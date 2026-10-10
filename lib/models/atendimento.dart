/// Um atendimento registrado por um Hakuna.
///
/// **Append-only.** Toda abertura gera um registro novo com número
/// próprio; nada é editado nem sobrescrito. Dois Hakunas atendendo a mesma
/// pessoa viram dois registros — decisão do usuário, e é ela que elimina
/// conflito de sincronização entre aparelhos offline.
///
/// Tabela `atendimentos`.
class Atendimento {
  /// Gerado no aparelho antes de existir no servidor. Permite registrar o
  /// atendimento sem rede e evita duplicata quando o envio é repetido.
  final String clientId;

  /// Null até o registro chegar ao servidor.
  final String? id;

  final String topId;
  final String participantId;

  /// Hakuna que atendeu. O registro é dele.
  final String openedBy;

  /// Número visível no histórico (#1, #7, #8). Sequencial por Top.
  final int? numeroRegistro;

  /// O relato do atendimento. Obrigatório — é o conteúdo clínico.
  final String procedimento;

  // --- sinais vitais aferidos no momento ---
  final int? systolicBp;
  final int? diastolicBp;
  final int? glicemiaMgDl;
  final int? spo2;
  final int? heartRate;
  final double? temperatureC;
  final String? feridas;

  // --- onde aconteceu ---
  final double? latitude;
  final double? longitude;

  final DateTime openedAt;

  /// Caminhos das fotos na pasta do próprio celular, enquanto não subiram.
  final List<String> fotosLocais;

  Atendimento({
    required this.clientId,
    required this.topId,
    required this.participantId,
    required this.openedBy,
    required this.procedimento,
    required this.openedAt,
    this.id,
    this.numeroRegistro,
    this.systolicBp,
    this.diastolicBp,
    this.glicemiaMgDl,
    this.spo2,
    this.heartRate,
    this.temperatureC,
    this.feridas,
    this.latitude,
    this.longitude,
    this.fotosLocais = const [],
  });

  factory Atendimento.fromMap(Map<String, dynamic> map) {
    return Atendimento(
      clientId: map['client_id'] as String? ?? map['id'] as String,
      id: map['id'] as String?,
      topId: map['top_id'] as String,
      participantId: map['participant_id'] as String,
      openedBy: map['opened_by'] as String,
      numeroRegistro: map['numero_registro'] as int?,
      procedimento: map['notes'] as String? ?? '',
      systolicBp: map['systolic_bp'] as int?,
      diastolicBp: map['diastolic_bp'] as int?,
      glicemiaMgDl: map['glicemia_mg_dl'] as int?,
      spo2: map['spo2'] as int?,
      heartRate: map['heart_rate'] as int?,
      temperatureC: (map['temperature_c'] as num?)?.toDouble(),
      feridas: map['feridas'] as String?,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      openedAt: DateTime.parse(map['opened_at'] as String),
    );
  }

  /// O que vai para o Supabase. `fotosLocais` fica de fora: foto tem tabela
  /// própria e sobe separado, porque o arquivo pode demorar a sair do
  /// celular bem depois do texto.
  Map<String, dynamic> toMap() => {
    'client_id': clientId,
    'top_id': topId,
    'participant_id': participantId,
    'opened_by': openedBy,
    'notes': procedimento,
    'numero_registro': numeroRegistro,
    'systolic_bp': systolicBp,
    'diastolic_bp': diastolicBp,
    'glicemia_mg_dl': glicemiaMgDl,
    'spo2': spo2,
    'heart_rate': heartRate,
    'temperature_c': temperatureC,
    'feridas': feridas,
    'latitude': latitude,
    'longitude': longitude,
    'opened_at': openedAt.toUtc().toIso8601String(),
  };

  /// "140x90", como o Hakuna escreve. Null quando falta uma das duas.
  String? get pressaoArterial {
    if (systolicBp == null || diastolicBp == null) return null;
    return '$systolicBp x $diastolicBp';
  }

  /// Algum sinal vital foi aferido? Serve para a tela decidir se mostra o
  /// bloco de vitais no histórico.
  bool get temSinaisVitais =>
      systolicBp != null ||
      diastolicBp != null ||
      glicemiaMgDl != null ||
      spo2 != null ||
      heartRate != null ||
      temperatureC != null;

  bool get temLocalizacao => latitude != null && longitude != null;

  /// Resumo dos vitais numa linha só, para o cabeçalho do histórico.
  String? get resumoVitais {
    final partes = <String>[
      if (pressaoArterial != null) 'PA $pressaoArterial',
      if (glicemiaMgDl != null) 'DX $glicemiaMgDl',
      if (spo2 != null) 'SpO₂ $spo2%',
      if (heartRate != null) 'FC $heartRate',
      if (temperatureC != null) 'T ${temperatureC!.toStringAsFixed(1)}°C',
    ];
    return partes.isEmpty ? null : partes.join(' · ');
  }
}

/// Faixas de alerta dos sinais vitais.
///
/// **Não substitui avaliação clínica** — serve só para destacar na tela um
/// número que merece um segundo olhar. Os cortes são os usados em triagem
/// de adulto; criança tem outros, e por isso nada aqui bloqueia nem decide
/// conduta.
abstract final class AlertaVital {
  static bool pressaoAlterada(int? sistolica, int? diastolica) {
    if (sistolica == null || diastolica == null) return false;
    return sistolica >= 140 ||
        sistolica < 90 ||
        diastolica >= 90 ||
        diastolica < 60;
  }

  static bool glicemiaAlterada(int? mgDl) {
    if (mgDl == null) return false;
    return mgDl < 70 || mgDl > 180;
  }

  static bool spo2Alterado(int? spo2) {
    if (spo2 == null) return false;
    return spo2 < 94;
  }

  static bool frequenciaAlterada(int? bpm) {
    if (bpm == null) return false;
    return bpm < 50 || bpm > 120;
  }

  static bool temperaturaAlterada(double? celsius) {
    if (celsius == null) return false;
    return celsius < 35.0 || celsius >= 37.8;
  }
}
