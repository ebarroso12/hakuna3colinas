import 'package:flutter_test/flutter_test.dart';
import 'package:legendario_connect/services/supabase_service.dart';

/// Em 20/11/2026 ninguém conseguia entrar no app, e a causa não era o app:
/// o projeto do Supabase estava **pausado** (o plano gratuito pausa depois
/// de dias sem uso) e o endereço `<ref>.supabase.co` parou de existir.
///
/// O que a tela mostrava nesse caso era o texto cru do Dart —
/// `ClientException with SocketException: Failed host lookup: ...` — ou,
/// pior, nada que separasse "servidor fora" de "senha errada". Quem lê
/// isso troca a senha, pede código novo ao admin e continua sem entrar.
///
/// Estes testes travam a tradução: erro de rede vira uma frase que diz o
/// que fazer, e NUNCA vira "senha incorreta".
void main() {
  group('sem conseguir falar com o servidor', () {
    const exemplos = [
      // Android/iOS: DNS do projeto pausado ou sem internet nenhuma.
      "ClientException with SocketException: Failed host lookup: "
          "'abc.supabase.co' (OS Error: No address associated with "
          "hostname, errno = 7)",
      'SocketException: Connection refused',
      'SocketException: Network is unreachable',
      'ClientException: Connection closed before full header was received',
      'TimeoutException after 0:00:30.000000: Future not completed',
      // Web: o navegador esconde a causa e diz só isto.
      'ClientException: XMLHttpRequest error.',
      'ClientException: Failed to fetch',
    ];

    for (final cru in exemplos) {
      test('"${cru.split(':').first}" vira aviso de servidor', () {
        final msg = friendlyAuthError(Exception(cru), usouNumero: true);
        expect(msg, contains('servidor'));
        expect(msg.toLowerCase(), isNot(contains('senha incorret')));
        // O texto cru não pode chegar à tela.
        expect(msg, isNot(contains('Exception')));
        expect(msg, isNot(contains('supabase.co')));
      });
    }
  });

  test('senha errada continua dizendo senha errada', () {
    final msg = friendlyAuthError(
      Exception('Invalid login credentials'),
      usouNumero: true,
    );
    expect(msg, startsWith('Número ou senha incorretos'));
    expect(msg, isNot(contains('servidor')));
  });

  test('pareceErroDeRede reconhece só rede', () {
    expect(pareceErroDeRede('Failed host lookup'), isTrue);
    expect(pareceErroDeRede('Invalid login credentials'), isFalse);
    expect(pareceErroDeRede('Database error saving new user'), isFalse);
  });
}
