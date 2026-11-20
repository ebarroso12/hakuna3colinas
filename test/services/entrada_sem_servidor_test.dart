import 'package:flutter_test/flutter_test.dart';
import 'package:legendario_connect/services/entrada_sem_servidor.dart';

/// Servidor fora do ar não pode trancar quem já entrou neste aparelho, mas
/// também não pode abrir a porta para quem nunca foi aprovado.
void main() {
  group('podeEntrarSemServidor', () {
    test('mesmo usuário, aprovado da última vez: entra', () {
      expect(
        podeEntrarSemServidor(
          uid: 'a',
          uidGuardado: 'a',
          aprovadoGuardado: true,
        ),
        isTrue,
      );
    });

    test('outro usuário no mesmo aparelho: não entra', () {
      expect(
        podeEntrarSemServidor(
          uid: 'b',
          uidGuardado: 'a',
          aprovadoGuardado: true,
        ),
        isFalse,
      );
    });

    test('não estava aprovado: não entra', () {
      expect(
        podeEntrarSemServidor(
          uid: 'a',
          uidGuardado: 'a',
          aprovadoGuardado: false,
        ),
        isFalse,
      );
    });

    test('sem nada guardado: não entra', () {
      expect(
        podeEntrarSemServidor(
          uid: 'a',
          uidGuardado: null,
          aprovadoGuardado: null,
        ),
        isFalse,
      );
    });
  });

  group('codificação da aprovação guardada', () {
    test('ida e volta', () {
      final ok = lerAprovacaoGuardada(codificarAprovacao('a', true));
      expect(ok.uid, 'a');
      expect(ok.aprovado, isTrue);
      final no = lerAprovacaoGuardada(codificarAprovacao('a', false));
      expect(no.aprovado, isFalse);
    });

    test('lixo, vazio e nulo viram "sem cache"', () {
      for (final v in [null, '', 'a', 'a|2', '|1']) {
        final r = lerAprovacaoGuardada(v);
        expect(r.uid, isNull, reason: '$v');
        expect(r.aprovado, isNull, reason: '$v');
      }
    });
  });
}
