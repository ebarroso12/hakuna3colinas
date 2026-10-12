import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/top_alert.dart';
import '../offline/cache_local.dart';
import '../offline/outbox.dart';
import '../offline/sync_service.dart';
import '../offline/tabelas.dart';
import 'supabase_service.dart';

/// Alarme do Top: disparo e recebimento.
///
/// Dois defeitos sérios viviam aqui, e os dois eram do mesmo tipo — a
/// função mais crítica do app era a menos protegida.
///
/// **Disparo.** `sendTopAlert` era `insert` direto no Supabase. Sem sinal
/// — o estado normal na trilha — o alarme falhava e era **descartado**,
/// com um aviso na tela e nada mais. Era a única escrita do app sem
/// caminho offline, justamente a que não pode se perder. Agora entra na
/// fila como qualquer outra coisa, com `client_id` para o reenvio não
/// duplicar e com a **hora do aparelho**, não `now()` do Postgres: offline
/// o acidente aconteceu horas antes do upload, e registrar a hora do
/// upload apagaria a única informação que importa para reconstruir o
/// evento.
///
/// **Recebimento.** O alarme só existia como faixa vermelha dentro da tela
/// de detalhe do Top. Quem estivesse na lista de participantes, no chat ou
/// com o celular no bolso não recebia nada. Agora a assinatura é única e
/// do app inteiro, e a faixa aparece por cima de **qualquer** tela, com
/// vibração e som.
///
/// O QUE AINDA NÃO FAZ, e é limite real: com o app **fechado** nada
/// chega. Notificação de app fechado exige FCM (Firebase) — projeto,
/// `google-services.json` e um serviço no servidor para disparar o push.
/// Não está feito. Em campo isso significa que o alarme serve para quem
/// está com o app aberto; para quem não está, continua valendo o rádio.
class AlarmeService extends ChangeNotifier {
  AlarmeService._();

  static final AlarmeService instance = AlarmeService._();

  static const entidade = 'top_alerts';

  /// Por quanto tempo um alarme continua na tela.
  ///
  /// Uma hora, o mesmo que a faixa antiga usava. Mais que isso e a tela
  /// fica poluída com alarme já resolvido; menos e quem pegou o celular
  /// 20 minutos depois não vê que houve um.
  static const janela = Duration(hours: 1);

  StreamSubscription<List<TopAlert>>? _assinatura;

  /// O que veio do servidor. Substituído inteiro a cada tique do stream.
  final List<TopAlert> _recebidos = [];

  /// O que chegou pelo **rádio**, sem passar por servidor nenhum.
  ///
  /// Lista separada porque `_recebidos` é sobrescrita a cada atualização
  /// do Realtime — guardar alarme de rádio lá o apagaria no primeiro
  /// instante em que a rede voltasse, que é exatamente quando ele ainda
  /// importa.
  final List<TopAlert> _porRadio = [];

  /// Chaves descartadas pelo usuário. Texto e não número: alarme de rádio
  /// não tem id do Postgres. Ver [TopAlert.chave].
  final Set<String> _descartados = {};

  /// Chaves já anunciadas (som + vibração). Sem isto, cada atualização do
  /// stream reanunciaria a lista inteira — e, pior, o mesmo alarme
  /// chegando pelo rádio e depois pelo servidor tocaria duas vezes.
  final Set<String> _anunciados = {};

  /// Como mandar o alarme pelos aparelhos próximos.
  ///
  /// Injetado por `MalhaService` ao ligar a malha e limpo ao desligar. É
  /// um gancho e não um import para o caminho do disparo não depender do
  /// plugin de rádio: sem malha ligada, `null`, e o alarme segue só pela
  /// fila como antes.
  ///
  /// Devolve **quantos aparelhos estavam ao alcance** no momento do
  /// disparo. Isso NÃO é confirmação de entrega: a malha é broadcast sem
  /// reconhecimento, então o número diz para quantos se falou, nunca
  /// quantos ouviram.
  Future<int> Function({
    required String clientId,
    required String corpo,
    required DateTime criadaEm,
    double? latitude,
    double? longitude,
  })?
  espalharPeloRadio;

