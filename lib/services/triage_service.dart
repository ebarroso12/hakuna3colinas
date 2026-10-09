import '../models/profile.dart';
import '../models/triage_rule.dart';

/// Calcula a cor de triagem de um participante a partir das regras
/// configuráveis pelo admin master (idade + nº de comorbidades). As regras
/// em si vêm do banco (SupabaseService.fetchActiveTriageRules) — nada aqui
/// está fixo no código.
class TriageService {
  TriageService._();

  /// Retorna a cor da regra de menor [TriageRule.priority] que casa com o
  /// paciente, ou null se faltar idade ou nenhuma regra bater.
  ///
  /// A ordenação é feita aqui dentro de propósito: antes isso dependia de
  /// quem chamava ter buscado as regras com `.order('priority')`. Uma
  /// consulta nova sem esse `order` mudaria a classificação clínica sem
  /// erro nenhum aparecer. Cor de triagem não pode depender da ordem em
  /// que a lista chegou.
  static TriageColor? colorFor(Profile profile, List<TriageRule> rules) {
    final age = profile.age;
    if (age == null) return null;
    final comorbidityCount = profile.comorbidities.length;
    final porPrioridade = [...rules]
      ..sort((a, b) => a.priority.compareTo(b.priority));
    for (final rule in porPrioridade) {
      if (rule.matches(age: age, comorbidityCount: comorbidityCount)) {
        return rule.color;
      }
    }
    return null;
  }
}
