import '../models/participant.dart';
import '../models/profile.dart';
import '../models/triage_rule.dart';

/// Calcula a cor de triagem de um participante a partir das regras
/// configuráveis pelo admin master (idade + nº de comorbidades). As regras
/// em si vêm do banco (SupabaseService.fetchActiveTriageRules) — nada aqui
/// está fixo no código.
class TriageService {
  TriageService._();

  /// Mesma classificação, para um [Participant] (Senderista).
  ///
  /// Participante e perfil são coisas diferentes — só Legendário tem
  /// perfil/login —, mas a regra clínica é a mesma: idade + número de
  /// comorbidades. Daí a lógica ficar num lugar só, em [_corPara].
  static TriageColor? colorForParticipant(
    Participant participante,
    List<TriageRule> rules,
  ) {
    return _corPara(
      idade: participante.idade,
      comorbidades: participante.totalComorbidades,
      rules: rules,
    );
  }

  /// Retorna a cor da regra de menor [TriageRule.priority] que casa com o
  /// paciente, ou null se faltar idade ou nenhuma regra bater.
  ///
  /// A ordenação é feita aqui dentro de propósito: antes isso dependia de
  /// quem chamava ter buscado as regras com `.order('priority')`. Uma
  /// consulta nova sem esse `order` mudaria a classificação clínica sem
  /// erro nenhum aparecer. Cor de triagem não pode depender da ordem em
  /// que a lista chegou.
  static TriageColor? colorFor(Profile profile, List<TriageRule> rules) {
    return _corPara(
      idade: profile.age,
      comorbidades: profile.comorbidities.length,
      rules: rules,
    );
  }

  /// Núcleo da classificação, compartilhado por perfil e participante.
  ///
  /// Ordena por priority aqui dentro em vez de confiar em quem chamou ter
  /// feito `.order('priority')`: uma consulta nova sem esse order mudaria
  /// a cor de triagem sem erro nenhum aparecer.
  static TriageColor? _corPara({
    required int? idade,
    required int comorbidades,
    required List<TriageRule> rules,
  }) {
    if (idade == null) return null;
    final porPrioridade = [...rules]
      ..sort((a, b) => a.priority.compareTo(b.priority));
    for (final rule in porPrioridade) {
      if (rule.matches(age: idade, comorbidityCount: comorbidades)) {
        return rule.color;
      }
    }
    return null;
  }
}
