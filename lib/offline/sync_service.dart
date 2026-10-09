import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'outbox.dart';

/// Como uma entrada da fila vira uma escrita no servidor.
///
/// Cada entidade registra a sua: posição, atendimento, etc. Manter isso
/// fora do [SyncService] deixa a sincronização testável sem Supabase.
typedef OutboxUploader = Future<void> Function(OutboxEntry entry);

enum SyncStatus { parado, aguardandoSinal, sincronizando, emDia, comErro }

class SyncReport {
  final int enviados;
  final int falharam;
  final int aindaPendentes;
  final Object? ultimoErro;

  const SyncReport({
    required this.enviados,
    required this.falharam,
    required this.aindaPendentes,
    this.ultimoErro,
  });

  bool get tudoCerto => falharam == 0 && aindaPendentes == 0;
}

/// Esvazia o [Outbox] quando há conexão.
///
/// O app é usado em trilha: o Hakuna registra atendimento e posição sem
/// sinal e guarda o celular. Quando passa por uma área com cobertura ou
/// chega no wifi do alojamento, isto roda sozinho e sobe tudo, na ordem em
/// que aconteceu.
class SyncService {
  SyncService._();

  static final SyncService instance = SyncService._();

  final Map<String, OutboxUploader> _uploaders = {};
  final _statusController = StreamController<SyncStatus>.broadcast();

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _sincronizando = false;
  SyncStatus _status = SyncStatus.parado;

  SyncStatus get status => _status;
  Stream<SyncStatus> get statusStream => _statusController.stream;

  void _setStatus(SyncStatus s) {
    _status = s;
    if (!_statusController.isClosed) _statusController.add(s);
  }

  /// Registra como enviar uma entidade. Sem uploader registrado, as
  /// entradas daquela entidade ficam na fila em vez de serem descartadas.
  void registerUploader(String entity, OutboxUploader uploader) {
    _uploaders[entity] = uploader;
  }

  /// Passa a observar a conectividade e sincroniza quando o sinal voltar.
  ///
  /// Não dispara nada só por existir rede: a tentativa real de envio é que
  /// diz se há internet de verdade. Wifi de alojamento que não navega é
  /// comum, e `connectivity_plus` enxerga isso como conectado.
  Future<void> start() async {
    if (_connectivitySub != null) return;
    _setStatus(SyncStatus.aguardandoSinal);
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final temRede = results.any((r) => r != ConnectivityResult.none);
      if (temRede) unawaited(syncNow());
    });
    unawaited(syncNow());
  }

  Future<void> stop() async {
    await _connectivitySub?.cancel();
    _connectivitySub = null;
    _setStatus(SyncStatus.parado);
  }

  /// Tenta esvaziar a fila agora.
  ///
  /// Seguro de chamar a qualquer momento: se já houver uma sincronização em
  /// andamento, esta chamada não faz nada em vez de enviar tudo duas vezes.
  Future<SyncReport> syncNow({int lote = 200}) async {
    if (_sincronizando) {
      return SyncReport(
        enviados: 0,
        falharam: 0,
        aindaPendentes: await Outbox.instance.pendingCount(),
      );
    }
    _sincronizando = true;
    _setStatus(SyncStatus.sincronizando);

    var enviados = 0;
    var falharam = 0;
    Object? ultimoErro;

    try {
      final pendentes = await Outbox.instance.pending(limit: lote);
      for (final entrada in pendentes) {
        final uploader = _uploaders[entrada.entity];
        if (uploader == null) {
          // Entidade sem uploader registrado: deixa na fila. Melhor ficar
          // pendente do que sumir.
          continue;
        }
        try {
          await uploader(entrada);
          await Outbox.instance.markSynced(entrada.id);
          enviados++;
        } catch (e) {
          await Outbox.instance.markFailed(entrada.id, e);
          falharam++;
          ultimoErro = e;
          // Para no primeiro erro de propósito: quase sempre é queda de
          // rede, e insistir nas outras 199 só queima bateria e enche o
          // log de erro igual.
          break;
        }
      }

      final restantes = await Outbox.instance.pendingCount();
      _setStatus(
        falharam > 0
            ? SyncStatus.comErro
            : restantes == 0
            ? SyncStatus.emDia
            : SyncStatus.aguardandoSinal,
      );
      return SyncReport(
        enviados: enviados,
        falharam: falharam,
        aindaPendentes: restantes,
        ultimoErro: ultimoErro,
      );
    } finally {
      _sincronizando = false;
    }
  }

  @visibleForTesting
  void resetForTests() {
    _uploaders.clear();
    _sincronizando = false;
    _status = SyncStatus.parado;
  }
}
