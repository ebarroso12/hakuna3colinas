import 'package:flutter_test/flutter_test.dart';
import 'package:legendario_connect/models/participant.dart';

Participant _p({
  String nome = 'Alan Lucas Lemos',
  String? apelido,
  String? familia,
  double? peso,
  double? altura,
  List<String> comorbidades = const [],
  String? cidade,
  String? estado,
  int? idade,
}) {
  DateTime? nascimento;
  if (idade != null) {
    final agora = DateTime.now();
    nascimento = DateTime(agora.year - idade, 1, 1);
  }
  return Participant(
    id: 'p1',
    topId: 't1',
    fullName: nome,
    nickname: apelido,
    familia: familia,
    weightKg: peso,
    heightCm: altura,
    comorbidades: comorbidades,
    cidade: cidade,
    estado: estado,
    birthDate: nascimento,
  );
}

void main() {
  group('IMC', () {
    test('calcula peso / altura²  — o caso da ficha do app oficial', () {
      // 82 kg, 169 cm -> 28,7 (o valor que aparece no print)
      final imc = _p(peso: 82, altura: 169).imc;
      expect(imc, isNotNull);
      expect(imc!, closeTo(28.7, 0.05));
    });

    test('null quando falta peso ou altura', () {
      expect(_p(peso: 82).imc, isNull);
      expect(_p(altura: 169).imc, isNull);
      expect(_p().imc, isNull);
    });

    test(
      'altura zero não vira infinito na tela',
      () => expect(_p(peso: 82, altura: 0).imc, isNull),
    );

    test('altura negativa também não calcula', () {
      expect(_p(peso: 82, altura: -10).imc, isNull);
    });
  });

  group('faixa de IMC (cortes da OMS)', () {
    FaixaImc? faixaPara(double imcAlvo) {
      // altura fixa de 1,70 m -> peso = imc * 2.89
      return _p(altura: 170, peso: imcAlvo * 2.89).faixaImc;
    }

    test('abaixo do peso', () => expect(faixaPara(17), FaixaImc.abaixo));
    test('normal', () => expect(faixaPara(22), FaixaImc.normal));
    test('sobrepeso', () => expect(faixaPara(27), FaixaImc.sobrepeso));
    test('obesidade I', () => expect(faixaPara(32), FaixaImc.obesidade1));
    test('obesidade II', () => expect(faixaPara(37), FaixaImc.obesidade2));
    test('obesidade III', () => expect(faixaPara(45), FaixaImc.obesidade3));

    test('as 6 faixas têm sigla própria, como a barra colorida da ficha', () {
      final siglas = FaixaImc.values.map((f) => f.sigla).toList();
      expect(siglas, ['Ab', 'Nm', 'Sp', 'Ob1', 'Ob2', 'Ob3']);
      expect(siglas.toSet().length, 6);
    });

    test('sem peso/altura não há faixa', () => expect(_p().faixaImc, isNull));
  });

  group('comorbidades contam para a triagem', () {
    test('lista vazia conta zero', () {
      expect(_p().totalComorbidades, 0);
    });

    test('conta só o que está na lista de comorbidades', () {
      expect(
        _p(comorbidades: ['diabetes', 'hipertensão']).totalComorbidades,
        2,
      );
    });

    test('plano de saúde e alergia NÃO entram na contagem — ficam em campos '
        'próprios de propósito, senão inflariam a cor da triagem', () {
      final participante = Participant(
        id: 'p1',
        topId: 't1',
        fullName: 'Teste',
        comorbidades: const ['diabetes'],
        planoSaude: 'UNIMED',
        alergias: 'PICADA ABELHAS MARIMBONDOS',
        medicamentosContinuos: 'losartana',
      );
      expect(
        participante.totalComorbidades,
        1,
        reason: 'só diabetes é comorbidade; plano, alergia e medicação não',
      );
    });
  });

  group('idade', () {
    test('calcula a partir da data de nascimento', () {
      expect(_p(idade: 43).idade, 43);
    });

    test('sem data de nascimento é null', () => expect(_p().idade, isNull));
  });

  group('localidade', () {
    test('junta cidade e estado como no cabeçalho da ficha', () {
      expect(
        _p(cidade: 'FRANCA', estado: 'SÃO PAULO').localidade,
        'FRANCA - SÃO PAULO',
      );
    });

    test('com só um dos dois, mostra o que tem, sem traço solto', () {
      expect(_p(cidade: 'FRANCA').localidade, 'FRANCA');
      expect(_p(estado: 'SÃO PAULO').localidade, 'SÃO PAULO');
    });

    test('sem nenhum dos dois é null', () => expect(_p().localidade, isNull));

    test('campos só com espaço contam como vazios', () {
      expect(_p(cidade: '  ', estado: '  ').localidade, isNull);
    });
  });

  group('busca na lista de participantes', () {
    final alan = _p(nome: 'Alan Lucas Lemos', familia: 'ÁGUIA');

    test('acha pelo primeiro nome', () {
      expect(alan.combinaCom('alan'), isTrue);
    });

    test('acha pelo sobrenome', () {
      expect(alan.combinaCom('lemos'), isTrue);
    });

    test('acha por pedaço do meio do nome', () {
      expect(alan.combinaCom('luc'), isTrue);
    });

    test('ignora maiúscula/minúscula', () {
      expect(alan.combinaCom('LEMOS'), isTrue);
      expect(alan.combinaCom('LeMoS'), isTrue);
    });

    test('ignora espaço em volta do termo', () {
      expect(alan.combinaCom('  lemos  '), isTrue);
    });

    test('acha pela família', () {
      expect(alan.combinaCom('águia'), isTrue);
    });

    test('acha pelo apelido', () {
      expect(
        _p(
          nome: 'Richard Gonsales',
          apelido: 'Ricardão',
        ).combinaCom('ricardão'),
        isTrue,
      );
    });

    test('termo vazio devolve todo mundo', () {
      expect(alan.combinaCom(''), isTrue);
      expect(alan.combinaCom('   '), isTrue);
    });

    test('não acha o que não existe', () {
      expect(alan.combinaCom('zzz'), isFalse);
    });
  });

  group('fromMap / toMap', () {
    test('ida e volta preserva os campos da ficha', () {
      final original = {
        'id': 'p1',
        'top_id': 't1',
        'full_name': 'Alan Lucas Lemos',
        'familia': 'ÁGUIA',
        'cidade': 'FRANCA',
        'estado': 'SÃO PAULO',
        'height_cm': 169.0,
        'weight_kg': 82.0,
        'blood_type': 'A+',
        'biotipo': 'condicionamento-fisico-equilibrado',
        'cirurgias': 'tíbia fíbula com placas',
        'atividade_fisica_semanal': '3 A 4 VEZES',
        'comorbidades': ['diabetes'],
        'alergias': 'PICADA ABELHAS',
        'plano_saude': 'UNIMED',
        'active': true,
      };

      final p = Participant.fromMap(original);
      expect(p.bloodType, 'A+');
      expect(p.familia, 'ÁGUIA');
      expect(p.biotipo, 'condicionamento-fisico-equilibrado');
      expect(p.imc, closeTo(28.7, 0.05));

      final volta = p.toMap();
      expect(volta['blood_type'], 'A+');
      expect(volta['comorbidades'], ['diabetes']);
      expect(volta['plano_saude'], 'UNIMED');
    });

    test('campos ausentes não quebram a leitura', () {
      final p = Participant.fromMap({
        'id': 'p1',
        'top_id': 't1',
        'full_name': 'Minimo',
      });
      expect(p.comorbidades, isEmpty);
      expect(p.active, isTrue);
      expect(p.imc, isNull);
      expect(p.idade, isNull);
    });
  });
}
