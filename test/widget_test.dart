import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:legendario_connect/screens/login_screen.dart';
import 'package:legendario_connect/services/acesso_service.dart';

void main() {
  group('LoginScreen', () {
    testWidgets('um campo só, que aceita número ou e-mail', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

      // Era 'E-mail'. Mudou porque o Legendário entra pelo NÚMERO dele, e
      // um campo chamado "E-mail" faria ele procurar um e-mail que não
      // existe — `203460@legendarios.app` nunca é digitado por ninguém.
      expect(find.text('Número do Legendários ou e-mail'), findsOneWidget);
      expect(find.text('Senha'), findsOneWidget);
      expect(find.text('Entrar'), findsOneWidget);
    });

    testWidgets('o botão de primeiro acesso não se confunde com o campo', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

      // O rótulo era "Entrar com número do Legendários", que ficou ambíguo
      // quando o campo principal passou a aceitar número. Este botão leva a
      // outra coisa: quem ainda NÃO tem conta se cadastra com a senha que
      // o admin anunciou para o Top.
      expect(find.text('Primeiro acesso'), findsOneWidget);
    });
  });

  group('identificadorParaEmail — número ou e-mail no mesmo campo', () {
    test('número vira o e-mail interno', () {
      expect(
        AcessoService.identificadorParaEmail('203460'),
        '203460@legendarios.app',
      );
    });

    test('e-mail passa intacto', () {
      expect(
        AcessoService.identificadorParaEmail('edson.barroso@gmail.com'),
        'edson.barroso@gmail.com',
      );
    });

    test('espaço em volta não atrapalha', () {
      expect(
        AcessoService.identificadorParaEmail('  203460  '),
        '203460@legendarios.app',
      );
      expect(
        AcessoService.identificadorParaEmail('  a@b.com '),
        'a@b.com',
      );
    });

    test('a decisão é o arroba, e número nunca tem arroba', () {
      // Garante que a regra não fica ambígua: todo valor que passa em
      // numeroValido é tratado como número.
      for (final n in ['7', '1782', '203460', '123456789012']) {
        expect(AcessoService.numeroValido(n), isTrue, reason: n);
        expect(
          AcessoService.identificadorParaEmail(n),
          endsWith('@legendarios.app'),
          reason: n,
        );
      }
    });
  });

  group('numeroValido — 1 a 12 dígitos', () {
    test('aceita de 1 a 12', () {
      expect(AcessoService.numeroValido('7'), isTrue);
      expect(AcessoService.numeroValido('203460'), isTrue);
      expect(AcessoService.numeroValido('123456789012'), isTrue);
    });

    test('recusa 13 dígitos', () {
      // O teto existe para não gravar lixo; 12 foi a decisão do usuário
      // ("não sabemos até onde parar").
      expect(AcessoService.numeroValido('1234567890123'), isFalse);
    });

    test('recusa letra, espaço no meio e vazio', () {
      expect(AcessoService.numeroValido('12a456'), isFalse);
      expect(AcessoService.numeroValido('123 456'), isFalse);
      expect(AcessoService.numeroValido(''), isFalse);
    });

    test('a regra tem de ser a MESMA da Edge Function', () {
      // TypeScript não importa Dart: esta regex existe duas vezes, aqui e
      // em `numeroValido` na função `acesso`. Se divergirem, o app aceita e
      // o servidor recusa — e a mensagem só diz "número inválido".
      expect(AcessoService.regexNumero, r'^[0-9]{1,12}$');
    });
  });
}
