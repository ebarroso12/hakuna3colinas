import 'package:flutter_test/flutter_test.dart';
import 'package:hakuna_connect/models/profile.dart';
import 'package:hakuna_connect/models/triage_rule.dart';
import 'package:hakuna_connect/services/triage_service.dart';

/// Perfil com idade exata [age]. Usa 1º de janeiro como data de nascimento
/// porque essa data existe em todo ano (evita o bug de 29/fev em ano não
/// bissexto) e garante que o aniversário já passou, qualquer que seja o dia
/// em que o teste rodar.
Profile _profile({required int age, int comorbidities = 0}) {
  final now = DateTime.now();
  return Profile(
    id: 'p1',
    fullName: 'Teste',
    legendariosNumber: '000',
    role: UserRole.senderista,
    birthDate: DateTime(now.year - age, 1, 1),
    comorbidities: List.generate(comorbidities, (i) => 'comorbidade$i'),
  );
}

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
    label: 'regra $id',
    minAge: minAge,
    maxAge: maxAge,
    minComorbidities: minComorbidities,
    maxComorbidities: maxComorbidities,
    priority: priority,
    active: true,
  );
}

/// Cópia fiel das 6 regras ativas em produção (tabela `triage_rules` do
/// projeto Supabase hakuna3colinas, conferidas em 09/10/2026), já na ordem
/// que `fetchActiveTriageRules()` devolve — `.order('priority')` ascendente.
///
/// Se as regras do banco mudarem, estes testes passam a testar uma
/// configuração que não existe mais: atualizar esta lista junto.
final _producao = <TriageRule>[
  _rule(
    id: 1,
    color: TriageColor.red,
    minAge: 41,
    minComorbidities: 0,
    maxComorbidities: 999,
    priority: 1,
  ),
  _rule(
    id: 2,
    color: TriageColor.blue,
    minAge: 0,
    maxAge: 25,
    minComorbidities: 0,
    maxComorbidities: 0,
    priority: 2,
  ),
  _rule(
    id: 3,
    color: TriageColor.green,
    minAge: 25,
    maxAge: 40,
    minComorbidities: 0,
    maxComorbidities: 0,
    priority: 3,
  ),
  _rule(
    id: 4,
    color: TriageColor.green,
    minAge: 0,
    maxAge: 25,
    minComorbidities: 1,
    maxComorbidities: 1,
    priority: 4,
  ),
  _rule(
    id: 5,
    color: TriageColor.yellow,
    minAge: 25,
    maxAge: 40,
    minComorbidities: 1,
    maxComorbidities: 1,
    priority: 5,
  ),
  _rule(
    id: 6,
    color: TriageColor.red,
    minAge: 0,
    maxAge: 40,
    minComorbidities: 2,
    maxComorbidities: 999,
    priority: 6,
  ),
];