  /// Em qual Top a malha esta ligada, ou null.
  ///
  /// Injetado junto com [espalharPeloRadio]. A malha e ligada POR TOP
  /// (`botao_da_malha.dart`), e sem esta conferencia um alarme do Top B
  /// sairia pelo radio carimbado com o Top A — os aparelhos do Top A o
  /// aceitariam como se fosse deles, e o do Top B nao receberia nada.
  /// Carimbo errado em alarme manda socorro para o evento errado.
  String? topDaMalha;

  /// Teto de espera do radio no disparo.
  ///
  /// `TransporteNearby.enviar` faz um `await` por vizinho, em laco. Com
  /// varios aparelhos ou um radio lento, a TELA ficaria esperando — e
  /// nesse ponto o alarme JA esta gravado na fila. Esperar o radio so
  /// tira segundos de quem precisa agir. Estourado o teto, o envio segue
  /// sozinho em segundo plano e a tela diz que nao deu para confirmar.
  /// Nao e `const` para o teste poder encurta-lo: medir o estouro do teto
  /// com 3 segundos de espera de verdade seria teste lento por nada. Mesma
  /// costura de [anunciarLigado] e `idDeUsuarioParaTestes`.
  static Duration limiteDoRadio = const Duration(seconds: 3);

  /// Só para teste: evita tentar tocar som sem binding de plataforma.
  @visibleForTesting
  static bool anunciarLigado = true;

  /// Alarmes que a tela deve mostrar agora.
  List<TopAlert> get ativos {
    final corte = DateTime.now().subtract(janela);
    final porChave = <String, TopAlert>{};
    // Rádio primeiro, servidor depois: quando o MESMO alarme chega pelos
    // dois caminhos (mesmo `client_id`), o do servidor é o que fica. Ele
    // tem autoria confirmada; o do rádio não, e mostrar a versão não
    // confirmada quando existe a confirmada seria perder informação.
    for (final a in [..._porRadio, ..._recebidos]) {
      if (_descartados.contains(a.chave)) continue;
      if (!a.createdAt.isAfter(corte)) continue;
      porChave[a.chave] = a;
    }
    return porChave.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  void registrarUploader() {
    SyncService.instance.registerUploader(entidade, (entrada) async {
      await SupabaseService.instance.enviarAlarme(entrada.payload);
    });
  }

  /// Enfileira o alarme. Devolve o `client_id`, que já identifica o
  /// disparo antes de ele existir no servidor.
  ///
  /// Não lança por falta de rede: a entrada fica na fila e sobe depois. O
  /// que a tela precisa dizer ao Hakuna é se já **saiu** ou se está
  /// esperando sinal — ver [SyncService.pendentes].
  Future<DisparoDeAlarme> disparar({
    required String topId,
    String? mensagem,
    double? latitude,
    double? longitude,
  }) async {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) {
      throw StateError('Sessão expirada — não é possível disparar o alarme');
    }
    final clientId = Outbox.novoClientId();
    final nome = await nomeDeQuemDispara();
    final quando = DateTime.now().toUtc();
    await Outbox.instance.enqueue(
      entity: entidade,
      topId: topId,
      clientId: clientId,
      payload: {
        'client_id': clientId,
        'top_id': topId,
        'sender_id': uid,
        // QUEM ESTÁ CHAMANDO viaja dentro do alarme.
        //
        // `profiles` é fechada para quem recebe (`id = auth.uid() or
        // is_admin()`), então o destinatário não tem como resolver o uuid.
        // Lido do cache local porque o disparo precisa funcionar sem rede
        // — buscar o perfil aqui transformaria a função mais crítica do
        // app numa que depende de sinal.
        'sender_name': nome,
        'message': mensagem,
        'latitude': latitude,
        'longitude': longitude,
        // Hora do aparelho, não `now()` no Postgres.
        'created_at': quando.toIso8601String(),
      },
    );
    // Tenta sair AGORA. Com sinal, o alarme não espera o próximo tique do
    // sincronizador — numa emergência a diferença de 30 segundos importa.
    envioEmAndamento = SyncService.instance.syncNow();
    unawaited(envioEmAndamento!);

    // O rádio é caminho PARALELO, não alternativo. A fila continua sendo
    // o que garante que o alarme chegue a quem está longe quando houver
    // sinal; o rádio é o que faz chegar AGORA a quem está perto — que
    // numa emergência é exatamente quem pode socorrer.
    //
    // Falha aqui não desfaz nada: o alarme já está gravado na fila.
    var vizinhos = 0;
    var tentadoPorRadio = false;
    var malhaDeOutroTop = false;
    var radioDemorou = false;
    final espalhar = espalharPeloRadio;
    final topDoRadio = topDaMalha;

    if (espalhar != null && topDoRadio != null && topDoRadio != topId) {
      // Malha ligada, mas para OUTRO Top. Nao transmite: carimbar o
      // alarme com o Top errado e pior que nao transmitir, porque chega
      // a quem nao tem o que fazer e nao chega a quem tem.
      malhaDeOutroTop = true;
    } else if (espalhar != null) {
      tentadoPorRadio = true;
      try {
        vizinhos = await espalhar(
          clientId: clientId,
          corpo: linhaDeEmergencia(
            nome: nome,
            mensagem: mensagem,
            latitude: latitude,
            longitude: longitude,
          ),
          criadaEm: quando,
          latitude: latitude,
          longitude: longitude,
        ).timeout(limiteDoRadio);
      } on TimeoutException {
        // O envio continua em segundo plano; so nao da para dizer a
        // quantos chegou. A tela nao pode afirmar o que nao sabe.
        radioDemorou = true;
      } catch (_) {
        vizinhos = 0;
      }
    }

    return DisparoDeAlarme(
      clientId: clientId,
      tentadoPorRadio: tentadoPorRadio,
      vizinhosAoAlcance: vizinhos,
      malhaDeOutroTop: malhaDeOutroTop,
      radioDemorou: radioDemorou,
    );
  }

