enum ClinicalPriority { critica, alta, moderada, baixa }

ClinicalPriority _priorityFromString(String value) {
  return ClinicalPriority.values.firstWhere(
    (p) => p.name.toUpperCase() == value.toUpperCase(),
    orElse: () => ClinicalPriority.moderada,
  );
}

extension ClinicalPriorityLabel on ClinicalPriority {
  String get label => switch (this) {
    ClinicalPriority.critica => 'CRÍTICA',
    ClinicalPriority.alta => 'ALTA',
    ClinicalPriority.moderada => 'MODERADA',
    ClinicalPriority.baixa => 'BAIXA',
  };
}

class DifferentialHypothesis {
  final String hypothesis;
  final String forIt;
  final String against;

  DifferentialHypothesis({
    required this.hypothesis,
    required this.forIt,
    required this.against,
  });

  factory DifferentialHypothesis.fromJson(Map<String, dynamic> json) {
    return DifferentialHypothesis(
      hypothesis: json['hypothesis'] as String? ?? '',
      forIt: json['forIt'] as String? ?? '',
      against: json['against'] as String? ?? '',
    );
  }
}

class ClinicalEvidenceRef {
  final String source;
  final String institution;
  final int? year;
  final String reference;

  ClinicalEvidenceRef({
    required this.source,
    required this.institution,
    this.year,
    required this.reference,
  });

  factory ClinicalEvidenceRef.fromJson(Map<String, dynamic> json) {
    return ClinicalEvidenceRef(
      source: json['source'] as String? ?? '',
      institution: json['institution'] as String? ?? '',
      year: json['year'] as int?,
      reference: json['reference'] as String? ?? '',
    );
  }
}

/// Resposta estruturada da Hakuna Medical AI — schema validado no backend
/// (Edge Function), nunca texto livre pra decisão crítica. [isMock] é true
/// enquanto a integração real com a OpenAI não estiver conectada (ver
/// supabase/functions/clinical-ai/index.ts) — a UI precisa deixar isso
/// visível, nunca esconder que é uma simulação.
class ClinicalAiResponse {
  final ClinicalPriority priority;
  final List<String> immediateRisks;
  final List<String> cannotMiss;
  final List<DifferentialHypothesis> differentialDiagnosis;
  final List<String> actionsNow;
  final List<String> additionalAssessment;
  final List<String> therapeuticOptions;
  final List<String> medicationConsiderations;
  final String? evacuationRecommendation;
  final List<String> missingInformation;
  final List<ClinicalEvidenceRef> evidence;
  final String uncertainty;
  final bool isMock;

  ClinicalAiResponse({
    required this.priority,
    this.immediateRisks = const [],
    this.cannotMiss = const [],
    this.differentialDiagnosis = const [],
    this.actionsNow = const [],
    this.additionalAssessment = const [],
    this.therapeuticOptions = const [],
    this.medicationConsiderations = const [],
    this.evacuationRecommendation,
    this.missingInformation = const [],
    this.evidence = const [],
    required this.uncertainty,
    required this.isMock,
  });

  factory ClinicalAiResponse.fromJson(Map<String, dynamic> json) {
    return ClinicalAiResponse(
      priority: _priorityFromString(json['priority'] as String? ?? 'MODERADA'),
      immediateRisks: (json['immediateRisks'] as List<dynamic>? ?? [])
          .cast<String>(),
      cannotMiss: (json['cannotMiss'] as List<dynamic>? ?? []).cast<String>(),
      differentialDiagnosis:
          (json['differentialDiagnosis'] as List<dynamic>? ?? [])
              .map(
                (e) =>
                    DifferentialHypothesis.fromJson(e as Map<String, dynamic>),
              )
              .toList(),
      actionsNow: (json['actionsNow'] as List<dynamic>? ?? []).cast<String>(),
      additionalAssessment:
          (json['additionalAssessment'] as List<dynamic>? ?? []).cast<String>(),
      therapeuticOptions: (json['therapeuticOptions'] as List<dynamic>? ?? [])
          .cast<String>(),
      medicationConsiderations:
          (json['medicationConsiderations'] as List<dynamic>? ?? [])
              .cast<String>(),
      evacuationRecommendation: json['evacuationRecommendation'] as String?,
      missingInformation: (json['missingInformation'] as List<dynamic>? ?? [])
          .cast<String>(),
      evidence: (json['evidence'] as List<dynamic>? ?? [])
          .map((e) => ClinicalEvidenceRef.fromJson(e as Map<String, dynamic>))
          .toList(),
      uncertainty: json['uncertainty'] as String? ?? '',
      isMock: json['isMock'] as bool? ?? true,
    );
  }
}