void main() {
  group('TriageService.colorFor — classificação com as regras de produção', () {
    test('jovem sem comorbidade é azul', () {
      expect(
        TriageService.colorFor(_profile(age: 20), _producao),
        TriageColor.blue,
      );
    });

    test('jovem com 1 comorbidade é verde', () {
      expect(
        TriageService.colorFor(_profile(age: 20, comorbidities: 1), _producao),
        TriageColor.green,
      );
    });

    test('jovem com 2+ comorbidades é vermelho', () {
      expect(
        TriageService.colorFor(_profile(age: 20, comorbidities: 3), _producao),
        TriageColor.red,
      );
    });

    test('adulto 26-40 sem comorbidade é verde', () {
      expect(
        TriageService.colorFor(_profile(age: 30), _producao),
        TriageColor.green,
      );
    });

    test('adulto 26-40 com 1 comorbidade é amarelo', () {
      expect(
        TriageService.colorFor(_profile(age: 30, comorbidities: 1), _producao),
        TriageColor.yellow,
      );
    });

    test('adulto 26-40 com 2+ comorbidades é vermelho', () {
      expect(
        TriageService.colorFor(_profile(age: 30, comorbidities: 2), _producao),
        TriageColor.red,
      );
    });

    test('acima de 40 é vermelho mesmo sem nenhuma comorbidade', () {
      expect(
        TriageService.colorFor(_profile(age: 50), _producao),
        TriageColor.red,
      );
    });
  });

  group('TriageService.colorFor — bordas de idade', () {
    test('40 anos ainda cai na faixa adulta (verde sem comorbidade)', () {
      expect(
        TriageService.colorFor(_profile(age: 40), _producao),
        TriageColor.green,
      );
    });

    test('41 anos vira vermelho pela regra de prioridade 1', () {
      expect(
        TriageService.colorFor(_profile(age: 41), _producao),
        TriageColor.red,
      );
    });

    // ATENÇÃO: as regras 2 (0-25) e 3 (25-40) se sobrepõem exatamente em 25.
    // Quem decide é a prioridade, e a regra 2 vem antes. Estes dois testes
    // fixam o comportamento REAL de hoje — não necessariamente o desejado.
    // Ver a inconsistência que eles expõem no teste logo abaixo.
    test('25 anos sem comorbidade resolve como AZUL (regra 2 tem prioridade)', () {
      expect(
        TriageService.colorFor(_profile(age: 25), _producao),
        TriageColor.blue,
      );
    });

    test('25 anos com 1 comorbidade resolve como VERDE (regra 4 antes da 5)', () {
      expect(
        TriageService.colorFor(_profile(age: 25, comorbidities: 1), _producao),
        TriageColor.green,
      );
    });

    test(
      'INCONSISTÊNCIA DE BORDA: 25 anos com 1 comorbidade é verde, '
      '26 anos com a mesma comorbidade é amarelo — um ano de diferença '
      'muda a classificação em dois níveis',
      () {
        final aos25 = TriageService.colorFor(
          _profile(age: 25, comorbidities: 1),
          _producao,
        );
        final aos26 = TriageService.colorFor(
          _profile(age: 26, comorbidities: 1),
          _producao,
        );
        expect(aos25, TriageColor.green);
        expect(aos26, TriageColor.yellow);
        expect(aos25, isNot(aos26));
      },
    );
  });

  group('TriageService.colorFor — ausência de classificação', () {
    test('sem data de nascimento retorna null (UI mostra "Sem triagem")', () {
      final semData = Profile(
        id: 'p2',
        fullName: 'Sem data',
        legendariosNumber: '001',
        role: UserRole.senderista,
        comorbidities: const ['diabetes', 'hipertensao'],
      );
      expect(TriageService.colorFor(semData, _producao), isNull);
    });

    test('lista de regras vazia retorna null', () {
      expect(TriageService.colorFor(_profile(age: 30), const []), isNull);
    });
  });

  group('TriageService.colorFor — contrato implícito de ordenação', () {
    test(
      'FRAGILIDADE: com regras fora de ordem de priority, um jovem sem '
      'comorbidade deixa de ser azul — colorFor pega a primeira que casar, '
      'não a de menor priority',
      () {
        final profile = _profile(age: 20, comorbidities: 0);

        // Ordem correta (como o banco devolve): azul.
        expect(TriageService.colorFor(profile, _producao), TriageColor.blue);

        // Mesmas regras, ordem trocada: a regra 6 (0-40, 2+ comorbidades)
        // não casa, mas basta qualquer regra mais permissiva vir antes da 2
        // pra mudar o resultado. Simula alguém que buscou as regras sem
        // `.order('priority')`.
        final foraDeOrdem = <TriageRule>[
          _rule(
            id: 99,
            color: TriageColor.yellow,
            minAge: 0,
            maxAge: 120,
            minComorbidities: 0,
            maxComorbidities: 999,
            priority: 50,
          ),
          ..._producao,
        ];
        expect(
          TriageService.colorFor(profile, foraDeOrdem),
          TriageColor.yellow,
          reason:
              'uma regra de priority 50 venceu as de priority 1-6 só por estar '
              'primeiro na lista — colorFor deveria ordenar internamente',
        );
      },
    );
  });
}
