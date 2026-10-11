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

  group('varredura do fonte — nenhuma AppBar passa de 7 ações', () {
    // A primeira versão desta varredura era por INDENTAÇÃO, e não media
    // nada: `indexWhere(endsWith('actions: ['))` pegava o PRIMEIRO
    // `actions:` do arquivo, que em `top_detail_screen.dart` é o de um
    // AlertDialog na linha 171. A AppBar de verdade, 160 linhas abaixo,
    // nunca era contada — uma oitava ação passaria batido, que é
    // exatamente o que o teste existe para impedir. Pior ainda, a
    // indentação contava o `),` de fecho de cada entrada como se fosse
    // outra entrada.
    //
    // Agora é casamento de delimitadores, pulando string e comentário.
    // Não é um parser de Dart; é o suficiente para contar entradas de uma
    // lista literal, e erra para o lado seguro (um `...[]` conta as
    // entradas de dentro, que é o limite superior).

    /// Onde termina o delimitador aberto em [inicio].
    ///
    /// [inicio] aponta para `(` ou `[`. Devolve o índice do fecho
    /// correspondente, pulando literais de string e comentários — sem
    /// isso, um tooltip com vírgula ou um `Icons.add_photo_alternate` em
    /// comentário desalinhariam a contagem.
    int fechoDe(String src, int inicio) {
      final abre = src[inicio];
      final fecha = abre == '(' ? ')' : ']';
      var nivel = 0;
      var i = inicio;
      while (i < src.length) {
        final c = src[i];

        if (c == '/' && i + 1 < src.length) {
          if (src[i + 1] == '/') {
            final fim = src.indexOf('\n', i);
            i = fim < 0 ? src.length : fim;
            continue;
          }
          if (src[i + 1] == '*') {
            final fim = src.indexOf('*/', i);
            i = fim < 0 ? src.length : fim + 2;
            continue;
          }
        }

        if (c == "'" || c == '"') {
          // Tudo dentro da string é pulado, interpolação incluída. Um
          // `[` dentro de `'${lista[0]}'` não conta como delimitador.
          final tripla = src.startsWith(c * 3, i);
          final marca = tripla ? c * 3 : c;
          var j = i + marca.length;
          while (j < src.length) {
            if (src[j] == r'\') {
              j += 2;
              continue;
            }
            if (src.startsWith(marca, j)) {
              j += marca.length;
              break;
            }
            j++;
          }
          i = j;
          continue;
        }

        if (c == abre || (abre == '(' && c == '[') || (abre == '[' && c == '(')) {
          nivel++;
        } else if (c == fecha ||
            (abre == '(' && c == ']') ||
            (abre == '[' && c == ')')) {
          nivel--;
          if (nivel == 0 && c == fecha) return i;
        }
        i++;
      }
      return -1;
    }

    /// Conta as entradas de uma lista literal que começa em [inicio] (`[`).
    ///
    /// Entrada = vírgula no nível zero. O projeto é formatado pelo
    /// `dart format`, que deixa vírgula final, então vírgulas no nível
    /// zero é exatamente o número de entradas. Um `...[` espalhado tem as
    /// entradas de dentro somadas: três widgets dentro de um spread
    /// ocupam três lugares na barra.
    int entradasDaLista(String src, int inicio) {
      final fim = fechoDe(src, inicio);
      if (fim < 0) return 0;

      var total = 0;
      var nivel = 0;
      var i = inicio + 1;
      var ultimoTemConteudo = false;

      while (i < fim) {
        final c = src[i];

        if (c == '/' && i + 1 < fim) {
          if (src[i + 1] == '/') {
            final f = src.indexOf('\n', i);
            i = f < 0 ? fim : f;
            continue;
          }
          if (src[i + 1] == '*') {
            final f = src.indexOf('*/', i);
            i = f < 0 ? fim : f + 2;
            continue;
          }
        }

        if (c == "'" || c == '"') {
          final tripla = src.startsWith(c * 3, i);
          final marca = tripla ? c * 3 : c;
          var j = i + marca.length;
          while (j < src.length) {
            if (src[j] == r'\') {
              j += 2;
              continue;
            }
            if (src.startsWith(marca, j)) {
              j += marca.length;
              break;
            }
            j++;
          }
          i = j;
          ultimoTemConteudo = true;
          continue;
        }

        // Spread: conta o que tem dentro, não um só.
        if (nivel == 0 && src.startsWith('...', i)) {
          final corchete = src.indexOf('[', i);
          if (corchete > 0 && corchete < fim) {
            total += entradasDaLista(src, corchete);
            i = fechoDe(src, corchete) + 1;
            // Consome a vírgula que separa o spread da entrada seguinte.
            // Sem isto ela era contada POR CIMA das entradas de dentro, e
            // `[...[A(), B()], C()]` dava 4 em vez de 3 — o próprio
            // auto-teste logo abaixo pegou isso.
            while (i < fim && src[i].trim().isEmpty) {
              i++;
            }
            if (i < fim && src[i] == ',') i++;
            ultimoTemConteudo = false;
            continue;
          }
        }

        if ('([{'.contains(c)) {
          nivel++;
        } else if (')]}'.contains(c)) {
          nivel--;
        } else if (c == ',' && nivel == 0) {
          total++;
          ultimoTemConteudo = false;
          i++;
          continue;
        } else if (c.trim().isNotEmpty) {
          ultimoTemConteudo = true;
        }
        i++;
      }

      // Sem vírgula final (lista de uma linha, `const [BotaoInicio()]`).
      if (ultimoTemConteudo) total++;
      return total;
    }

    /// Maior número de ações declaradas numa AppBar deste fonte.
    ///
    /// Procura `AppBar(` e `SliverAppBar(` — e **só dentro delas** o
    /// `actions:`. É o que impede o AlertDialog de ser medido no lugar da
    /// barra.
    int maiorAppBar(String src) {
      var maior = 0;
      for (final padrao in ['AppBar(', 'SliverAppBar(']) {
        var de = 0;
        while (true) {
          final i = src.indexOf(padrao, de);
          if (i < 0) break;
          de = i + padrao.length;

          final abre = i + padrao.length - 1; // o '('
          final fim = fechoDe(src, abre);
          if (fim < 0) continue;

          final corpo = src.substring(abre, fim);
          final a = corpo.indexOf('actions:');
          if (a < 0) continue;
          final corchete = corpo.indexOf('[', a);
          if (corchete < 0) continue;

          final n = entradasDaLista(corpo, corchete);
          if (n > maior) maior = n;
        }
      }
      return maior;
    }

    test('o contador conta o que eu digo que ele conta', () {
      // Sem isto, o contador poderia estar quebrado e o teste de varredura
      // passaria sempre — que foi o defeito da primeira versão.
      expect(maiorAppBar('AppBar(actions: [A(), B()])'), 2);
      expect(maiorAppBar('AppBar(actions: const [A()])'), 1);
      expect(
        maiorAppBar("AppBar(actions: [A(tooltip: 'a, b, c'), B()])"),
        2,
        reason: 'vírgula dentro de string não é separador',
      );
      expect(
        maiorAppBar('AppBar(actions: [if (x) A(), B()])'),
        2,
        reason: 'if na entrada conta uma vez',
      );
      expect(
        maiorAppBar('AppBar(actions: [...[A(), B()], C()])'),
        3,
        reason: 'spread soma o que tem dentro',
      );
      expect(
        maiorAppBar('AlertDialog(actions: [A(), B(), C()])'),
        0,
        reason: 'actions de dialog NÃO é a barra — foi o bug da v1 deste teste',
      );
      expect(
        maiorAppBar('''
          AlertDialog(actions: [A(), B(), C()]),
          AppBar(actions: [X()]),
        '''),
        1,
        reason: 'com dialog antes, mede a AppBar e não o dialog',
      );
    });

    test('a AppBar da tela do Top é medida, e tem no máximo 7', () {
      final src = File(
        'lib/screens/top_detail_screen.dart',
      ).readAsStringSync();
      final n = maiorAppBar(src);
      expect(n, greaterThan(0), reason: 'a varredura tem de ACHAR a AppBar');
      expect(n, lessThanOrEqualTo(7));
    });

    test('nenhuma tela declara mais de 7 ações na AppBar', () {
      final telas = Directory('lib/screens')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));

      final estouradas = <String, int>{};
      for (final tela in telas) {
        final n = maiorAppBar(tela.readAsStringSync());
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
  });
}
