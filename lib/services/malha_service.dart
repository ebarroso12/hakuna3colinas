import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/team.dart';
import '../offline/cache_local.dart';
import '../offline/chat_repositorio.dart';
import '../offline/tabelas.dart';
import '../offline/transporte_local.dart';
import '../offline/transporte_nearby.dart';
import 'supabase_service.dart';

/// Liga as três peças da malha local: rádio, regra e disco.
///
/// - o **rádio** ([TransporteLocal]) só move bytes
/// - a **regra** ([RegrasDaMalha]) decide o que aceitar e repassar
/// - o **disco** ([CacheLocal]) guarda, marcado como não confirmado
///
/// Cada uma é substituível sem tocar nas outras. Trocar Nearby por LoRa
/// mexe só na primeira.
///
/// ## Desligado por padrão, e isso é decisão
///
/// `P2P_CLUSTER` mantém BLE e WiFi Direct ativos procurando vizinhos, e
/// isso consome bateria de verdade. Na trilha, bateria é recurso clínico:
/// um celular morto não registra atendimento nem dispara alarme.
///
/// Então ligar é ato explícito de quem está em campo e sabe que vai ficar
/// sem sinal — não uma otimização que o app faz sozinho pelas costas.
class MalhaService extends ChangeNotifier {
  MalhaService._();

  static final MalhaService instance = MalhaService._();

  /// Injetável para teste: a regra e o disco se provam sem rádio nenhum.
  @visibleForTesting
  TransporteLocal? transporteParaTestes;

  TransporteLocal? _transporte;
  RegrasDaMalha? _regras;
  StreamSubscription<List<int>>? _subRecebidos;
  StreamSubscription<int>? _subVizinhos;

  String? _topId;
  int _vizinhos = 0;
  int _recebidas = 0;
  int _repassadas = 0;
  String? _erro;

  bool get ligada => _transporte != null;
  int get vizinhos => _vizinhos;
  int get mensagensRecebidas => _recebidas;
  int get mensagensRepassadas => _repassadas;
  String? get erro => _erro;

  /// Só Android tem Nearby Connections. No iOS a tela mostra isto em vez
  /// de oferecer um botão que não faz nada.
  bool get disponivelNesteAparelho =>
      transporteParaTestes != null || TransporteNearby.disponivel;

  /// Liga a malha para um Top.
  ///
  /// Pede as permissões antes: sem elas o rádio simplesmente não acha
  /// ninguém, **sem erro**, e o usuário conclui que a função não serve.
  Future<bool> ligar({required String topId}) async {
    if (ligada) return true;
    _erro = null;

    if (!disponivelNesteAparelho) {
      _erro =
          'A malha por rádio é Android. Neste aparelho o app continua '
          'funcionando — só não troca mensagem com quem está perto.';
      notifyListeners();
      return false;
    }

    if (transporteParaTestes == null && !await _pedirPermissoes()) {
      _erro =
          'Sem permissão de Bluetooth, WiFi e localização a malha não '
          'acha ninguém. O Android exige localização para buscar '
          'aparelhos por perto, mesmo sem usar GPS.';
      notifyListeners();
      return false;
    }

    final transporte = transporteParaTestes ?? TransporteNearby();
    _regras = RegrasDaMalha(meuTopId: topId);
    _topId = topId;

    try {
      await transporte.ligar(meuNome: await _meuNome());
    } catch (e) {
      _erro = 'Não foi possível ligar a malha: $e';
      _regras = null;
      _topId = null;
      notifyListeners();
      return false;
    }

    _transporte = transporte;
    _subRecebidos = transporte.recebidos.listen(
      _aoReceber,
      // Erro no rádio não pode derrubar o app nem matar a escuta em
      // silêncio para sempre.
      onError: (_) {},
    );
    _subVizinhos = transporte.vizinhos.listen((n) {
      _vizinhos = n;
      notifyListeners();
    }, onError: (_) {});

    notifyListeners();
    return true;
  }

  Future<void> desligar() async {
    final t = _transporte;
    _transporte = null;
    _regras = null;
    _topId = null;
    _vizinhos = 0;
    // Zera os contadores junto. Eles descrevem ESTA sessão de malha; se
    // sobrevivessem ao desligar, a tela mostraria "12 recebidas" de um
    // turno anterior e quem lê concluiria que a malha está entregando
    // agora. Número velho apresentado como atual é pior que nenhum.
    _recebidas = 0;
    _repassadas = 0;
    _erro = null;
    await _subRecebidos?.cancel();
    await _subVizinhos?.cancel();
    _subRecebidos = null;
    _subVizinhos = null;
    await t?.desligar();
    notifyListeners();
  }

