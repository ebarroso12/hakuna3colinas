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

/// Cópia fiel das 8 regras ativas em produção (tabela `triage_rules` do
/// projeto Supabase hakuna3colinas, ids 7-14, aplicadas em 09/10/2026).
///
/// As faixas etárias são explícitas e não se sobrepõem: 0-25, 26-40, 41+.
/// A configuração anterior (ids 1-6, hoje `active = false`) tinha uma regra
/// "41+, qualquer comorbidade -> vermelho" com priority 1, que atropelava
/// todas as outras: acima de 40 o número de comorbidades deixava de
/// importar, e alguém saudável pulava de verde aos 40 para vermelho aos 41.
///
/// Se as regras do banco mudarem, esta lista precisa mudar junto.
final _producao = <TriageRule>[
  _rule(
    id: 7,
    color: TriageColor.blue,
    minAge: 0,
    maxAge: 25,
    minComorbidities: 0,
    maxComorbidities: 0,
    priority: 1,
  ),
  _rule(
    id: 8,
    color: TriageColor.green,
    minAge: 0,
    maxAge: 25,
    minComorbidities: 1,
    maxComorbidities: 1,
    priority: 2,
  ),
  _rule(
    id: 9,
    color: TriageColor.red,
    minAge: 0,
    maxAge: 25,
    minComorbidities: 2,
    maxComorbidities: 999,
    priority: 3,
  ),
  _rule(
    id: 10,
    color: TriageColor.green,
    minAge: 26,
    maxAge: 40,
    minComorbidities: 0,
    maxComorbidities: 0,
    priority: 4,
  ),
  _rule(
    id: 11,
    color: TriageColor.yellow,
    minAge: 26,
    maxAge: 40,
    minComorbidities: 1,
    maxComorbidities: 1,
    priority: 5,
  ),
  _rule(
    id: 12,
    color: TriageColor.red,
    minAge: 26,
    maxAge: 40,
    minComorbidities: 2,
    maxComorbidities: 999,
    priority: 6,
  ),
  _rule(
    id: 13,
    color: TriageColor.yellow,
    minAge: 41,
    minComorbidities: 0,
    maxComorbidities: 0,
    priority: 7,
  ),
  _rule(
    id: 14,
    color: TriageColor.red,
    minAge: 41,
    minComorbidities: 1,
    maxComorbidities: 999,
    priority: 8,
  ),
];

TriageColor? _cor(int idade, int comorbidades) => TriageService.colorFor(
  _profile(age: idade, comorbidities: comorbidades),
  _producao,
);

