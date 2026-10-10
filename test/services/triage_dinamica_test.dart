import 'package:flutter_test/flutter_test.dart';
import 'package:hakuna_connect/models/afericao.dart';
import 'package:hakuna_connect/models/triage_rule.dart';
import 'package:hakuna_connect/services/triage_dinamica.dart';

/// Testa o caso que motivou o módulo: participante **verde** no cadastro
/// com PA 190x120 e SpO₂ 88% aferidos em campo continuava verde na lista.
void main() {
  Afericao afericao({int? spo2, int? pas, int? pad}) => Afericao(
    medidoEm: DateTime(2026, 10, 10, 14, 30),
    spo2: spo2,
    systolicBp: pas,
    diastolicBp: pad,
  );

  group('o bug original', () {
    test('verde no cadastro com PA 190x120 e SpO2 88% vira vermelho', () {
      final g = TriageDinamica.avaliar(
        corDeCadastro: TriageColor.green,
        afericao: afericao(spo2: 88, pas: 190, pad: 120),
      );

      expect(g.cor, TriageColor.red);
      expect(g.escalada, isTrue);
      expect(g.motivos, ['SpO₂ 88%', 'PA 190 x 120']);
      // O cadastro não é apagado — ele explica a cor de base e volta a
      // valer quando uma aferição normal chegar.
      expect(g.corDeCadastro, TriageColor.green);
    });
  });

  group('sem aferição não muda nada', () {
    test('aferição nula devolve a cor de cadastro', () {
      final g = TriageDinamica.avaliar(corDeCadastro: TriageColor.blue);
      expect(g.cor, TriageColor.blue);
      expect(g.escalada, isFalse);
      expect(g.motivos, isEmpty);
    });

    test('atendimento só de observação não escala', () {
      final g = TriageDinamica.avaliar(
        corDeCadastro: TriageColor.green,
        afericao: afericao(),
      );
      expect(g.cor, TriageColor.green);
      expect(g.escalada, isFalse);
    });

    test('cadastro sem cor continua sem cor quando a aferição é normal', () {
      final g = TriageDinamica.avaliar(
        corDeCadastro: null,
        afericao: afericao(spo2: 97, pas: 120, pad: 80),
      );
      expect(g.cor, isNull);
      expect(g.escalada, isFalse);
    });
  });

  group('limiares — exatamente na borda', () {
    test('SpO2 90 NÃO escala; 89 escala', () {
      expect(
        TriageDinamica.avaliar(
          corDeCadastro: TriageColor.green,
          afericao: afericao(spo2: 90),
        ).escalada,
        isFalse,
      );
      expect(
        TriageDinamica.avaliar(
          corDeCadastro: TriageColor.green,
          afericao: afericao(spo2: 89),
        ).motivos,
        ['SpO₂ 89%'],
      );
    });

    test('sistólica 180 NÃO escala; 181 escala', () {
      expect(
        TriageDinamica.avaliar(
          corDeCadastro: TriageColor.green,
          afericao: afericao(pas: 180, pad: 100),
        ).escalada,
        isFalse,
      );
      expect(
        TriageDinamica.avaliar(
          corDeCadastro: TriageColor.green,
          afericao: afericao(pas: 181, pad: 100),
        ).cor,
        TriageColor.red,
      );
    });

    test('diastólica 110 NÃO escala; 111 escala', () {
      expect(
        TriageDinamica.avaliar(
          corDeCadastro: TriageColor.green,
          afericao: afericao(pas: 140, pad: 110),
        ).escalada,
        isFalse,
      );
      expect(
        TriageDinamica.avaliar(
          corDeCadastro: TriageColor.green,
          afericao: afericao(pas: 140, pad: 111),
        ).cor,
        TriageColor.red,
      );
    });

    test('diastólica crítica sozinha escala, mesmo com sistólica normal', () {
      final g = TriageDinamica.avaliar(
        corDeCadastro: TriageColor.green,
        afericao: afericao(pas: 130, pad: 125),
      );
      expect(g.cor, TriageColor.red);
      expect(g.motivos, ['PA 130 x 125']);
    });
  });

  group('nunca rebaixa', () {
    test('aferição normal não transforma vermelho de cadastro em verde', () {
      final g = TriageDinamica.avaliar(
        corDeCadastro: TriageColor.red,
        afericao: afericao(spo2: 99, pas: 115, pad: 70),
      );
      expect(g.cor, TriageColor.red);
      // Não foi escalada: a cor é a do cadastro, não da aferição.
      expect(g.escalada, isFalse);
    });

    test('para toda cor de cadastro, o resultado nunca é menos grave', () {
      const ordem = {
        TriageColor.blue: 0,
        TriageColor.green: 1,
        TriageColor.yellow: 2,
        TriageColor.red: 3,
      };
      for (final base in TriageColor.values) {
        for (final spo2 in [null, 80, 89, 90, 97]) {
          for (final pas in [null, 110, 180, 200]) {
            final g = TriageDinamica.avaliar(
              corDeCadastro: base,
              afericao: afericao(spo2: spo2, pas: pas, pad: 80),
            );
            expect(
              ordem[g.cor]!,
              greaterThanOrEqualTo(ordem[base]!),
              reason:
                  'cadastro $base + SpO2 $spo2 + PAS $pas rebaixou para '
                  '${g.cor}',
            );
          }
        }
      }
    });
  });

  group('escala mesmo sem ficha completa', () {
    test('SpO2 85 em participante sem cor de cadastro dá vermelho', () {
      // Sem data de nascimento não há cor estática. Isso não pode impedir
      // a escalada: o paciente está hipoxêmico independente da ficha.
      final g = TriageDinamica.avaliar(
        corDeCadastro: null,
        afericao: afericao(spo2: 85),
      );
      expect(g.cor, TriageColor.red);
      expect(g.escalada, isTrue);
    });
  });

  group('valor implausível não é silenciado', () {
    test('SpO2 3 escala com motivo de reaferição', () {
      final g = TriageDinamica.avaliar(
        corDeCadastro: TriageColor.green,
        afericao: afericao(spo2: 3),
      );
      expect(g.cor, TriageColor.red);
      expect(g.motivos.single, contains('reaferir'));
    });

    test('SpO2 0 (oxímetro sem leitura) não fica verde', () {
      final g = TriageDinamica.avaliar(
        corDeCadastro: TriageColor.green,
        afericao: afericao(spo2: 0),
      );
      expect(g.cor, TriageColor.red);
    });
  });

  group('valorCritico — aviso durante a digitação', () {
    test('avisa antes de salvar, com os mesmos limiares', () {
      expect(TriageDinamica.valorCritico(spo2: 88), isTrue);
      expect(TriageDinamica.valorCritico(sistolica: 190), isTrue);
      expect(TriageDinamica.valorCritico(diastolica: 115), isTrue);
      expect(TriageDinamica.valorCritico(spo2: 97), isFalse);
      expect(TriageDinamica.valorCritico(), isFalse);
    });
  });
}
