import '../models/profile.dart';
import '../models/triage_rule.dart';

/// Calcula a cor de triagem de um participante a partir das regras
/// configuráveis pelo admin master (idade + nº de comorbidades). As regras
/// em si vêm do banco (SupabaseService.fetchActiveTriageRules) — nada aqui
/// está fixo no código.
class TriageService {
  TriageService._();

  /// Retorna a cor da primeira regra (por priority) que casa com o
  /// paciente, ou null se faltar idade ou nenhuma regra bater.
  static TriageColor? colorFor(Profile profile, List<TriageRule> rules) {
    final age = profile.age;
    if (age == null) return null;
    final comorbidityCount = profile.comorbidities.length;
    for (final rule in rules) {
      if (rule.matches(age: age, comorbidityCount: comorbidityCount)) return rule.color;
    }
    return null;
  }
}
