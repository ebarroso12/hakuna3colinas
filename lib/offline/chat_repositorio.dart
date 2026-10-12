import 'dart:async';

import '../models/chat_message.dart';
import '../models/team.dart';
import '../models/team_message.dart';
import '../services/supabase_service.dart';
import 'cache_local.dart';
import 'outbox.dart';
import 'sync_service.dart';

/// O que a tela de chat precisa saber, de uma vez.
///
/// Três informações distintas num objeto só porque separar causaria estado
/// inconsistente na tela: contar pendentes de uma lista que já foi
/// substituída mostra número errado.
class ChatNaTela<T> {
  /// Servidor + fila local, em ordem cronológica.
  final List<T> mensagens;

  /// Quantas ainda estão na fila do aparelho.
  final int pendentes;

  /// Última falha do canal de tempo real, se houver.
  ///
  /// Separado das mensagens de propósito: sem rede, o certo é mostrar as
  /// mensagens que já se tem **e** avisar que o chat está parado. A versão
  /// anterior trocava a lista inteira por uma tela de erro — o Hakuna
  /// perdia o acesso ao que já havia sido dito.
  final Object? erroDeRede;

  const ChatNaTela({
    required this.mensagens,
    required this.pendentes,
    this.erroDeRede,
  });

  bool get offline => erroDeRede != null;
}

/// Chat com fila offline, igual a atendimento e posição.
///
/// **O que estava errado:** `sendTeamMessage` e `sendTopMessage` faziam
/// `insert` direto no Supabase. Em campo isso significa: sem sinal, a
/// mensagem simplesmente **não existe** — o Hakuna digita, vê um erro
/// vermelho e o texto fica no campo. Com sinal oscilando é pior, porque o
/// insert pode ter chegado e a resposta não, e ele reenvia.
///
/// Agora a mensagem entra na fila local e aparece na tela na hora, marcada
/// como pendente. O [SyncService] sobe quando houver sinal.
///
/// **Por que o chat não é append-only como o atendimento:** o atendimento é
/// registro clínico e não se edita. Mensagem de chat pode ser apagada por
/// coordenador (há policy de DELETE). Isso não muda a fila: ela só trata
/// de envio.
class ChatRepositorio {
  ChatRepositorio._();

  static final ChatRepositorio instance = ChatRepositorio._();

  static const entityTeam = 'team_messages';
  static const entityTop = 'top_hakuna_messages';

  /// Avisa os streams abertos que a fila mudou.
  ///
  /// O stream do Supabase só reage a mudança **no servidor**; uma mensagem
  /// que acabou de entrar na fila local não dispara nada lá. Sem este
  /// controller, a mensagem enviada offline só apareceria na tela quando o
  /// Hakuna saísse e voltasse.
  final _filaMudou = StreamController<void>.broadcast();

  void registrarUploaders() {
    SyncService.instance.registerUploader(entityTeam, (entrada) async {
      await SupabaseService.instance.enviarMensagemEquipe(entrada.payload);
      // Subiu: o realtime vai trazer a versão do servidor, e a pendente
      // precisa sair da tela no mesmo instante — senão a mensagem aparece
      // duas vezes até a próxima reconstrução.
      _filaMudou.add(null);
    });
    SyncService.instance.registerUploader(entityTop, (entrada) async {
      await SupabaseService.instance.enviarMensagemTop(entrada.payload);
      _filaMudou.add(null);
    });
  }

  // =====================================================================
  // ENVIO
  // =====================================================================

  /// Enfileira mensagem de equipe. Devolve a mensagem como ela aparece na
  /// tela antes de existir no servidor.
  ///
  /// Só lança se falhar a gravação no **próprio aparelho** — aí é disco
  /// cheio ou banco corrompido, e o Hakuna precisa saber que a mensagem não
  /// foi guardada em lugar nenhum.
  Future<TeamMessage> enviarParaEquipe({
    required String topId,
    required TeamKey team,
    required String body,
    bool isAlert = false,
  }) async {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) {
      throw StateError('Sessão expirada — não é possível enviar mensagem');
    }

