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

    test('uid vazio nunca entra, mesmo "igual" ao guardado', () {
      expect(
        podeEntrarSemServidor(uid: '', uidGuardado: '', aprovadoGuardado: true),
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

  // A decisão do `catch` de `AuthGate._checkApproval`, fora da tela para
  // poder ser testada sem montar a árvore nem fingir o Supabase. Era ali,
  // inline, que um erro de leitura (trocar `&&` por `||`, esquecer o uid)
  // abriria a porta para quem não devia — e nada pegaria.
  group('entraNaFalha', () {
    const redeFora = 'ClientException with SocketException: Failed host lookup';

    test('erro que não é de rede: não entra, mesmo aprovado', () {
      expect(
        entraNaFalha(
          erro: Exception('PostgrestException: permission denied'),
          uid: 'a',
          guardado: codificarAprovacao('a', true),
        ),
        isFalse,
      );
    });

    test('sem sessão (uid nulo): não entra', () {
      expect(
        entraNaFalha(
          erro: Exception(redeFora),
          uid: null,
          guardado: codificarAprovacao('a', true),
        ),
        isFalse,
      );
    });

    test('rede fora + mesma conta aprovada: entra', () {
      expect(
        entraNaFalha(
          erro: Exception(redeFora),
          uid: 'a',
          guardado: codificarAprovacao('a', true),
        ),
        isTrue,
      );
    });

    test('rede fora + outra conta guardada: não entra', () {
      expect(
        entraNaFalha(
          erro: Exception(redeFora),
          uid: 'b',
          guardado: codificarAprovacao('a', true),
        ),
        isFalse,
      );
    });

    test('rede fora + mesma conta NÃO aprovada: não entra', () {
      expect(
        entraNaFalha(
          erro: Exception(redeFora),
          uid: 'a',
          guardado: codificarAprovacao('a', false),
        ),
        isFalse,
      );
    });

    test('rede fora + nada guardado ou lixo: não entra', () {
      for (final g in [null, '', 'lixo']) {
        expect(
          entraNaFalha(erro: Exception(redeFora), uid: 'a', guardado: g),
          isFalse,
          reason: '$g',
        );
      }
    });
  });
}
