// `tops.aceitar_fora_da_lista` — o interruptor que faz a senha do Top BASTAR.
//
// Achado na revisão de 24/11/2026: o campo foi ligado por SQL em 23/11 e
// **não tinha tela nenhuma**. Não havia como desligar pelo app. A mitigação
// escrita ("feche o cadastro depois que a equipe entrar") cobria só
// `autocadastro_liberado`; este ficava ligado para sempre, e gerar senha
// nova reabre o cadastro junto — então o Top voltava a aceitar qualquer
// número sem que ninguém pudesse impedir sem abrir o banco à mão.
//
// O que estes testes travam:
//
//   1. o DEFAULT do modelo é o restritivo (`false`), nos dois caminhos —
//      construtor e `fromMap` sem a coluna. É o inverso de
//      `autocadastroLiberado`, que tem default `true`, e a diferença é
//      deliberada: não trazer a coluna não pode AFIRMAR uma permissão;
//   2. a assimetria da tela: LIGAR é do master, DESLIGAR é de qualquer
//      admin — a mesma regra do trigger `tops_trava_senha`;
//   3. a tela DIZ quem muda, em vez de só travar o interruptor.
//
// A trava de verdade é o banco (`13_trava_do_top_sem_uid_nulo.sql`): a
// chave anônima está dentro do APK e alcança `tops` por PATCH. Aqui se
// trava o outro lado — não oferecer o que o servidor vai recusar.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:legendario_connect/models/top.dart';
import 'package:legendario_connect/screens/admin/admin_top_form_screen.dart';

void main() {
  Map<String, dynamic> linha({bool? fora}) => {
    'id': 'top-1',
    'name': 'TRACK 3 Colinas',
    'status': 'active',
    'aceitar_fora_da_lista': ?fora,
  };

  group('modelo', () {
    test('o default do construtor é o RESTRITIVO', () {
      final t = Top(id: 'x', name: 'y', status: TopStatus.active);
      expect(
        t.aceitarForaDaLista,
        isFalse,
        reason: 'ligado por omissão faria todo Top novo aceitar qualquer '
            'número; o padrão tem de ser a segunda tranca',
      );
    });

    test('fromMap SEM a coluna devolve false, não true', () {
      // Consulta antiga (ou cache de versão anterior) que não traga a
      // coluna NÃO pode afirmar que o Top aceita gente fora da lista.
      expect(Top.fromMap(linha()).aceitarForaDaLista, isFalse);
    });

    test('fromMap lê os dois valores quando a coluna vem', () {
      expect(Top.fromMap(linha(fora: true)).aceitarForaDaLista, isTrue);
      expect(Top.fromMap(linha(fora: false)).aceitarForaDaLista, isFalse);
    });

    test('é o oposto de autocadastroLiberado, e isso é de propósito', () {
      // Os dois ausentes: um abre (para não fechar Top que está rodando),
      // o outro fecha (para não afrouxar quem entra). Se alguém "unificar"
      // os defaults, este teste cai.
      final t = Top.fromMap(linha());
      expect(t.autocadastroLiberado, isTrue);
      expect(t.aceitarForaDaLista, isFalse);
    });
  });

  group('tela', () {
    Top topDe({required bool fora}) => Top(
      id: 'top-1',
      name: 'TRACK 3 Colinas',
      topNumber: '1922',
      location: 'Pista 3 Colinas',
      cidade: 'Franca',
      diretorResponsavel: 'Diretor do evento',
      status: TopStatus.active,
      autocadastroLiberado: true,
      aceitarForaDaLista: fora,
    );

    Future<void> montar(
      WidgetTester tester, {
      required bool master,
      required bool fora,
    }) async {
      // Superfície alta: o bloco fica no fim de uma lista longa e o
      // `ListView` não constrói o que não aparece.
      tester.view.physicalSize = const Size(1000, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: AdminTopFormScreen(
            top: topDe(fora: fora),
            isMasterAdmin: master,
          ),
        ),
      );
      await tester.pump();
    }

    // Por KEY, não por tipo nem por texto: a tela tem dois interruptores
    // e o subtítulo do outro ("...está na lista do Top consegue se
    // cadastrar") também casa com "está na lista".
    SwitchListTile oInterruptor(WidgetTester tester) =>
        tester.widget(find.byKey(const Key('aceitar_fora_da_lista')));

    testWidgets('o interruptor existe — antes não havia tela nenhuma', (
      tester,
    ) async {
      await montar(tester, master: true, fora: false);
      expect(find.text('Só quem está na lista do Top'), findsOneWidget);
    });

    testWidgets('admin comum NÃO liga (desligado, fica travado)', (
      tester,
    ) async {
      await montar(tester, master: false, fora: false);
      expect(
        oInterruptor(tester).onChanged,
        isNull,
        reason: 'ligar afrouxa quem entra no Top: é do master, e o banco '
            'recusa com 42501 — oferecer aqui é prometer o que não vai dar',
      );
    });

    testWidgets('admin comum DESLIGA (ligado, pode mexer)', (tester) async {
      await montar(tester, master: false, fora: true);
      expect(
        oInterruptor(tester).onChanged,
        isNotNull,
        reason: 'desligar é o lado seguro, igual a fechar o cadastro: '
            'qualquer admin pode',
      );
    });

    testWidgets('master liga e desliga', (tester) async {
      await montar(tester, master: true, fora: false);
      expect(oInterruptor(tester).onChanged, isNotNull);
      await montar(tester, master: true, fora: true);
      expect(oInterruptor(tester).onChanged, isNotNull);
    });

    testWidgets('a tela DIZ quem muda, em vez de só travar', (tester) async {
      await montar(tester, master: false, fora: false);
      expect(
        find.textContaining('administrador master'),
        findsWidgets,
        reason: 'porta fechada sem explicação parece defeito, e o admin '
            'tenta de novo',
      );
    });

    testWidgets('ligado, a tela avisa que a senha BASTA', (tester) async {
      await montar(tester, master: true, fora: true);
      expect(find.text('Aceita quem NÃO está na lista'), findsOneWidget);
      expect(find.textContaining('senha do Top BASTA'), findsOneWidget);
    });
  });
}