void main() {
  group('faixa até 25 anos', () {
    test('sem comorbidade é azul', () => expect(_cor(18, 0), TriageColor.blue));
    test('1 comorbidade é verde', () => expect(_cor(18, 1), TriageColor.green));
    test(
      '2+ comorbidades é vermelho',
      () => expect(_cor(18, 3), TriageColor.red),
    );
    test('25 anos ainda é a faixa jovem', () {
      expect(_cor(25, 0), TriageColor.blue);
      expect(_cor(25, 1), TriageColor.green);
      expect(_cor(25, 2), TriageColor.red);
    });
  });

  group('faixa 26 a 40 anos', () {
    test(
      'sem comorbidade é verde',
      () => expect(_cor(30, 0), TriageColor.green),
    );
    test(
      '1 comorbidade é amarelo',
      () => expect(_cor(30, 1), TriageColor.yellow),
    );
    test(
      '2+ comorbidades é vermelho',
      () => expect(_cor(30, 2), TriageColor.red),
    );
    test('26 e 40 anos são as pontas da faixa', () {
      expect(_cor(26, 0), TriageColor.green);
      expect(_cor(40, 0), TriageColor.green);
      expect(_cor(40, 1), TriageColor.yellow);
    });
  });

  group('faixa acima de 40 anos', () {
    test(
      'sem comorbidade é amarelo, não vermelho',
      () => expect(_cor(41, 0), TriageColor.yellow),
    );
    test(
      '1 comorbidade já é vermelho',
      () => expect(_cor(41, 1), TriageColor.red),
    );
    test(
      '2+ comorbidades é vermelho',
      () => expect(_cor(41, 4), TriageColor.red),
    );

    test('as comorbidades voltaram a diferenciar acima de 40', () {
      expect(
        _cor(65, 0),
        isNot(_cor(65, 2)),
        reason:
            'na configuração antiga os dois casos eram vermelho e a triagem '
            'perdia a capacidade de priorizar na faixa com mais participantes',
      );
    });

    test(
      'idade não satura: 41 e 80 anos com o mesmo quadro dão a mesma cor',
      () {
        expect(_cor(41, 0), _cor(80, 0));
        expect(_cor(41, 2), _cor(80, 2));
      },
    );
  });

  group('transições entre faixas', () {
    test('40 -> 41 sobe exatamente um nível, não pula o amarelo', () {
      expect(_cor(40, 0), TriageColor.green);
      expect(_cor(41, 0), TriageColor.yellow);
    });

    test('25 -> 26 sobe exatamente um nível', () {
      expect(_cor(25, 0), TriageColor.blue);
      expect(_cor(26, 0), TriageColor.green);
      expect(_cor(25, 1), TriageColor.green);
      expect(_cor(26, 1), TriageColor.yellow);
    });

    test('a gravidade nunca diminui quando a idade aumenta', () {
      const ordem = {
        TriageColor.blue: 0,
        TriageColor.green: 1,
        TriageColor.yellow: 2,
        TriageColor.red: 3,
      };
      for (var comorbidades = 0; comorbidades <= 5; comorbidades++) {
        var anterior = -1;
        for (var idade = 0; idade <= 100; idade++) {
          final nivel = ordem[_cor(idade, comorbidades)]!;
          expect(
            nivel,
            greaterThanOrEqualTo(anterior),
            reason:
                'aos $idade anos com $comorbidades comorbidade(s) a cor ficou '
                'MENOS grave do que na idade anterior',
          );
          anterior = nivel;
        }
      }
    });

    test('a gravidade nunca diminui quando as comorbidades aumentam', () {
      const ordem = {
        TriageColor.blue: 0,
        TriageColor.green: 1,
        TriageColor.yellow: 2,
        TriageColor.red: 3,
      };
      for (final idade in [10, 25, 26, 40, 41, 70]) {
        var anterior = -1;
        for (var comorbidades = 0; comorbidades <= 8; comorbidades++) {
          final nivel = ordem[_cor(idade, comorbidades)]!;
          expect(nivel, greaterThanOrEqualTo(anterior), reason: '$idade anos');
          anterior = nivel;
        }
      }
    });
  });

  group('cobertura das regras', () {
    test(
      'nenhum buraco: 0 a 110 anos x 0 a 8 comorbidades sempre classifica',
      () {
        final semCor = <String>[];
        for (var idade = 0; idade <= 110; idade++) {
          for (var comorbidades = 0; comorbidades <= 8; comorbidades++) {
            if (_cor(idade, comorbidades) == null) {
              semCor.add('$idade anos / $comorbidades comorbidade(s)');
            }
          }
        }
        expect(semCor, isEmpty);
      },
    );

    test('nenhuma sobreposição: cada caso casa com exatamente uma regra', () {
      final sobrepostos = <String>[];
      for (var idade = 0; idade <= 110; idade++) {
        for (var comorbidades = 0; comorbidades <= 8; comorbidades++) {
          final casam = _producao
              .where(
                (r) => r.matches(age: idade, comorbidityCount: comorbidades),
              )
              .length;
          if (casam != 1) {
            sobrepostos.add(
              '$idade anos / $comorbidades comorbidade(s): $casam regras',
            );
          }
        }
      }
      expect(
        sobrepostos,
        isEmpty,
        reason:
            'faixas sobrepostas fazem o resultado depender da priority em vez '
            'de ser explícito — foi o que causou o penhasco dos 40',
      );
    });
  });

  group('ausência de classificação', () {
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

  group('colorFor ordena por priority internamente', () {
    test('regra de priority alta no topo da lista não vence as de baixa', () {
      final foraDeOrdem = <TriageRule>[
        _rule(
          id: 99,
          color: TriageColor.red,
          minAge: 0,
          maxAge: 120,
          minComorbidities: 0,
          maxComorbidities: 999,
          priority: 50,
        ),
        ..._producao,
      ];
      expect(
        TriageService.colorFor(_profile(age: 18), foraDeOrdem),
        TriageColor.blue,
        reason: 'a regra de priority 1 tem que vencer a de priority 50',
      );
    });

    test('lista invertida dá o mesmo resultado da ordem correta', () {
      final invertida = _producao.reversed.toList();
      for (final caso in [
        (idade: 18, comorbidades: 0),
        (idade: 30, comorbidades: 1),
        (idade: 41, comorbidades: 0),
        (idade: 65, comorbidades: 3),
      ]) {
        expect(
          TriageService.colorFor(
            _profile(age: caso.idade, comorbidities: caso.comorbidades),
            invertida,
          ),
          _cor(caso.idade, caso.comorbidades),
          reason: '${caso.idade} anos, ${caso.comorbidades} comorbidade(s)',
        );
      }
    });

    test('não modifica a lista recebida (ordena numa cópia)', () {
      final entrada = _producao.reversed.toList();
      final antes = entrada.map((r) => r.id).toList();
      TriageService.colorFor(_profile(age: 30), entrada);
      expect(entrada.map((r) => r.id).toList(), antes);
    });
  });
}
