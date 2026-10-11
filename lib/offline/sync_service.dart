import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

import 'falha_de_envio.dart';
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

  /// Quantas foram recusadas em definitivo nesta rodada e saíram da fila.
  /// Não são perda silenciosa: ficam no banco, visíveis, para quem resolver.
  final int quarentenados;

  final Object? ultimoErro;

  const SyncReport({
    required this.enviados,
    required this.falharam,
    required this.aindaPendentes,
    this.quarentenados = 0,
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

  /// Quantas falhas seguidas antes de mandar a entrada para a quarentena.
  ///
  /// Rede de segurança para erro mal classificado: `_envioDaFila` erra para
  /// o lado de "transitório" de propósito, e sem este teto um erro
  /// definitivo que não foi reconhecido travaria a fila para sempre.
  ///
  /// 10 é folgado — com sincronização disparada a cada volta de sinal, dez
  /// falhas seguidas na mesma entrada não são oscilação de cobertura.
  static const maxTentativas = 10;

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
  Future<SyncReport> syncNow({int lote = 200}) {
    // Guarda a rodada em andamento para quem precisa esperar por ela.
    //
    // Em produção ninguém espera: os serviços chamam `unawaited(syncNow())`
    // porque a tela não pode travar aguardando rede. Em teste isso vira
    // uma rodada que continua viva depois do `tearDown` e esbarra no banco
    // já fechado — `DatabaseException(database_closed)`, que parece erro de
    // produção e não é. Com esta referência o teste aguarda
    // `SyncService.instance.rodadaEmAndamento` antes de fechar o banco.
    final rodada = _syncNow(lote: lote);
    rodadaEmAndamento = rodada;
    return rodada;
  }

  /// A última rodada disparada, inclusive as `unawaited`. Só para teste.
  @visibleForTesting
  Future<SyncReport>? rodadaEmAndamento;

  Future<SyncReport> _syncNow({int lote = 200}) async {
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
    var quarentenados = 0;
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
        } on FalhaPermanente catch (e) {
          // Recusa definitiva: insistir não resolve. Sai da fila e a
          // sincronização SEGUE para a próxima entrada.
          //
          // Sem isto, uma mensagem recusada pela RLS (Top em draft, por
          // exemplo) travava atendimento, GPS, foto e auditoria atrás dela
          // para sempre — porque o `break` abaixo parava tudo e a próxima
          // rodada relia a fila na mesma ordem.
          await Outbox.instance.quarantine(entrada.id, e.motivo);
          quarentenados++;
          ultimoErro = e;
          continue;
        } catch (e) {
          await Outbox.instance.markFailed(entrada.id, e);
          ultimoErro = e;

          // Teto de tentativas: rede de segurança para erro que foi
          // classificado como transitório e não é. `_envioDaFila` erra
          // para o lado de "transitório" de propósito (descartar dado
          // clínico é pior que atrasar), e é aqui que esse erro para de
          // custar a fila inteira.
          //
          // `attempts` é o valor ANTES desta tentativa, daí o `+ 1`.
          if (entrada.attempts + 1 >= maxTentativas) {
            await Outbox.instance.quarantine(
              entrada.id,
              'falhou ${entrada.attempts + 1} vezes seguidas; '
              'último erro: $e',
            );
            quarentenados++;
            continue;
          }

          falharam++;
          // Para no primeiro erro TRANSITÓRIO de propósito: quase sempre é
          // queda de rede, e insistir nas outras 199 só queima bateria e
          // enche o log de erro igual.
          break;
        }
      }

      final restantes = await Outbox.instance.pendingCount();

      // Limpa o que já subiu há mais de 30 dias. Rodava em teste nenhum e
      // em produção nunca: a fila crescia sem fim, e numa trilha de 4 h o
      // GPS sozinho gera centenas de linhas.
      //
      // Só depois de a fila esvaziar, e sem derrubar o sync se falhar:
      // manutenção não pode custar um envio.
      if (restantes == 0) {
        try {
          await Outbox.instance.purgeSynced();
        } catch (_) {}
      }

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
        quarentenados: quarentenados,
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
