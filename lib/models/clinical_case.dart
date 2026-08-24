enum ClinicalAiMode { rapida, discussao }

/// Caso clínico estruturado enviado à Hakuna Medical AI — desidentificado
/// por design: idade (não data de nascimento), sem nome/CPF/telefone. Ver
/// supabase/functions/clinical-ai/index.ts.
class ClinicalCase {
  final String topId;
  final String? attendanceId;
  final int? ageYears;
  final String? sex;
  final String chiefComplaint;
  final String? mechanismOfInjury;
  final int? onsetMinutesAgo;
  final int? systolicBp;
  final int? diastolicBp;
  final int? heartRate;
  final int? respiratoryRate;
  final int? spo2;
  final double? temperatureC;
  final int? glasgow;
  final double? glycemia;
  final String? notes;
  final ClinicalAiMode mode;

  ClinicalCase({
    required this.topId,
    this.attendanceId,
    this.ageYears,
    this.sex,
    required this.chiefComplaint,
    this.mechanismOfInjury,
    this.onsetMinutesAgo,
    this.systolicBp,
    this.diastolicBp,
    this.heartRate,
    this.respiratoryRate,
    this.spo2,
    this.temperatureC,
    this.glasgow,
    this.glycemia,
    this.notes,
    required this.mode,
  });

  Map<String, dynamic> toJson() => {
    'topId': topId,
    if (attendanceId != null) 'attendanceId': attendanceId,
    if (ageYears != null) 'ageYears': ageYears,
    if (sex != null) 'sex': sex,
    'chiefComplaint': chiefComplaint,
    if (mechanismOfInjury != null) 'mechanismOfInjury': mechanismOfInjury,
    if (onsetMinutesAgo != null) 'onsetMinutesAgo': onsetMinutesAgo,
    'vitals': {
      if (systolicBp != null) 'systolicBp': systolicBp,
      if (diastolicBp != null) 'diastolicBp': diastolicBp,
      if (heartRate != null) 'heartRate': heartRate,
      if (respiratoryRate != null) 'respiratoryRate': respiratoryRate,
      if (spo2 != null) 'spo2': spo2,
      if (temperatureC != null) 'temperatureC': temperatureC,
      if (glasgow != null) 'glasgow': glasgow,
      if (glycemia != null) 'glycemia': glycemia,
    },
    if (notes != null) 'notes': notes,
    'mode': mode.name,
  };
}
