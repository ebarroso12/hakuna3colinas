import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nearby_connections/nearby_connections.dart';

import 'transporte_local.dart';

/// [TransporteLocal] em cima da Nearby Connections do Google (BLE +
/// WiFi Direct + hotspot), **sem internet nenhuma**.
///
/// ## O que esta classe NÃO faz, e é de propósito
///
/// Dedupe, validação, limite de saltos e a decisão de repassar não moram
/// aqui — moram em `transporte_local.dart`, que não importa plugin
/// nenhum e por isso é testável sem dois aparelhos. Aqui ficam só os
/// bytes e o rádio.
///
/// Essa separação é o que permite trocar isto por LoRa sem reescrever a
/// regra, e é o que impede o risco do plugin virar risco do app.
///
/// ## Os riscos herdados, escritos porque são reais
///
/// - **Android apenas.** No iOS a classe inteira se recusa a ligar, com
///   mensagem — ver [disponivel]. O app roda nos dois.
/// - **O plugin estava 19 meses sem publicar** em 12/10/2026 (4.3.0).
/// - **P2P_CLUSTER consome rádio e bateria.** Por isso [ligar] é
///   explícito e nunca automático: na trilha, bateria é recurso clínico.
///
/// ## Por que P2P_CLUSTER
///
/// Das três estratégias, é a única em que **todos falam com todos**.
/// `P2P_STAR` elegeria um centro — e numa trilha o "centro" é quem se
/// afastou. `P2P_POINT_TO_POINT` liga dois aparelhos só.
class TransporteNearby implements TransporteLocal {
  TransporteNearby({this.idDoServico = 'com.legendarios.hakuna_connect'});

  /// Separa a malha dos Legendários de qualquer outro app usando a mesma
  /// API no mesmo lugar. O padrão do plugin é um id de exemplo, que
  /// deixaria aparelhos de outros apps aparecendo como vizinhos.
  final String idDoServico;

  /// Nearby Connections é Android. No iOS nada disto existe.
  static bool get disponivel =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  final _recebidos = StreamController<List<int>>.broadcast();
  final _vizinhos = StreamController<int>.broadcast();

  /// Endpoints conectados AGORA. É daqui que sai a contagem de vizinhos
  /// e é para estes que [enviar] manda.
  final _conectados = <String>{};

  bool _ligado = false;

  @override
  Stream<List<int>> get recebidos => _recebidos.stream;

  @override
  Stream<int> get vizinhos => _vizinhos.stream;

  bool get ligado => _ligado;

  @override
  Future<void> ligar({required String meuNome}) async {
    if (_ligado) return;
    if (!disponivel) {
      throw UnsupportedError(
        'A malha local é Android. Neste aparelho o app continua '
        'funcionando normalmente — só não troca mensagem por rádio.',
      );
    }

    // Anuncia E procura ao mesmo tempo. Quem só anuncia nunca acha
    // ninguém; quem só procura nunca é achado. Na trilha não há como
    // combinar quem faz o quê.
    await Nearby().startAdvertising(
      meuNome,
      Strategy.P2P_CLUSTER,
      serviceId: idDoServico,
      onConnectionInitiated: _aoIniciarConexao,
      onConnectionResult: _aoResultado,
      onDisconnected: _aoDesconectar,
    );

    await Nearby().startDiscovery(
      meuNome,
      Strategy.P2P_CLUSTER,
      serviceId: idDoServico,
      onEndpointFound: (id, nome, servico) {
        // Aceita qualquer um que esteja rodando este app. Filtrar por
        // pessoa aqui não faria sentido: numa emergência, quem está perto
        // é quem importa, e a RLS continua valendo quando a mensagem
        // subir — ver `transporte_local.dart`.
        Nearby().requestConnection(
          meuNome,
          id,
          onConnectionInitiated: _aoIniciarConexao,
          onConnectionResult: _aoResultado,
          onDisconnected: _aoDesconectar,
        );
      },
      onEndpointLost: (id) {
        if (id != null && _conectados.remove(id)) _anunciarVizinhos();
      },
    );

    _ligado = true;
  }

  void _aoIniciarConexao(String id, ConnectionInfo info) {
    // Aceita sem pedir confirmação ao usuário, de propósito: numa
    // emergência ninguém vai parar para aprovar pareamento. A proteção
    // não está aqui — está no fato de a mensagem chegar marcada como NÃO
    // confirmada até o servidor autenticá-la.
    Nearby().acceptConnection(
      id,
      onPayLoadRecieved: (endpointId, payload) {
        final bytes = payload.bytes;
        if (bytes != null && !_recebidos.isClosed) {
          _recebidos.add(bytes);
        }
      },
      // Só usamos payload de BYTES. `FILE` e `STREAM` não entram: a
      // malha carrega mensagem curta, e aceitar arquivo de origem não
      // autenticada é porta que não precisa existir.
      onPayloadTransferUpdate: (endpointId, update) {},
    );
  }

  void _aoResultado(String id, Status status) {
    if (status == Status.CONNECTED) {
      _conectados.add(id);
    } else {
      _conectados.remove(id);
    }
    _anunciarVizinhos();
  }

  void _aoDesconectar(String id) {
    _conectados.remove(id);
    _anunciarVizinhos();
  }

  void _anunciarVizinhos() {
    if (!_vizinhos.isClosed) _vizinhos.add(_conectados.length);
  }

  @override
  Future<void> enviar(List<int> bytes) async {
    if (!_ligado || _conectados.isEmpty) return;
    final dados = Uint8List.fromList(bytes);

    // Um envio por endpoint, e a falha de um NÃO impede os outros. Se o
    // aparelho de alguém saiu de alcance no meio, isso não pode calar a
    // mensagem para o resto da equipe.
    for (final id in _conectados.toList()) {
      try {
        await Nearby().sendBytesPayload(id, dados);
      } catch (_) {
        _conectados.remove(id);
      }
    }
    _anunciarVizinhos();
  }

  @override
  Future<void> desligar() async {
    if (!_ligado) return;
    _ligado = false;
    try {
      await Nearby().stopDiscovery();
      await Nearby().stopAdvertising();
      await Nearby().stopAllEndpoints();
    } catch (_) {
      // Desligar não pode falhar de um jeito que trave a tela. O rádio
      // cai junto com o processo de qualquer forma.
    }
    _conectados.clear();
    _anunciarVizinhos();
  }

  Future<void> dispose() async {
    await desligar();
    await _recebidos.close();
    await _vizinhos.close();
  }
}