  /// A linha que viaja no `corpo` do pacote de rádio.
  ///
  /// Legível por gente de propósito. Aparelho com a v1.0.41/42 instalada
  /// não conhece `tipo` e lê o pacote como mensagem de chat — então o que
  /// ele mostra no chat geral é ESTE texto. Se fosse JSON interno, a
  /// pessoa veria `{"tipo":"alarme",...}` no chat e não entenderia que
  /// alguém pediu socorro.
  static String linhaDeEmergencia({
    String? nome,
    String? mensagem,
    double? latitude,
    double? longitude,
  }) {
    final quem = (nome == null || nome.trim().isEmpty)
        ? 'Alguém do Top'
        : nome.trim();
    // Sem coordenada, diz "sem posição". Nunca 0,0: é posição VÁLIDA, no
    // Atlântico, e usá-la como sentinela manda socorro para o oceano.
    final onde = (latitude != null && longitude != null)
        ? '${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}'
        : 'sem posição';
    final extra = (mensagem == null || mensagem.trim().isEmpty)
        ? ''
        : ' — ${mensagem.trim()}';
    return 'EMERGÊNCIA — $quem — $onde$extra';
  }

  /// Chegou um alarme pelo rádio, sem passar por servidor nenhum.
  ///
  /// Chamado por `MalhaService`. Entra **não confirmado**, e a faixa
  /// mostra isso: no rádio não há autenticação, e qualquer aparelho ao
  /// alcance pode afirmar o que quiser em nome de quem quiser.
  void receberAlarmeDoRadio(TopAlert alarme) {
    if (_porRadio.any((a) => a.chave == alarme.chave)) return;
    _porRadio.add(alarme);

    final corte = DateTime.now().subtract(janela);
    final meuId = SupabaseService.instance.currentUserId;
    if (!_anunciados.contains(alarme.chave) &&
        alarme.createdAt.isAfter(corte) &&
        // O próprio alarme volta pelo rádio quando um vizinho o repassa.
        // Sem isto, quem pediu socorro ouviria o próprio alarme tocar.
        alarme.senderId != meuId) {
      _anunciados.add(alarme.chave);
      _anunciar();
    }
    notifyListeners();
  }