    final clientId = Outbox.novoClientId();
    final agora = DateTime.now();

    await Outbox.instance.enqueue(
      entity: entityTeam,
      topId: topId,
      clientId: clientId,
      payload: {
        'client_id': clientId,
        'top_id': topId,
        'team': team.name,
        'sender_id': uid,
        'body': body,
        'is_alert': isAlert,
        // Hora do aparelho: offline a mensagem é escrita muito antes de
        // subir, e deixar o Postgres preencher `now()` colocaria a
        // mensagem fora de ordem no histórico da equipe.
        'created_at': agora.toUtc().toIso8601String(),
      },
    );

    _filaMudou.add(null);
    unawaited(SyncService.instance.syncNow());

    return TeamMessage(
      clientId: clientId,
      topId: topId,
      team: team,
      senderId: uid,
      body: body,
      createdAt: agora,
      isAlert: isAlert,
    );
  }

  Future<ChatMessage> enviarParaTop({
    required String topId,
    required String body,
  }) async {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) {
      throw StateError('Sessão expirada — não é possível enviar mensagem');
    }

    final clientId = Outbox.novoClientId();
    final agora = DateTime.now();

    await Outbox.instance.enqueue(
      entity: entityTop,
      topId: topId,
      clientId: clientId,
      payload: {
        'client_id': clientId,
        'top_id': topId,
        'sender_id': uid,
        'body': body,
        'created_at': agora.toUtc().toIso8601String(),
      },
    );

    _filaMudou.add(null);
    unawaited(SyncService.instance.syncNow());

    return ChatMessage(
      clientId: clientId,
      topId: topId,
      senderId: uid,
      body: body,
      createdAt: agora,
    );
  }

  // =====================================================================
  // LEITURA
  // =====================================================================

  Stream<ChatNaTela<TeamMessage>> observarEquipe({
    required String topId,
    required TeamKey team,
  }) {
    return _observar<TeamMessage>(
      doServidor: SupabaseService.instance
          .watchTeamMessages(topId: topId, team: team)
          .asyncMap((lista) => _guardar(entityTeam, lista, _teamParaMapa)),
      lerDoCache: () async {
        final linhas = await CacheLocal.instance.lerMensagens(
          entidade: entityTeam,
          topId: topId,
          team: team.name,
        );
        return linhas.map(TeamMessage.fromMap).toList();
      },
      lerPendentes: () => _pendentesDeEquipe(topId, team),
      quando: (m) => m.createdAt,
      clientIdDe: (m) => m.clientId,
    );
  }

  Stream<ChatNaTela<ChatMessage>> observarTop(String topId) {
    return _observar<ChatMessage>(
      doServidor: SupabaseService.instance
          .watchTopMessages(topId)
          .asyncMap((lista) => _guardar(entityTop, lista, _topParaMapa)),
      lerDoCache: () async {
        final linhas = await CacheLocal.instance.lerMensagens(
          entidade: entityTop,
          topId: topId,
        );
        return linhas.map(ChatMessage.fromMap).toList();
      },
      lerPendentes: () => _pendentesDoTop(topId),
      quando: (m) => m.createdAt,
      clientIdDe: (m) => m.clientId,
    );
  }

  /// Grava no disco o que chegou do servidor e devolve a lista intacta.
  ///
  /// A rede alimenta o disco, o disco alimenta a tela — a mesma regra que
  /// vale para participantes e tags, agora para a conversa.
  ///
  /// **Falha de disco não derruba o chat.** Com rede, o cache é só a
  /// cópia; a lista já está na mão e vai para a tela de qualquer forma.
  /// Derrubar o stream aqui tiraria do ar a conversa que estava
  /// funcionando, para proteger uma cópia que só importa depois.
  Future<List<T>> _guardar<T>(
    String entidade,
    List<T> lista,
    Map<String, Object?> Function(T) paraMapa,
  ) async {
    try {
      await CacheLocal.instance.salvarMensagens(
        entidade: entidade,
        linhas: lista.map(paraMapa).toList(),
      );
    } catch (_) {}
    return lista;
  }

  static Map<String, Object?> _teamParaMapa(TeamMessage m) => {
    'id': m.id,
    'client_id': m.clientId,
    'top_id': m.topId,
    'team': m.team.name,
    'sender_id': m.senderId,
    'body': m.body,
    'is_alert': m.isAlert,
    'created_at': m.createdAt.toIso8601String(),
    'edited_at': m.editedAt?.toIso8601String(),
  };

  /// `team` fica null: o chat clínico não é por equipe, e é isso que
  /// separa as duas conversas dentro da mesma tabela local.
  static Map<String, Object?> _topParaMapa(ChatMessage m) => {
    'id': m.id,
    'client_id': m.clientId,
    'top_id': m.topId,
    'team': null,
    'sender_id': m.senderId,
    'body': m.body,
    'is_alert': false,
    'created_at': m.createdAt.toIso8601String(),
    'edited_at': null,
  };

  /// Junta servidor + fila numa lista só, sem duplicar e em ordem.
  ///
  /// Função pura, separada do stream de propósito: é aqui que mora o risco
  /// real desta classe. Entre o upload da mensagem e a limpeza da fila, a
  /// mesma mensagem existe nos dois lados — e sem a deduplicação por
  /// `client_id` ela apareceria **duas vezes** na tela do chat.
  ///
  /// A deduplicação é pelo lado do servidor: quem está no servidor manda,
  /// e a cópia pendente é descartada. Nunca o contrário — a versão do
  /// servidor é a que todos os outros Hakunas estão vendo.
  ///
  /// Mensagem antiga (anterior à v1.0.18) tem `client_id` null e não
  /// participa da deduplicação. Isso é correto: ela nunca esteve na fila,
  /// então não há par para casar.
  static ChatNaTela<T> juntar<T>({
    required List<T> doServidor,
    required List<T> pendentes,
    required DateTime Function(T) quando,
    required String? Function(T) clientIdDe,
    Object? erroDeRede,
  }) {
    final idsNoServidor = doServidor
        .map(clientIdDe)
        .whereType<String>()
        .toSet();

    final aindaPendentes = pendentes.where((m) {
      final id = clientIdDe(m);
      // Pendente sem client_id não deveria existir (o repositório sempre
      // gera um), mas se existir é mais seguro mostrar que esconder: uma
      // mensagem a mais na tela é visível e corrigível; uma mensagem que
      // o Hakuna acha que mandou e sumiu, não.
      return id == null || !idsNoServidor.contains(id);
    }).toList();

    final todas = [...doServidor, ...aindaPendentes]
      ..sort((a, b) => quando(a).compareTo(quando(b)));

    return ChatNaTela(
      mensagens: todas,
      pendentes: aindaPendentes.length,
      erroDeRede: erroDeRede,
    );
  }

  /// Junta o stream do servidor com a fila local.
  ///
  /// Três gatilhos de reemissão, e cada um existe por um motivo:
  ///   1. o stream do servidor emitiu (mensagem nova de outra pessoa);
  ///   2. a fila mudou (enviei algo, ou algo subiu);
  ///   3. o status da sincronização mudou (voltou o sinal).
  ///
  /// Sem o 2, mensagem enviada offline não apareceria. Sem o 3, a mensagem
  /// ficaria marcada como pendente na tela mesmo depois de subir, até a
  /// próxima mensagem de alguém.
  Stream<ChatNaTela<T>> _observar<T>({
    required Stream<List<T>> doServidor,
    required Future<List<T>> Function() lerDoCache,
    required Future<List<T>> Function() lerPendentes,
    required DateTime Function(T) quando,
    required String? Function(T) clientIdDe,
  }) {
    late StreamController<ChatNaTela<T>> controller;
    var doServidorAtual = <T>[];

    /// O servidor ainda não respondeu NADA nesta assinatura.
    ///
    /// Diferente de "respondeu lista vazia": sem rede o stream do Supabase
    /// não emite nem erro imediato, só fica calado. Enquanto estiver
    /// calado, o que vale é o disco.
    var servidorRespondeu = false;
    Object? erro;
    StreamSubscription<List<T>>? subServidor;
    StreamSubscription<void>? subFila;
    StreamSubscription<SyncStatus>? subSync;

    Future<void> emitir() async {
      if (controller.isClosed) return;
      List<T> pendentes;
      try {
        pendentes = await lerPendentes();
      } catch (_) {
        pendentes = const [];
      }

      // Sem rede o stream do Supabase fica CALADO — não emite lista vazia
      // nem erro imediato. Até ele falar, a conversa vem do disco; depois,
      // o servidor manda, porque é ele que tem as mensagens novas.
      //
      // Antes da v1.0.41 não havia disco: offline, a tela mostrava apenas
      // o que o próprio usuário tinha escrito, e a conversa da equipe
      // sumia. Quem chega ao acampamento sem sinal é justamente quem mais
      // precisa ler o que foi combinado enquanto estava fora.
      var base = doServidorAtual;
      if (!servidorRespondeu) {
        try {
          base = await lerDoCache();
        } catch (_) {
          base = const [];
        }
      }

      if (controller.isClosed) return;
      controller.add(
        juntar<T>(
          doServidor: base,
          pendentes: pendentes,
          quando: quando,
          clientIdDe: clientIdDe,
          erroDeRede: erro,
        ),
      );
    }

    controller = StreamController<ChatNaTela<T>>(
      onListen: () {
        subServidor = doServidor.listen(
          (lista) {
            doServidorAtual = lista;
            servidorRespondeu = true;
            erro = null;
            unawaited(emitir());
          },
          // NÃO propaga o erro: sem rede a tela continua mostrando o que
          // já tem, com o aviso de offline. Propagar faria o StreamBuilder
          // ir para `hasError` e esconder o histórico inteiro.
          onError: (Object e) {
            erro = e;
            unawaited(emitir());
          },
        );
        subFila = _filaMudou.stream.listen((_) => unawaited(emitir()));
        subSync = SyncService.instance.statusStream.listen(
          (_) => unawaited(emitir()),
        );
        // Emite na hora, antes de a rede responder: offline é isto que
        // coloca o histórico pendente na tela em vez de um spinner eterno.
        unawaited(emitir());
      },
      onCancel: () async {
        await subServidor?.cancel();
        await subFila?.cancel();
        await subSync?.cancel();
      },
    );

    return controller.stream;
  }

  Future<List<TeamMessage>> _pendentesDeEquipe(
    String topId,
    TeamKey team,
  ) async {
    final entradas = await Outbox.instance.pending(
      entity: entityTeam,
      limit: 500,
    );
    return entradas
        .where((e) => e.topId == topId && e.payload['team'] == team.name)
        .map((e) => TeamMessage.fromMap(e.payload))
        .toList();
  }

  Future<List<ChatMessage>> _pendentesDoTop(String topId) async {
    final entradas = await Outbox.instance.pending(
      entity: entityTop,
      limit: 500,
    );
    return entradas
        .where((e) => e.topId == topId)
        .map((e) => ChatMessage.fromMap(e.payload))
        .toList();
  }

  /// Total de mensagens esperando sinal, de todos os chats.
  Future<int> pendentesDeEnvio() async {
    final equipe = await Outbox.instance.pendingCount(entity: entityTeam);
    final top = await Outbox.instance.pendingCount(entity: entityTop);
    return equipe + top;
  }
}
