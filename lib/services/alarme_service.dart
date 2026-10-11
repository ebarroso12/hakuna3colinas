import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/top_alert.dart';
import '../offline/outbox.dart';
import '../offline/sync_service.dart';
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
  final List<TopAlert> _recebidos = [];
  final Set<int> _descartados = {};

  /// Ids já anunciados (som + vibração). Sem isto, cada atualização do
  /// stream reanunciaria a lista inteira.
  final Set<int> _anunciados = {};

  /// Só para teste: evita tentar tocar som sem binding de plataforma.
  @visibleForTesting
  static bool anunciarLigado = true;

  /// Alarmes que a tela deve mostrar agora.
  List<TopAlert> get ativos {
    final corte = DateTime.now().subtract(janela);
    return _recebidos
        .where(
          (a) => !_descartados.contains(a.id) && a.createdAt.isAfter(corte),
        )
        .toList();
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
  Future<String> disparar({
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
    await Outbox.instance.enqueue(
      entity: entidade,
      topId: topId,
      clientId: clientId,
      payload: {
        'client_id': clientId,
        'top_id': topId,
        'sender_id': uid,
        'message': mensagem,
        'latitude': latitude,
        'longitude': longitude,
        // Hora do aparelho, não `now()` no Postgres.
        'created_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
    // Tenta sair AGORA. Com sinal, o alarme não espera o próximo tique do
    // sincronizador — numa emergência a diferença de 30 segundos importa.
    envioEmAndamento = SyncService.instance.syncNow();
    unawaited(envioEmAndamento!);
    return clientId;
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
    _descartados.clear();
    _anunciados.clear();
  }

  void descartar(int id) {
    _descartados.add(id);
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
          !_anunciados.contains(a.id) &&
          a.createdAt.isAfter(corte) &&
          // Não anuncia o próprio alarme: quem disparou já sabe, e o
          // celular apitando na mão de quem pediu socorro é ruído.
          a.senderId != meuId,
    );
    for (final a in novos) {
      _anunciados.add(a.id);
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
    _descartados.clear();
    _anunciados.clear();
  }
}
