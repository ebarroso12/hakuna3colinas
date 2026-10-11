import 'dart:async';

import '../models/afericao.dart';
import '../offline/dados_do_top.dart';
import '../offline/outbox.dart';
import '../offline/sync_service.dart';
import 'supabase_service.dart';

/// Registro de sinais vitais, com os dois defeitos que tinha corrigidos.
///
/// **Ia direto para o Supabase.** `recordVitalSigns` era `insert` puro, sem
/// fila e sem `client_id`. Sem sinal a aferição era perdida e nem aparecia
/// na fila — o Hakuna media a pressão, salvava, via "registrado" e o dado
/// não existia em lugar nenhum. Agora entra no outbox como atendimento,
/// foto, posição, chat e auditoria.
///
/// **Não reclassificava a triagem.** `TriageDinamica` escala a cor para
/// vermelho a partir de `cache_ultima_afericao`, e essa tabela só era
/// alimentada por `AtendimentoService`. Resultado: SpO₂ 85 medido no
/// formulário de atendimento pintava a pessoa de vermelho, e o **mesmo**
/// 85 medido nesta tela não pintava nada. Duas portas para a mesma medida,
/// uma funcionando. Agora as duas alimentam o cache.
class SinaisVitaisService {
  SinaisVitaisService._();

  static final SinaisVitaisService instance = SinaisVitaisService._();

  static const entidade = 'vital_signs';

  void registrarUploader() {
    SyncService.instance.registerUploader(entidade, (entrada) async {
      await SupabaseService.instance.enviarSinaisVitais(entrada.payload);
    });
  }

  /// Enfileira a aferição e atualiza a cor na hora.
  ///
  /// Devolve o `client_id`. Não lança por falta de rede.
  Future<String> registrar({
    required String topId,
    required String profileId,
    int? heartRate,
    int? systolicBp,
    int? diastolicBp,
    int? spo2,
    double? temperatureC,
    int? respiratoryRate,
    String? notes,
  }) async {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) {
      throw StateError('Sessão expirada — não é possível registrar');
    }

    // Hora do aparelho: offline a medição é feita horas antes do upload, e
    // `now()` no Postgres gravaria a hora em que o sinal voltou.
    final medidoEm = DateTime.now().toUtc();
    final clientId = Outbox.novoClientId();

    await Outbox.instance.enqueue(
      entity: entidade,
      topId: topId,
      clientId: clientId,
      payload: {
        'client_id': clientId,
        'top_id': topId,
        'profile_id': profileId,
        'recorded_by': uid,
        'heart_rate': heartRate,
        'systolic_bp': systolicBp,
        'diastolic_bp': diastolicBp,
        'spo2': spo2,
        'temperature_c': temperatureC,
        'respiratory_rate': respiratoryRate,
        'notes': notes,
        'recorded_at': medidoEm.toIso8601String(),
      },
    );

    // Alimenta a triagem dinâmica no mesmo instante — não quando o dado
    // chega ao servidor. Fora do caminho crítico: se o cache falhar, a
    // aferição já está na fila e o dado clínico está salvo; só a cor fica
    // velha. Mesmo tratamento que `AtendimentoService.registrar` dá.
    try {
      await DadosDoTop.instance.registrarAfericao(
        profileId,
        topId,
        Afericao(
          medidoEm: medidoEm,
          systolicBp: systolicBp,
          diastolicBp: diastolicBp,
          spo2: spo2,
        ),
      );
    } catch (_) {}

    unawaited(SyncService.instance.syncNow());
    return clientId;
  }

  /// Aferições deste perfil ainda na fila, para a tela mostrar o que o
  /// Hakuna acabou de medir mesmo sem rede.
  ///
  /// Sem isto a tela ficava vazia offline: o histórico vinha só de um
  /// `.stream()` do Supabase, e o registro recém-salvo não aparecia em
  /// lugar nenhum — parecia que não tinha sido gravado.
  Future<List<Map<String, dynamic>>> pendentesDe({
    required String topId,
    required String profileId,
  }) async {
    final fila = await Outbox.instance.pending(entity: entidade, limit: 500);
    return fila
        .map((e) => e.payload)
        .where(
          (p) => p['top_id'] == topId && p['profile_id'] == profileId,
        )
        .toList();
  }
}
