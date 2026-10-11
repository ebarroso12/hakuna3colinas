import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legendario_connect/models/team.dart';
import 'package:legendario_connect/models/top.dart';
import 'package:legendario_connect/screens/team_chats_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// O app é dos **9 TIMES** e a tela de chats não mostrava time nenhum.
///
/// `TeamChatsScreen` listava só as equipes em que o usuário já era membro
/// liberado. Como `top_team_members` nasce vazia, esse era o estado de
/// todo mundo num Top recém-montado — inclusive do admin, que a RLS
/// libera em todas as 9 (`is_admin() or is_team_member(...)`). O dono do
/// projeto abriu o app em 11/10/2026 e não achou as 9 equipes.
///
/// Este teste monta a tela no **pior caso possível**: ninguém logado,
/// portanto zero vínculos e perfil que nem carrega. É o caso em que a
/// versão antiga mostrava um único cartão dizendo "Você ainda não está em
/// nenhuma equipe". As 9 têm de aparecer de todo jeito, cada uma com o
/// motivo de estar fechada.
///
/// O que ele **não** prova: que a RLS devolve as mensagens, que o admin
/// consegue escrever no chat de equipe alheia, nem que `team_key` tem os
/// 9 valores no Postgres de produção — a 9ª (`hakunas`) entrou por comando
/// rodado direto em produção, e nada no repositório a recria.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    // Mesmo motivo de `o_app_abre_test.dart`: `shared_preferences` é
    // plugin de plataforma e `Supabase.initialize` estoura sem ele.
    // Mapa vazio = aparelho novo, ninguém logado.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/shared_preferences'),
          (chamada) async =>
              chamada.method == 'getAll' ? <String, Object>{} : null,
        );

    await Supabase.initialize(
      url: 'https://exemplo.supabase.co',
      publishableKey: 'chave-de-teste-sem-valor',
      debug: false,
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
      ),
    );
  });

  Top topDeTeste() => Top(
    id: '00000000-0000-0000-0000-000000000001',
    name: 'Top de teste',
    status: TopStatus.active,
    startsAt: DateTime(2026, 10, 11),
  );

  /// Monta a tela numa superfície alta de propósito.
  ///
  /// O `ListView` constrói só o que está visível, então num 360×640 as
  /// últimas equipes não existem na árvore e `find.text` não as acha —
  /// a primeira versão deste teste falhou em "Mídia" por isso, e não por
  /// defeito da tela. Com 2400 dp de altura as 9 ficam montadas ao mesmo
  /// tempo, que é o que se quer verificar aqui. **Quem mede se as ações
  /// da AppBar caibem num celular de verdade é
  /// `appbar_cabe_no_celular_test.dart`** — não este.
  ///
  /// `setSurfaceSize` tem de ser chamado DENTRO do teste (ele assere
  /// `inTest`), daí ser função e não `setUp`.
  Future<void> montar(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(home: TeamChatsScreen(top: topDeTeste())),
    );
    // Sem usuário logado, `fetchMyTeams` devolve lista vazia na hora e
    // `fetchMyProfile` falha — os dois sem rede.
    await tester.pumpAndSettle();
  }

  testWidgets('as 9 equipes aparecem mesmo sem vínculo nenhum', (tester) async {
    await montar(tester);

    expect(TeamKeyUi.equipes.length, 9, reason: 'são 9 equipes, não 8');

    for (final equipe in TeamKeyUi.equipes) {
      expect(
        find.text(equipe.label),
        findsOneWidget,
        reason: '${equipe.label} tem de aparecer na lista, aberta ou fechada',
      );
    }

    // O canal geral continua acessível e separado das 9: ele não é equipe.
    expect(find.text('Chat geral'), findsOneWidget);
    expect(find.text(TeamKey.geral.label), findsNothing);
  });

  testWidgets('equipe fechada DIZ o motivo, em vez de só não aparecer', (
    tester,
  ) async {
    await montar(tester);

    // Sem vínculo e sem perfil de admin, as 9 caem no mesmo estado. O
    // texto é o que manda o usuário pedir a coisa certa ao admin, em vez
    // de achar que o app está quebrado.
    expect(find.text('Você não está nesta equipe'), findsNWidgets(9));

    // E o cabeçalho não pode mentir sobre quantas são.
    expect(find.textContaining('As 9 equipes'), findsOneWidget);
  });

  testWidgets('tocar numa equipe fechada explica, não abre chat vazio', (
    tester,
  ) async {
    await montar(tester);

    await tester.tap(find.text('Segurança'));
    await tester.pump();

    // Continua na mesma tela — não navegou para um chat que a RLS
    // esvaziaria — e explica nomeando quem resolve.
    expect(find.text('Chats e anotações'), findsOneWidget);
    expect(
      find.textContaining('O admin do Top ou o coordenador'),
      findsOneWidget,
    );
  });
}
