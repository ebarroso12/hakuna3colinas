// A senha do Top é do admin master. Decisão do dono em 23/11/2026:
// *"esta senha deve ser gerada dentro do app somente pelos master... os
// admin master terão todo acesso"*.
//
// **Este teste não é a trava.** A trava é o trigger `tops_trava_senha`
// (`supabase/07_senha_do_top_so_o_master.sql`) mais a conferência dentro
// da Edge Function `acesso` — a chave anônima está dentro do APK e alcança
// `tops` por `PATCH` direto, então esconder o botão não protege nada. O que
// este teste trava é o OUTRO lado: que a tela não ofereça um botão que o
// servidor vai recusar, e que ela DIGA quem faz, em vez de só esconder.
//
// Por que texto e não só ausência de botão: o `CLAUDE.md` registra, na
// correção das 9 equipes, que "o texto é a correção, não enfeite" — porta
// fechada sem explicação parece defeito, e o admin tenta de novo.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:legendario_connect/models/top.dart';
import 'package:legendario_connect/screens/admin/admin_top_form_screen.dart';

void main() {
  Top topDe({
    String? numero = '1922',
    String? local = 'Pista 3 Colinas',
    String? diretor = 'Diretor do evento',
    bool autocadastro = false,
  }) => Top(
    id: 'top-1',
    name: 'TRACK 3 Colinas',
    topNumber: numero,
    location: local,
    cidade: 'Franca',
    diretorResponsavel: diretor,
    emblemaPath: null,
    description: null,
    status: TopStatus.active,
    startsAt: null,
    endsAt: null,
    autocadastroLiberado: autocadastro,
  );

  Future<void> montar(
    WidgetTester tester, {
    required bool master,
    Top? top,
  }) async {
    // Superfície alta: o formulário é uma lista longa e o bloco da senha
    // fica no fim. Com tela de celular o `ListView` não constrói o que não
    // aparece, e o teste falharia por rolagem, não por regra — foi o erro
    // cometido em `as_nove_equipes_aparecem_test.dart`.
    tester.view.physicalSize = const Size(1000, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: AdminTopFormScreen(top: top ?? topDe(), isMasterAdmin: master),
      ),
    );
    await tester.pump();
  }

  testWidgets('o master vê o botão de gerar a senha', (tester) async {
    await montar(tester, master: true);
    expect(find.text('Gerar senha do Top'), findsOneWidget);
  });

  testWidgets('o admin comum NÃO vê o botão, e a tela diz quem faz', (
    tester,
  ) async {
    await montar(tester, master: false);

    expect(find.text('Gerar senha do Top'), findsNothing);

    // Não basta esconder: tem de explicar, e tem de dizer que ele ainda
    // distribui a senha — distribuir é falar, não é permissão.
    expect(
      find.textContaining('Só o administrador master gera a senha'),
      findsOneWidget,
    );
    expect(find.textContaining('distribuir'), findsOneWidget);
  });

  testWidgets('cadastro FECHADO: o admin comum não consegue abrir', (
    tester,
  ) async {
    await montar(tester, master: false, top: topDe(autocadastro: false));

    final sw = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(
      sw.onChanged,
      isNull,
      reason: 'admin comum não abre o cadastro; o banco recusa com 42501',
    );
    expect(
      find.textContaining('Só o administrador master abre o cadastro'),
      findsOneWidget,
    );
  });

  testWidgets('cadastro ABERTO: o admin comum PODE fechar', (tester) async {
    await montar(tester, master: false, top: topDe(autocadastro: true));

    final sw = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(
      sw.onChanged,
      isNotNull,
      reason: 'fechar é sempre o lado seguro, e não precisa do master',
    );
  });

  testWidgets('o master abre e fecha', (tester) async {
    await montar(tester, master: true, top: topDe(autocadastro: false));
    var sw = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(sw.onChanged, isNotNull);

    await montar(tester, master: true, top: topDe(autocadastro: true));
    sw = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(sw.onChanged, isNotNull);
  });

  testWidgets('sem número, pista ou diretor, gerar a senha é recusado e a '
      'tela diz o que falta', (tester) async {
    await montar(
      tester,
      master: true,
      top: topDe(numero: null, local: null, diretor: null),
    );

    await tester.tap(find.text('Gerar senha do Top'));
    await tester.pumpAndSettle();

    expect(find.text('Falta identificar o Top'), findsOneWidget);
    expect(find.textContaining('Número do Top'), findsWidgets);
    expect(find.textContaining('Local / pista'), findsWidgets);
    expect(find.textContaining('Diretor responsável'), findsWidgets);

    // O diálogo de confirmação de gerar NÃO pode ter aparecido: a conferência
    // vem antes, senão o admin confirma e só então descobre que falta campo.
    expect(find.text('Gerar senha do Top?'), findsNothing);
  });

  testWidgets('com os campos preenchidos, gerar pede confirmação', (
    tester,
  ) async {
    await montar(tester, master: true);

    await tester.tap(find.text('Gerar senha do Top'));
    await tester.pumpAndSettle();

    // Gerar de novo invalida a senha anterior na hora, então tem de ser
    // escolha consciente e não um toque acidental.
    expect(find.text('Gerar senha do Top?'), findsOneWidget);
    expect(find.textContaining('INVALIDA a anterior'), findsOneWidget);
  });
}
