class VitalSigns {
  final int id;
  final String topId;
  final String profileId;
  final String recordedBy;
  final int? heartRate;
  final int? systolicBp;
  final int? diastolicBp;
  final int? spo2;
  final double? temperatureC;
  final int? respiratoryRate;
  final String? notes;
  final DateTime recordedAt;

  VitalSigns({
    required this.id,
    required this.topId,
    required this.profileId,
    required this.recordedBy,
    this.heartRate,
    this.systolicBp,
    this.diastolicBp,
    this.spo2,
    this.temperatureC,
    this.respiratoryRate,
    this.notes,
    required this.recordedAt,
  });

  factory VitalSigns.fromMap(Map<String, dynamic> map) {
    return VitalSigns(
      id: map['id'] as int,
      topId: map['top_id'] as String,
      profileId: map['profile_id'] as String,
      recordedBy: map['recorded_by'] as String,
      heartRate: map['heart_rate'] as int?,
      systolicBp: map['systolic_bp'] as int?,
      diastolicBp: map['diastolic_bp'] as int?,
      spo2: map['spo2'] as int?,
      temperatureC: (map['temperature_c'] as num?)?.toDouble(),
      respiratoryRate: map['respiratory_rate'] as int?,
      notes: map['notes'] as String?,
      recordedAt: DateTime.parse(map['recorded_at'] as String),
    );
  }

  /// Resumo compacto pra exibir numa lista (ex: "PA 120/80 · FC 78 · SpO2 97%").
  String get summary {
    final parts = <String>[];
    if (systolicBp != null && diastolicBp != null) parts.add('PA $systolicBp/$diastolicBp');
    if (heartRate != null) parts.add('FC $heartRate');
    if (spo2 != null) parts.add('SpO2 $spo2%');
    if (temperatureC != null) parts.add('Temp ${temperatureC!.toStringAsFixed(1)}°C');
    if (respiratoryRate != null) parts.add('FR $respiratoryRate');
    return parts.isEmpty ? 'Sem valores registrados' : parts.join(' · ');
  }
}
