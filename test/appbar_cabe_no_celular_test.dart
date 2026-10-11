import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A AppBar tem de caber no celular de quem usa.
///
/// Ninguém tinha medido, e a tela do Top havia chegado a **11 ações**: a
/// Row da AppBar estourava 168 px e o Flutter cortava em silêncio o que
/// passava da borda direita. Pulseiras NFC, Equipes do Top e Quem vê o
/// mapa existiam, abriam por código, passavam em teste — e eram
/// inalcançáveis num aparelho de 360 dp. Achado em 11/10/2026, antes da
/// primeira instalação.
///
/// Não há aviso: em release o excesso é clipado sem erro nenhum. Daí este
/// teste, que mede de verdade em vez de confiar em estimativa.
void main() {
  /// Mede quantas ações de 48 dp a AppBar aceita antes de estourar.
  Future<int> maximoDeAcoes(WidgetTester tester, double largura) async {
    tester.view.physicalSize = Size(largura, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    var cabe = 0;
    for (var n = 1; n <= 14; n++) {
      // Derruba a árvore entre medições. O `RenderFlex` reporta o estouro
      // uma única vez por instância, então reaproveitar o render object da
      // iteração anterior engole o erro e o teste mediria 14 — foi o que
      // aconteceu na primeira tentativa.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            // Título longo de propósito: é o nome real de um Top. O título
            // fica na fatia flexível do meio e encolhe, então não deveria
            // influir — e o teste prova que não influi.
            appBar: AppBar(
              title: const Text('Top de Franca — comemoração de 1 ano'),
              actions: [
                for (var i = 0; i < n; i++)
                  IconButton(
                    icon: const Icon(Icons.circle),
                    onPressed: () {},
                  ),
              ],
            ),
            body: const SizedBox(),
          ),
        ),
      );
      if (tester.takeException() == null) cabe = n;
    }
    return cabe;
  }

  testWidgets('num celular de 360 dp caibem 7 ações, não mais', (
    tester,
  ) async {
    expect(await maximoDeAcoes(tester, 360), 7);
  });

  testWidgets('num aparelho estreito de 320 dp caibem 6', (tester) async {
    expect(await maximoDeAcoes(tester, 320), 6);
  });

  /// Conta as ações declaradas no `actions:` de cada tela, lendo o fonte.
  ///
  /// Lê indentação porque o projeto é formatado pelo `dart format`: cada
  /// entrada da lista começa na mesma coluna. Não é um parser de Dart, e
  /// não precisa ser — precisa só quebrar se alguém empilhar demais.
  int acoesDeclaradas(String fonte) {
    final linhas = fonte.split('\n');
    final abre = linhas.indexWhere((l) => l.trimRight().endsWith('actions: ['));
    if (abre < 0) return 0;

    final recuo = linhas[abre].indexOf('actions:') + 2;
    var total = 0;
    for (var i = abre + 1; i < linhas.length; i++) {
      final linha = linhas[i];
      final semEspaco = linha.trimLeft();
      if (semEspaco.isEmpty || semEspaco.startsWith('//')) continue;
      final coluna = linha.length - semEspaco.length;
      if (coluna < recuo) break; // fechou a lista
      if (coluna != recuo) continue; // continuação da entrada anterior
      // `if (cond)` com a entrada na linha seguinte conta uma vez só.
      if (semEspaco.startsWith('if (') && !semEspaco.contains(')  ')) {
        if (semEspaco.endsWith(')')) continue;
      }
      total++;
    }
    return total;
  }

  test('nenhuma tela declara mais de 7 ações na AppBar', () {
    final telas = Directory(
      'lib/screens',
    ).listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

    final estouradas = <String, int>{};
    for (final tela in telas) {
      final n = acoesDeclaradas(tela.readAsStringSync());
      if (n > 7) estouradas[tela.uri.pathSegments.last] = n;
    }

    expect(
      estouradas,
      isEmpty,
      reason:
          'Estas telas têm mais ações do que cabe num celular de 360 dp. '
          'O excesso é cortado em silêncio na borda direita — o botão '
          'existe e ninguém alcança. Mova o que for de mesa para um '
          'PopupMenuButton, como em top_detail_screen.dart: $estouradas',
    );
  });
}
