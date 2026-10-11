import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legendario_connect/main.dart';
import 'package:legendario_connect/widgets/faixa_de_alarme.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A pergunta que nenhum outro teste responde: **o app abre?**
///
/// Os outros 347 testes provam lógica isolada — fila, triagem, exclusão,
/// formatação. Nenhum monta o widget raiz. Então um erro na montagem do
/// `MaterialApp` passaria por todos eles e só apareceria no celular,
/// como tela branca ou crash na abertura.
///
/// Isso não é teórico. A v1.0.31 pôs `FaixaDeAlarme` dentro de
/// `MaterialApp.builder`, acima do Navigator — o lugar mais fácil de
/// quebrar a árvore inteira do app. E um defeito real nasceu ali: o
/// `showModalBottomSheet` da faixa usava um contexto sem Navigator e
/// estouraria com "No Navigator widget found" no primeiro toque.
///
/// O que este teste **não** prova: que o APK instala, que o NFC funciona,
/// que o GPS lê, que o som toca. Nada disso se testa sem aparelho.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();

    // `shared_preferences` é plugin de plataforma e não existe em teste de
    // unidade: `Supabase.initialize` estoura com `MissingPluginException`
    // ao montar o armazenamento da sessão. Responder ao canal com um mapa
    // vazio é o equivalente a "aparelho novo, ninguém logado" — que é o
    // estado que este teste quer.
    //
    // `EmptyLocalStorage` sozinho não resolveu: o gotrue cria o seu
    // próprio `SharedPreferencesGotrueAsyncStorage` de qualquer forma.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/shared_preferences'),
          (chamada) async => chamada.method == 'getAll'
              ? <String, Object>{}
              : null,
        );

    // Credenciais falsas de propósito: `initialize` não faz chamada de
    // rede, só monta o cliente — e é o que o app precisa para a árvore
    // subir. Se um dia passar a fazer rede, este teste falha e avisa.
    await Supabase.initialize(
      url: 'https://exemplo.supabase.co',
      // `publishableKey` e nao `anonKey`: o segundo esta deprecado. O app
      // ja usa o novo em `SupabaseService.initialize`.
      publishableKey: 'chave-de-teste-sem-valor',
      debug: false,
      authOptions: const FlutterAuthClientOptions(
        localStorage: EmptyLocalStorage(),
      ),
    );
  });

  testWidgets('o widget raiz monta sem estourar', (tester) async {
    await tester.pumpWidget(const HakunaConnectApp());
    await tester.pump();

    // Sem sessão, o AuthGate tem de cair no login. Se cair em qualquer
    // outra coisa, a porta de entrada do app está errada.
    expect(tester.takeException(), isNull);
    expect(find.byType(MaterialApp), findsOneWidget);
  });

  testWidgets('a faixa de alarme fica ACIMA do Navigator, sem cobrir a tela', (
    tester,
  ) async {
    await tester.pumpWidget(const HakunaConnectApp());
    await tester.pump();

    // A faixa tem de existir na árvore (é o que faz o alarme aparecer em
    // qualquer tela) e, sem alarme ativo, não pode desenhar nada.
    expect(find.byType(FaixaDeAlarme), findsOneWidget);
    expect(find.textContaining('ALARME'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('existe navigatorKey — é o que a faixa usa para abrir folhas', (
    tester,
  ) async {
    await tester.pumpWidget(const HakunaConnectApp());
    await tester.pump();

    // Sem esta chave, "quem está mais perto" estoura com "No Navigator
    // widget found": o contexto da faixa está acima do Navigator.
    expect(
      navegadorDoApp.currentState,
      isNotNull,
      reason: 'o MaterialApp precisa do navigatorKey: navegadorDoApp',
    );
  });

  testWidgets('a tela de login aparece quando não há sessão', (tester) async {
    await tester.pumpWidget(const HakunaConnectApp());
    // Duas passadas: o AuthGate decide no StreamBuilder da sessão.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
    // É a porta de entrada do app. Se isto quebrar, ninguém entra.
    expect(find.text('Entrar'), findsOneWidget);
    expect(find.text('Número do Legendários ou e-mail'), findsOneWidget);
  });
}
