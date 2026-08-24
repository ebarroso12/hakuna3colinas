import 'package:flutter_test/flutter_test.dart';
import 'package:hakuna_connect/models/profile.dart';
import 'package:hakuna_connect/models/triage_rule.dart';
import 'package:hakuna_connect/services/triage_service.dart';

TriageRule _rule({
  required int id,
  required TriageColor color,
  required int minAge,
  int? maxAge,
  required int minComorbidities,
  required int maxComorbidities,
  required int priority,
}) {
  return TriageRule(
    id: id,
    color: color,
    label: color.label,
    minAge: minAge,
    maxAge: maxAge,
    minComorbidities: minComorbidities,
    maxComorbidities: maxComorbidities,
    priority: priority,
    active: true,
  );
}

Profile _profile({
  required DateTime birthDate,
  List<String> comorbidities = const [],
}) {
  return Profile(
    id: 'p1',
    fullName: 'Teste',
    legendariosNumber: '1',
    role: UserRole.senderista,
    birthDate: birthDate,
    comorbidities: comorbidities,
  );
}

void main() {
  group('TriageService.colorFor', () {
    final rules = [
      _rule(
        id: 1,
        color: TriageColor.red,
        minAge: 0,
        maxAge: 200,
        minComorbidities: 3,
        maxComorbidities: 99,
        priority: 1,
      ),
      _rule(
        id: 2,
        color: TriageColor.yellow,
        minAge: 60,
        maxAge: 200,
        minComorbidities: 0,
        maxComorbidities: 2,
        priority: 2,
      ),
      _rule(
        id: 3,
        color: TriageColor.green,
        minAge: 18,
        maxAge: 59,
        minComorbidities: 1,
        maxComorbidities: 2,
        priority: 3,
      ),
      _rule(
        id: 4,
        color: TriageColor.blue,
        minAge: 0,
        maxAge: 200,
        minComorbidities: 0,
        maxComorbidities: 0,
        priority: 4,
      ),
    ];

    test('sem data de nascimento retorna null (nao inventa idade)', () {
      final profile = Profile(
        id: 'p1',
        fullName: 'Teste',
        legendariosNumber: '1',
        role: UserRole.senderista,
      );
      expect(TriageService.colorFor(profile, rules), isNull);
    });

    test('muitas comorbidades vira vermelho independente da idade', () {
      final young = _profile(
        birthDate: DateTime.now().subtract(const Duration(days: 365 * 20)),
        comorbidities: ['diabetes', 'hipertensao', 'cardiopatia'],
      );
      expect(TriageService.colorFor(young, rules), TriageColor.red);
    });

    test('idoso com poucas comorbidades vira amarelo', () {
      final elderly = _profile(
        birthDate: DateTime.now().subtract(const Duration(days: 365 * 65)),
        comorbidities: ['hipertensao'],
      );
      expect(TriageService.colorFor(elderly, rules), TriageColor.yellow);
    });

    test('adulto sem nenhuma comorbidade vira azul', () {
      final healthyAdult = _profile(
        birthDate: DateTime.now().subtract(const Duration(days: 365 * 30)),
      );
      expect(TriageService.colorFor(healthyAdult, rules), TriageColor.blue);
    });

    test('prioridade mais baixa (numero menor) vence quando mais de uma regra bate', () {
      // 65 anos sem comorbidade bate tanto na regra 2 (amarelo, idoso,
      // prioridade 2) quanto na 4 (azul, zero comorbidade, prioridade 4) -
      // a de prioridade menor deve vencer, evitando ambiguidade de qual
      // regra "ganha" quando mais de uma se aplica à mesma pessoa.
      final profile = _profile(
        birthDate: DateTime.now().subtract(const Duration(days: 365 * 65)),
      );
      expect(TriageService.colorFor(profile, rules), TriageColor.yellow);
    });

    test('nenhuma regra bate retorna null', () {
      final profile = _profile(
        birthDate: DateTime.now().subtract(const Duration(days: 365 * 10)),
        comorbidities: ['a'],
      );
      expect(TriageService.colorFor(profile, rules), isNull);
    });
  });
}
