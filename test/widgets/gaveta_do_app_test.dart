import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legendario_connect/versao.dart';
import 'package:legendario_connect/widgets/gaveta_do_app.dart';

/// O pedido era: mostrar a versão na lateral e, se estiver desatualizada,
/// um botão "Atualizar". Estes testes travam as duas pontas.
///
/// Sem Supabase inicializado, `AtualizacaoService.consultar` cai no catch e
/// devolve `null` — que é exatamente o estado "sem rede" do campo. É o
/// caso mais importante de acertar: é nele que o app passa a maior parte
/// do tempo numa trilha.
void main() {
  Future<void> abrirGaveta(WidgetTester tester, {int? pendentes}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          drawer: GavetaDoApp(pendentesNaFila: pendentes),
          body: const SizedBox.shrink(),
        ),
      ),
    );
    tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
    await tester.pumpAndSettle();
  }

  testWidgets('a versão instalada aparece na gaveta', (tester) async {
    await abrirGaveta(tester);

    // Aparece duas vezes: no cabeçalho e na linha de status. As duas são
    // intencionais — o cabeçalho identifica, a linha compara.
    expect(find.textContaining(Versao.completa), findsWidgets);
  });

  testWidgets('sem conseguir consultar, NÃO diz que está atualizado', (
    tester,
  ) async {
    await abrirGaveta(tester);

    // Esta é a regra que importa: `null` é "não sei", não "está em dia".
    // Afirmar que está na última sem ter conseguido verificar seria o app
    // inventando uma informação que não tem.
    expect(find.textContaining('Não foi possível verificar'), findsOneWidget);
    expect(find.textContaining('mais recente publicada'), findsNothing);
  });

  testWidgets('sem versão nova, não existe botão ATUALIZAR', (tester) async {
    await abrirGaveta(tester);
    expect(find.text('ATUALIZAR'), findsNothing);
  });

  testWidgets('a gaveta avisa que a instalação é fora da Play Store', (
    tester,
  ) async {
    await abrirGaveta(tester);
    expect(find.textContaining('fontes desconhecidas'), findsOneWidget);
  });
}