  /// Manda uma mensagem que o próprio usuário escreveu.
  ///
  /// Não grava no cache: ela já está na fila do aparelho e já aparece na
  /// tela por lá. O que se faz aqui é marcar o `client_id` como conhecido,
  /// para a própria mensagem não voltar da malha como novidade e
  /// duplicar.
  Future<void> espalhar({
    required String clientId,
    required TeamKey? team,
    required String corpo,
    required DateTime criadaEm,
  }) async {
    final transporte = _transporte;
    final regras = _regras;
    final topId = _topId;
    if (transporte == null || regras == null || topId == null) return;

    final meuId = SupabaseService.instance.currentUserId;
    if (meuId == null) return;

    regras.jaConheco(clientId);

    final pacote = PacoteLocal(
      clientId: clientId,
      topId: topId,
      team: team,
      autorId: meuId,
      autorNome: await _meuNome(),
      corpo: corpo,
      criadaEm: criadaEm,
    );

    try {
      await transporte.enviar(pacote.paraBytes());
    } catch (_) {
      // Falha no rádio não pode derrubar o envio: a mensagem está na
      // fila e sobe pelo servidor quando houver sinal. A malha é um
      // caminho a mais, não o único.
    }
  }

  /// Chegou algo pelo rádio.
  Future<void> _aoReceber(List<int> bytes) async {
    final regras = _regras;
    final transporte = _transporte;
    if (regras == null || transporte == null) return;

    final pacote = PacoteLocal.deBytes(bytes);
    final decisao = regras.decidir(pacote);
    if (decisao != Decisao.aceitar || pacote == null) return;

    try {
      final nova = await CacheLocal.instance.salvarMensagemDoRadio(
        entidade: ChatRepositorio.entityTeam,
        clientId: pacote.clientId,
        topId: pacote.topId,
        team: pacote.team?.name,
        autorId: pacote.autorId,
        autorNome: pacote.autorNome,
        corpo: pacote.corpo,
        criadaEm: pacote.criadaEm,
      );
      if (nova) {
        _recebidas++;
        // Acorda os chats abertos: a mensagem entrou no disco, e sem
        // isto só apareceria na próxima vez que a tela fosse montada.
        ChatRepositorio.instance.avisarQueMudou();
      }
    } catch (_) {
      // Disco cheio ou banco travado não pode calar o rádio. A mensagem
      // se perde; a próxima não.
    }

    if (regras.deveRepassar(decisao, pacote)) {
      try {
        await transporte.enviar(pacote.maisUmSalto().paraBytes());
        _repassadas++;
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Nome para aparecer como vizinho e assinar o que se manda.
  ///
  /// Do cache local, pelo mesmo motivo do alarme: `profiles` é fechada
  /// para quem recebe e sem rede não há como resolver uuid em nome.
  Future<String> _meuNome() async {
    try {
      final nome = await CacheLocal.instance.lerEstado(ColunasEstado.meuNome);
      final limpo = nome?.trim();
      if (limpo != null && limpo.isNotEmpty) return limpo;
    } catch (_) {}
    return 'Alguém do Top';
  }

  /// As permissões que o Android exige para achar aparelhos por perto.
  ///
  /// `location` entra mesmo sem usar GPS: o Android trata varredura de
  /// Bluetooth e WiFi como capaz de revelar onde a pessoa está, e sem ela
  /// a busca devolve lista vazia **sem erro nenhum** — o pior modo de
  /// falhar, porque parece que a função não existe.
  Future<bool> _pedirPermissoes() async {
    final pedidos = await [
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices,
      Permission.location,
    ].request();

    // `nearbyWifiDevices` não existe antes do Android 13 e volta
    // `permanentlyDenied` lá — o que não é recusa do usuário, é a
    // permissão não existir naquela versão. Tratar como impedimento
    // bloquearia a malha em todo aparelho mais antigo.
    return pedidos.entries
        .where((e) => e.key != Permission.nearbyWifiDevices)
        .every((e) => e.value.isGranted);
  }
}
