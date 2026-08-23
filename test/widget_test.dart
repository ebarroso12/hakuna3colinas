import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hakuna_connect/screens/login_screen.dart';

void main() {
  testWidgets('LoginScreen mostra campos de e-mail e senha', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('E-mail'), findsOneWidget);
    expect(find.text('Senha'), findsOneWidget);
    expect(find.text('Entrar'), findsOneWidget);
  });
}