  /// Nome de quem está logado, do cache local. Null até o primeiro login
  /// com sinal — e aí o alarme sai sem nome, que a faixa trata.
  ///
  /// Nunca devolve uuid como substituto: uuid na faixa de emergência
  /// ocupa a linha do nome e não ajuda ninguém a achar a pessoa.
  ///
  /// **Quem GRAVA é `SupabaseService.fetchMyProfile`**, no cache local, a
  /// cada carregamento de perfil. Fica lá e não aqui para não criar import
  /// circular — este arquivo já importa o serviço do Supabase.
  Future<String?> nomeDeQuemDispara() async {
    try {
      final nome = await CacheLocal.instance.lerEstado(ColunasEstado.meuNome);
      final limpo = nome?.trim();
      return (limpo == null || limpo.isEmpty) ? null : limpo;
    } catch (_) {
      // Falha de disco não pode impedir o disparo. Alarme sem nome é
      // muito melhor que alarme não enviado.
      return null;
    }
  }

  /// A tentativa de envio que [disparar] acabou de disparar.
  ///
  /// Em produção ninguém aguarda isto: o alarme já está gravado e a tela
  /// não pode travar esperando rede. Existe porque sem uma referência ao
  /// future não há como um teste afirmar que o envio foi tentado — ele
  /// mediria uma corrida, e teste que depende de corrida ou mente ou
  /// falha sozinho. Mesma ideia de `idDeUsuarioParaTestes`.
  @visibleForTesting
  Future<void>? envioEmAndamento;

  /// Liga a escuta de alarmes do app inteiro. Chamar depois do login.
  ///
  /// Uma assinatura só, sem filtro de Top: a RLS de `top_alerts` já
  /// devolve apenas os Tops em que o usuário é Hakuna liberado. Filtrar
  /// por Top aqui faria o alarme de um Top chegar só a quem estivesse
  /// com AQUELE Top aberto — que era exatamente o defeito.
  void escutar() {
    if (_assinatura != null) return;
    _assinatura = SupabaseService.instance.watchMeusAlarmes().listen(
      _receber,
      // Queda de rede não pode derrubar o app nem matar a assinatura
      // em silêncio para sempre. O Supabase reconecta sozinho; aqui só
      // não se deixa a exceção subir.
      onError: (_) {},
    );
  }

  void parar() {
    _assinatura?.cancel();
    _assinatura = null;
    _recebidos.clear();
    _porRadio.clear();
    _descartados.clear();
    _anunciados.clear();
  }

  void descartar(String chave) {
    _descartados.add(chave);
    notifyListeners();
  }

  /// Recebe a lista do stream e anuncia só o que é novo.
  void _receber(List<TopAlert> lista) {
    _recebidos
      ..clear()
      ..addAll(lista);

    final corte = DateTime.now().subtract(janela);
    final meuId = SupabaseService.instance.currentUserId;
    final novos = lista.where(
      (a) =>
          !_anunciados.contains(a.chave) &&
          a.createdAt.isAfter(corte) &&
          // Não anuncia o próprio alarme: quem disparou já sabe, e o
          // celular apitando na mão de quem pediu socorro é ruído.
          a.senderId != meuId,
    );
    for (final a in novos) {
      _anunciados.add(a.chave);
      _anunciar();
    }
    notifyListeners();
  }

