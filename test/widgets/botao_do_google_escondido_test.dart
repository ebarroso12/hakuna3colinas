// O botão "Entrar com Google" não pode aparecer enquanto o provedor estiver
// desligado no Supabase.
//
// Decidido com o dono em 23/11/2026, a 3 dias do Top. O projeto Supabase foi
// reconstruído do zero e a configuração do Google ficou no antigo, que foi
// apagado:
//
//     external_google_enabled .... false
//     client_id / secret ......... ausentes
//
// E o lado do Google estava CERTO — client ID dentro do APK, impressões da
// chave registradas no Firebase. Por isso o botão não falhava logo: o
// seletor de conta do Google abria, a pessoa escolhia a conta, e só então
// vinha a recusa do servidor. Pior que não aparecer, porque parece que o app
// quebrou no meio do caminho.
//
// O motivo mais forte, porém, não é o erro na tela: conta criada pelo Google
// nasce **sem o número do Legendários** — `handle_new_user` põe o uuid no
// lugar. Quem entrasse por ali nunca mais entraria pelo número e ficaria
// fora do Top, exigindo conserto manual do admin, um por um. Com 216
// pessoas, não escala.
//
// Este teste existe para o botão não voltar sozinho — num refactor da tela,
// por exemplo. Quando o Google for configurado no Supabase, o certo é
// trocar `googleProvedorLigado` para `true` **e** ajustar este teste no
// mesmo commit: as duas pontas ou nenhuma.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:legendario_connect/services/supabase_service.dart';

void main() {
  test('o provedor Google está desligado, e é intencional', () {
    expect(
      SupabaseService.googleProvedorLigado,
      isFalse,
      reason: 'se você ligou o Google no painel do Supabase, troque aqui '
          'também e no mesmo commit — o app não tem como descobrir sozinho',
    );
  });

  test('com o provedor desligado, o botão não aparece em plataforma nenhuma', () {
    // `googleDisponivel` é o único portão que a tela consulta. Com o
    // provedor desligado ele tem de ser falso, inclusive no web e no
    // Android, onde antes era sempre verdadeiro.
    expect(SupabaseService.googleDisponivel, isFalse);
  });

  testWidgets('a tela de entrada não mostra "Entrar com Google"', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // A tela de login não toca a rede ao montar — o Supabase só é chamado
    // quando se aperta um botão. Por isso ela pode ser montada crua.
    await tester.pumpWidget(
      const MaterialApp(home: _TelaDeEntradaDeMentira()),
    );
    await tester.pump();

    expect(find.text('Entrar com Google'), findsNothing);
  });
}

/// Réplica mínima do bloco condicional da tela de entrada.
///
/// Montar a `LoginScreen` de verdade aqui exigiria o Supabase inicializado
/// (o `initState` dela não, mas o botão "Entrar" sim), e o que precisa ser
/// travado é a CONDIÇÃO, não o resto da tela. A condição é a mesma
/// expressão: `if (SupabaseService.googleDisponivel)`. Se alguém trocar o
/// portão na tela por outra coisa, o primeiro teste deste arquivo continua
/// pegando — é ele que garante o valor.
class _TelaDeEntradaDeMentira extends StatelessWidget {
  const _TelaDeEntradaDeMentira();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        const Text('Entrar'),
        if (SupabaseService.googleDisponivel)
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.g_mobiledata),
            label: const Text('Entrar com Google'),
          ),
      ],
    ),
  );
}
