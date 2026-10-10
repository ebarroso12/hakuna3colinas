import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legendario_connect/widgets/app_logo.dart';

/// A falha que estes testes travam é a gaveta inalcançável.
///
/// `Scaffold` só desenha o botão de hambúrguer quando `leading` é nulo, e a
/// tela raiz põe a logo ali. Se a logo não abrir a gaveta, ela só existe
/// arrastando a borda da tela — e ninguém descobre isso. O recurso estaria
/// escrito, testado por dentro e inacessível.
void main() {
  Widget cena({bool novidade = false}) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(leading: AppLogoAbreGaveta(novidade: novidade)),
        drawer: const Drawer(child: Text('conteudo da gaveta')),
        body: const SizedBox.shrink(),
      ),
    );
  }

  testWidgets('tocar na logo abre a gaveta', (tester) async {
    await tester.pumpWidget(cena());
    expect(find.text('conteudo da gaveta'), findsNothing);

    await tester.tap(find.byType(AppLogoAbreGaveta));
    await tester.pumpAndSettle();

    expect(find.text('conteudo da gaveta'), findsOneWidget);
  });

  testWidgets('sem novidade, nenhum ponto sobre a logo', (tester) async {
    await tester.pumpWidget(cena());
    final badge = tester.widget<Badge>(find.byType(Badge));
    expect(badge.isLabelVisible, isFalse);
  });

  testWidgets('com versão nova, o ponto aparece', (tester) async {
    // É o único aviso que o usuário recebe sem abrir a gaveta.
    await tester.pumpWidget(cena(novidade: true));
    final badge = tester.widget<Badge>(find.byType(Badge));
    expect(badge.isLabelVisible, isTrue);
  });
}