  /// Som e vibração.
  ///
  /// `SystemSound` e `HapticFeedback` são do próprio Flutter — não há
  /// plugin de áudio no projeto, e acrescentar um só para isto não se
  /// paga. O custo é não poder escolher o som nem tocá-lo com o volume de
  /// mídia no mudo; é um aviso de que algo aconteceu, não uma sirene.
  void _anunciar() {
    if (!anunciarLigado) return;
    // Três toques espaçados, porque um só passa batido num bolso.
    for (var i = 0; i < 3; i++) {
      Future<void>.delayed(Duration(milliseconds: 600 * i), () {
        HapticFeedback.heavyImpact();
        SystemSound.play(SystemSoundType.alert);
      });
    }
  }

  /// Só para teste: injeta uma lista como se tivesse vindo do stream.
  @visibleForTesting
  void receberParaTestes(List<TopAlert> lista) => _receber(lista);

  @visibleForTesting
  void limparParaTestes() {
    _recebidos.clear();
    _porRadio.clear();
    _descartados.clear();
    _anunciados.clear();
    espalharPeloRadio = null;
    topDaMalha = null;
  }
}

/// O que aconteceu quando o alarme foi disparado.
///
/// Existe porque **guardado** e **entregue** são coisas diferentes, e numa
/// emergência confundi-las é o erro mais caro que a tela pode cometer. A
/// fila garante que o alarme não se perde; ela não garante que alguém
/// recebeu.
class DisparoDeAlarme {
  const DisparoDeAlarme({
    required this.clientId,
    required this.tentadoPorRadio,
    required this.vizinhosAoAlcance,
    this.malhaDeOutroTop = false,
    this.radioDemorou = false,
  });

  /// Identidade do disparo, já válida antes de existir no servidor.
  final String clientId;

  /// A malha estava ligada e o envio foi tentado por ela.
  final bool tentadoPorRadio;

  /// Quantos aparelhos estavam ao alcance no instante do disparo.
  ///
  /// **Não é confirmação de recebimento.** A malha é broadcast sem ACK:
  /// este número diz para quantos se falou, nunca quantos ouviram. A tela
  /// tem de dizer isso com essas palavras — "enviado a 2 aparelhos por
  /// perto" é honesto; "2 pessoas foram avisadas" é mentira.
  final int vizinhosAoAlcance;

  /// A malha estava ligada, mas para outro Top — nada foi transmitido.
  final bool malhaDeOutroTop;

  /// O radio nao respondeu dentro de [AlarmeService.limiteDoRadio]. O
  /// envio segue em segundo plano; nao da para dizer a quantos chegou.
  final bool radioDemorou;

  /// Frase pronta para a tela, escrita para não prometer entrega.
  String get resumo {
    if (malhaDeOutroTop) {
      return 'Alarme gravado, mas NÃO foi pelo rádio: o rádio entre '
          'aparelhos está ligado para OUTRO Top. Ninguém por perto foi '
          'avisado. Abra o chat DESTE Top e ligue o rádio lá.';
    }
    if (!tentadoPorRadio) {
      return 'Alarme gravado. Sobe assim que houver sinal. O rádio entre '
          'aparelhos está DESLIGADO — ligue-o para avisar quem está por '
          'perto agora.';
    }
    if (radioDemorou) {
      return 'Alarme gravado e entregue ao rádio, que ainda não respondeu. '
          'NÃO dá para confirmar se alguém por perto recebeu — confirme '
          'por voz. Também sobe assim que houver sinal.';
    }
    if (vizinhosAoAlcance == 0) {
      return 'Alarme gravado e transmitido por rádio, mas NENHUM aparelho '
          'estava ao alcance. Ninguém por perto foi avisado. Sobe assim '
          'que houver sinal.';
    }
    final quantos = vizinhosAoAlcance == 1
        ? '1 aparelho'
        : '$vizinhosAoAlcance aparelhos';
    return 'Alarme gravado e transmitido por rádio a $quantos ao alcance. '
        'O rádio NÃO confirma recebimento — confirme por voz. Também sobe '
        'assim que houver sinal.';
  }
}
