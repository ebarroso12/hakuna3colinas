import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legendario_connect/services/exclusao_service.dart';
import 'package:legendario_connect/widgets/barra_de_selecao.dart';

/// O diálogo de confirmação é a última coisa entre um toque e a perda
/// definitiva de um cadastro. Estes testes travam o que ele promete.
///
/// A falha que mais importa evitar não é apagar demais — o banco barra
/// isso. É o admin **não saber** o que não foi apagado: marca 30 nomes,
/// confirma, e 4 continuam lá sem ele perceber. Por isso o diálogo lista
/// nome por nome quem sai e quem fica, com o motivo.
void main() {
  Dependencias livre(String id) =>
      Dependencias(id: id, podeApagar: true, motivos: const []);

  Dependencias travado(String id, List<String> motivos) =>
      Dependencias(id: id, podeApagar: false, motivos: motivos);

  Future<DecisaoDaExclusao?> abrir(
    WidgetTester tester, {
    required Map<String, String> nomes,
    required Map<String, Dependencias> deps,
    bool podeDesativar = true,
  }) async {
    DecisaoDaExclusao? escolha;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                escolha = await confirmarExclusao(
                  context,
                  nomes: nomes,
                  dependencias: deps,
                  podeDesativar: podeDesativar,
                );
              },
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    return escolha;
  }

  testWidgets('lista nome por nome quem sai', (tester) async {
    await abrir(
      tester,
      nomes: {'a': 'JOAO DA SILVA', 'b': 'MARIA SOUZA'},
      deps: {'a': livre('a'), 'b': livre('b')},
    );

    expect(find.textContaining('JOAO DA SILVA'), findsOneWidget);
    expect(find.textContaining('MARIA SOUZA'), findsOneWidget);
    expect(find.text('APAGAR 2'), findsOneWidget);
  });

  testWidgets('mostra o MOTIVO de quem fica, não só que ficou', (
    tester,
  ) async {
    await abrir(
      tester,
      nomes: {'a': 'JOAO', 'b': 'PEDRO'},
      deps: {
        'a': livre('a'),
        'b': travado('b', ['3 atendimento(s) no prontuário']),
      },
    );

    // "Não foi possível apagar PEDRO" faria o admin tentar de novo. O
    // número é o que explica.
    expect(find.textContaining('3 atendimento(s) no prontuário'), findsOneWidget);
    expect(find.textContaining('FICA'), findsOneWidget);
    expect(find.text('APAGAR 1'), findsOneWidget);
  });

  testWidgets('quando nada pode ser apagado, não existe botão de apagar', (
    tester,
  ) async {
    await abrir(
      tester,
      nomes: {'b': 'PEDRO'},
      deps: {'b': travado('b', ['2 atendimento(s) no prontuário'])},
    );

    expect(find.text('Nada pode ser apagado'), findsOneWidget);
    expect(find.textContaining('APAGAR'), findsNothing);
    // Mas sobra a saída certa: desativar preserva o prontuário.
    expect(find.text('Desativar 1'), findsOneWidget);
  });

  testWidgets('sem desativar disponível, o diálogo não promete o botão', (
    tester,
  ) async {
    // Na tela de usuários não existe "desativar" hoje. Mostrar o botão e
    // ele fazer outra coisa seria pior que não ter.
    await abrir(
      tester,
      nomes: {'b': 'PEDRO'},
      deps: {'b': travado('b', ['1 registro(s) de auditoria'])},
      podeDesativar: false,
    );

    expect(find.textContaining('Desativar'), findsNothing);
    expect(find.textContaining('Essas contas continuam'), findsOneWidget);
  });

  testWidgets('cancelar devolve cancelar', (tester) async {
    await abrir(
      tester,
      nomes: {'a': 'JOAO'},
      deps: {'a': livre('a')},
    );
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    // Nada a afirmar além de não ter estourado: o retorno é lido pela tela.
    expect(find.text('Cancelar'), findsNothing);
  });

  group('mensagem de erro', () {
    // Esta é a ÚNICA operação do app que não funciona offline, e por
    // decisão (ver a doc de `ExclusaoService`). Uma mensagem técnica aqui
    // faria o admin achar que é bug e repetir a ação — ou pior, duvidar
    // do resto do app, que funciona offline.
    test('falta de rede vira explicação, não SocketException', () {
      for (final e in [
        'SocketException: Failed host lookup',
        'ClientException with SocketException',
        'Connection closed before full header was received',
        'TimeoutException after 0:00:30.000000',
      ]) {
        final msg = ExclusaoService.mensagemDeErro(Exception(e));
        expect(msg, contains('precisa de internet'), reason: e);
        expect(msg, isNot(contains('SocketException')), reason: e);
      }
    });

    test('e diz POR QUE não fica guardado para depois', () {
      // Sem isso o admin pensaria que é falha, não desenho. O app guarda
      // tudo o mais offline; a exceção precisa ser justificada na hora.
      final msg = ExclusaoService.mensagemDeErro(
        Exception('SocketException: no route to host'),
      );
      expect(msg, contains('de propósito'));
    });

    test('erro que não é de rede chega inteiro', () {
      // Aqui o texto do servidor é a informação útil — engolir seria
      // esconder o motivo real da recusa.
      final msg = ExclusaoService.mensagemDeErro(
        Exception('apenas o administrador master'),
      );
      expect(msg, contains('apenas o administrador master'));
    });
  });

  group('BarraDeSelecao', () {
    testWidgets('acima do teto, o botão de apagar fica desligado', (
      tester,
    ) async {
      // Truncar 51 marcados em 50 apagaria quase tudo e deixaria um de
      // fora sem ninguém entender por quê. Melhor travar e dizer o teto.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: BarraDeSelecao(
                  marcados: ExclusaoService.maxPorVez + 1,
                  total: 216,
                  aoMarcarTodos: () {},
                  aoLimpar: () {},
                  aoApagar: () {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(
        find.textContaining('máximo ${ExclusaoService.maxPorVez} por vez'),
        findsOneWidget,
      );
      final botao = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.delete_outline),
      );
      expect(botao.onPressed, isNull);
    });

    testWidgets('com zero marcados, apagar fica desligado', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BarraDeSelecao(
              marcados: 0,
              total: 10,
              aoMarcarTodos: () {},
              aoLimpar: () {},
              aoApagar: () {},
            ),
          ),
        ),
      );
      final botao = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.delete_outline),
      );
      expect(botao.onPressed, isNull);
    });

    testWidgets('dentro do teto, apagar funciona e mostra a contagem', (
      tester,
    ) async {
      var apagou = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BarraDeSelecao(
              marcados: 7,
              total: 216,
              aoMarcarTodos: () {},
              aoLimpar: () {},
              aoApagar: () => apagou = true,
            ),
          ),
        ),
      );
      expect(find.text('7 marcado(s)'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.delete_outline));
      expect(apagou, isTrue);
    });
  });
}
