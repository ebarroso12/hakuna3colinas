import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legendario_connect/widgets/botao_inicio.dart';

/// Trava a regra: **nenhuma tela prende o usuário**.
///
/// Duas saídas, e as duas precisam existir. A seta de voltar devolve UM
/// passo; quem está em Top → participantes → ficha → prontuário →
/// atendimento precisa de cinco toques para sair. Numa trilha, com o
/// celular numa mão, isso é caminho longo demais — daí o botão de início.
///
/// O teste lê o CÓDIGO-FONTE das telas em vez de instanciá-las. Instanciar
/// as 35 exigiria Supabase, GPS, NFC e câmera de mentira; o que se quer
/// garantir aqui é mais simples e mais durável: que ninguém crie uma tela
/// nova sem saída. É a mesma ideia do guarda de versão em
/// `versao_bate_com_pubspec_test.dart`.
void main() {
  /// Telas que NÃO levam o botão de início, com o motivo.
  ///
  /// Esta lista é o ponto da revisão: para isentar uma tela, alguém tem de
  /// vir aqui e escrever por quê.
  const semBotaoDeInicio = <String, String>{
    'tops_screen.dart': 'é a própria tela inicial',
    'auth_gate.dart': 'é roteador, não tem AppBar nem é tela',
    'pending_approval_screen.dart':
        'não tem AppBar; a saída dela é o botão Sair',
    'login_screen.dart': 'antes do login não existe "início"',
    'signup_screen.dart': 'antes do login',
    'login_numero_screen.dart': 'antes do login',
    'login_with_code_screen.dart': 'antes do login',
    'primeiro_acesso_screen.dart': 'antes do login',
    'cadastro_legendario_screen.dart': 'antes do login',
  };

  late List<File> telas;

  setUpAll(() {
    final dir = Directory('lib/screens');
    expect(
      dir.existsSync(),
      isTrue,
      reason: 'o teste roda da raiz do projeto; sem isto nao verifica nada',
    );
    telas = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(
      telas.length,
      greaterThan(20),
      reason: 'achou telas de menos — o caminho deve estar errado',
    );
  });

  test('toda tela interna tem o botão de início', () {
    final faltando = <String>[];
    for (final f in telas) {
      final nome = f.uri.pathSegments.last;
      if (semBotaoDeInicio.containsKey(nome)) continue;
      if (!f.readAsStringSync().contains('BotaoInicio')) faltando.add(nome);
    }
    expect(
      faltando,
      isEmpty,
      reason:
          'Estas telas prendem o usuário: ${faltando.join(", ")}. '
          'Acrescente `const BotaoInicio()` no `actions` do AppBar, ou '
          'adicione a tela em `semBotaoDeInicio` com o motivo.',
    );
  });

  test('ninguém desligou a seta de voltar', () {
    // `automaticallyImplyLeading: false` e um `leading:` próprio no AppBar
    // são as duas formas de apagar a seta sem perceber. Já aconteceu neste
    // projeto: a logo como `leading` prendeu a tela de detalhe do Top (ver
    // `AppLogoAppBarLeading`).
    final suspeitas = <String>[];
    for (final f in telas) {
      final nome = f.uri.pathSegments.last;
      final codigo = f.readAsStringSync();
      if (codigo.contains('automaticallyImplyLeading: false')) {
        suspeitas.add('$nome (automaticallyImplyLeading: false)');
      }
      // `leading:` dentro de AppBar. A tela inicial é a exceção legítima —
      // ali a logo abre a gaveta e não há para onde voltar.
      if (nome != 'tops_screen.dart' &&
          RegExp(r'AppBar\((?:[^()]|\([^()]*\))*leading:').hasMatch(codigo)) {
        suspeitas.add('$nome (leading proprio no AppBar)');
      }
    }
    expect(
      suspeitas,
      isEmpty,
      reason:
          'Seta de voltar possivelmente apagada em: ${suspeitas.join(", ")}',
    );
  });

  group('BotaoInicio', () {
    testWidgets('volta para a primeira rota, de qualquer profundidade', (
      tester,
    ) async {
      final navegador = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navegador,
          home: const Scaffold(body: Text('inicio')),
        ),
      );

      // Empilha três telas, como Top -> participantes -> ficha.
      for (var i = 1; i <= 3; i++) {
        navegador.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(actions: const [BotaoInicio()]),
              body: Text('tela $i'),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }
      expect(find.text('tela 3'), findsOneWidget);

      await tester.tap(find.byType(BotaoInicio));
      await tester.pumpAndSettle();

      // Um toque, não três.
      expect(find.text('inicio'), findsOneWidget);
      expect(find.text('tela 1'), findsNothing);
    });

    testWidgets('na primeira rota, o botão não aparece', (tester) async {
      // Botão que não faz nada é pior que botão ausente: o usuário toca,
      // nada acontece, e ele passa a desconfiar do resto da tela.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(appBar: AppBar(actions: const [BotaoInicio()])),
        ),
      );
      expect(find.byIcon(Icons.home_outlined), findsNothing);
    });
  });
}
