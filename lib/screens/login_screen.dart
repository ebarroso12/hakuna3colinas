import 'package:flutter/material.dart';

import '../services/acesso_service.dart';
import '../services/supabase_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/password_field.dart';
import 'primeiro_acesso_screen.dart';
import 'login_with_code_screen.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  /// Aceita numero do Legendarios OU e-mail. Ver
  /// `AcessoService.identificadorParaEmail`.
  final _identificador = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _loadingGoogle = false;
  String? _error;

  Future<void> _signIn() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Não navega manualmente: o AuthGate, na raiz do app, escuta
      // authStateChanges e troca para a TopsScreen sozinho.
      // Um campo so: numero vira `numero@legendarios.app`, e-mail passa
      // direto. O Legendario entra pelo numero dele; admin e equipe, pelo
      // e-mail que o admin liberou.
      await SupabaseService.instance.signIn(
        email: AcessoService.identificadorParaEmail(_identificador.text),
        password: _passwordController.text,
      );
    } catch (e) {
      setState(() => _error = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() {
      _loadingGoogle = true;
      _error = null;
    });
    try {
      await SupabaseService.instance.signInWithGoogle();
    } catch (e) {
      if (mounted) {
        // `signInWithGoogle` já traduz os erros do plugin em texto útil
        // (ver SupabaseService._erroDoGoogle). Prefixar com "Não foi
        // possível entrar com Google:" repetia a informação e empurrava a
        // instrução — "use número e senha" — para fora da tela.
        setState(
          () => _error = e is StateError ? e.message : 'Erro no Google: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _loadingGoogle = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Legendario Connect')),
      // Rola quando não cabe (tela baixa, teclado aberto, mensagem de erro
      // longa) em vez de estourar o layout; continua centralizado quando cabe.
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: AppLogo(size: 140)),
              const SizedBox(height: 24),
              TextField(
                controller: _identificador,
                // `emailAddress` e nao `number`: o teclado precisa ter
                // arroba para quem entra por e-mail, e digito para quem
                // entra por numero. Um teclado numerico esconderia o @.
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Número do Legendários ou e-mail',
                  helperText: 'Legendário entra com o número. '
                      'Admin e equipe, com o e-mail.',
                ),
              ),
              const SizedBox(height: 12),
              PasswordField(
                controller: _passwordController,
                labelText: 'Senha',
              ),
              const SizedBox(height: 24),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              FilledButton(
                onPressed: _loading ? null : _signIn,
                child: _loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Entrar'),
              ),
              const SizedBox(height: 12),
              const Row(
                children: [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('ou'),
                  ),
                  Expanded(child: Divider()),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _loadingGoogle ? null : _signInWithGoogle,
                icon: _loadingGoogle
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.g_mobiledata, size: 28),
                label: const Text('Entrar com Google'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute<void>(builder: (_) => const SignupScreen())),
                child: const Text('Não tem conta? Cadastre-se'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const LoginWithCodeScreen(),
                  ),
                ),
                child: const Text('Esqueci minha senha / entrar com código'),
              ),
              // O campo la de cima e para quem JA TEM conta. Este botao e
              // outra coisa: quem ainda nao tem se cadastra com o numero e
              // a senha que o admin anunciou para o Top. Rotulo separado
              // para os dois nao competirem na mesma tela.
              FilledButton.tonalIcon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const PrimeiroAcessoScreen(),
                  ),
                ),
                icon: const Icon(Icons.badge_outlined),
                label: const Text('Primeiro acesso'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
