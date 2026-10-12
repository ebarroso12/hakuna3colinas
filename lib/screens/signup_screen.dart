import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/acesso_service.dart';
import '../services/supabase_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/password_field.dart';

/// Cadastro de um novo participante. Todo mundo entra como Senderista —
/// um admin promove pra Hakuna depois (não dá pra se autodeclarar Hakuna
/// no cadastro, isso teria que ser validado por alguém responsável).
class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _nameController = TextEditingController();
  final _legendariosNumberController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _weightController = TextEditingController();
  bool _loading = false;
  String? _error;

  Future<void> _signUp() async {
    final name = _nameController.text.trim();
    final number = _legendariosNumberController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final weightText = _weightController.text.trim().replaceAll(',', '.');

    if (name.isEmpty || number.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Preencha todos os campos.');
      return;
    }

    // Mesma validação de `AcessoService.numeroValido` e da Edge Function
    // `acesso` (^[0-9]{1,12}$). Antes a tela aceitava qualquer coisa não
    // vazia: dava para se cadastrar com "12" ou "abc", e aí o admin nunca
    // conseguiria liberar o acesso dessa pessoa — a Edge Function recusaria
    // o número com "numero invalido" e ninguém saberia por quê.
    if (!AcessoService.numeroValido(number)) {
      setState(
        () => _error =
            'Número do Legendários inválido. '
            'Use só dígitos, até 12 (ex.: 203460).',
      );
      return;
    }
    final weightKg = weightText.isEmpty ? null : double.tryParse(weightText);
    if (weightText.isNotEmpty && weightKg == null) {
      setState(() => _error = 'Peso inválido.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Não navega manualmente: se o cadastro já vier com sessão ativa
      // (confirmação de e-mail desligada), o AuthGate troca de tela sozinho.
      await SupabaseService.instance.signUp(
        email: email,
        password: password,
        fullName: name,
        legendariosNumber: number,
        weightKg: weightKg,
      );
      if (!mounted) return;
      if (SupabaseService.instance.currentUser == null) {
        // Confirmação de e-mail está ligada no projeto: a conta existe, mas
        // sem sessão — e, pior, SEM NINGUÉM SABENDO.
        //
        // Foi assim que o Legendário 219175 ficou preso em 12/10/2026:
        // conta criada, e-mail nunca confirmado, nada na tela de pedidos do
        // admin, e nenhum jeito de pedir ajuda de dentro do app. Login
        // recusado mesmo com a senha certa, e "esqueci minha senha"
        // respondendo "confirme seu e-mail". Um beco sem saída silencioso,
        // e o admin não tinha como nem saber que a pessoa existia.
        //
        // Registrar o pedido aqui é o que torna a pessoa VISÍVEL: mesmo que
        // ela nunca abra o e-mail, aparece na lista do admin e ele libera
        // por código. O caminho de e-mail deixa de ser o único.
        var avisado = false;
        try {
          await AcessoService.instance.solicitar(numero: number, nome: name);
          avisado = true;
        } catch (_) {
          // Sem rede, ou função fora do ar. O cadastro em si deu certo e
          // não se desfaz por causa do aviso — mas a tela diz a verdade,
          // que o administrador PODE não ter sido avisado, em vez de
          // afirmar que foi.
        }
        if (!mounted) return;
        await _avisoDeConfirmacao(email, avisado: avisado);
        if (!mounted) return;
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _error = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Aviso que FICA na tela, em vez de SnackBar que some em 4 segundos.
  ///
  /// Quem acabou de se cadastrar precisa sair daqui sabendo três coisas: a
  /// conta existe, falta confirmar o e-mail, e há um caminho se o e-mail
  /// não chegar. O SnackBar sumia antes de a pessoa terminar de ler — e em
  /// campo, no sol e com uma mão só, sumia mesmo. Depois dele a tela ainda
  /// fazia `pop()`, então não restava nem rastro do que tinha acontecido.
  Future<void> _avisoDeConfirmacao(String email, {required bool avisado}) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Falta confirmar seu e-mail'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Sua conta foi criada. Enviamos um link para:'),
              const SizedBox(height: 8),
              Text(
                email,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'Abra esse e-mail e toque no link. Só depois disso dá para '
                'entrar — até lá o app recusa a senha, mesmo estando certa.',
              ),
              const SizedBox(height: 16),
              Text(
                avisado
                    ? 'Se o e-mail não chegar, fale com o administrador do '
                          'Top: seu pedido já apareceu na lista dele, e ele '
                          'consegue liberar seu acesso sem o e-mail.'
                    : 'Não conseguimos avisar o administrador agora — pode '
                          'ser falta de internet. Se o e-mail não chegar, '
                          'procure-o e peça o código de acesso.',
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _legendariosNumberController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Criar conta')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: AppLogo(size: 100)),
            const SizedBox(height: 24),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nome completo'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _legendariosNumberController,
              keyboardType: TextInputType.number,
              // `keyboardType` sozinho não barra letra: teclado de terceiro,
              // colar e teclado físico passam por cima. O formatter barra.
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Número do Legendários',
                helperText: 'Só dígitos. É ele que identifica você no app.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _weightController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Peso (kg) — opcional',
                helperText: 'Usado só para estimar o gasto calórico na trilha.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'E-mail'),
            ),
            const SizedBox(height: 12),
            PasswordField(controller: _passwordController, labelText: 'Senha'),
            const SizedBox(height: 24),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            FilledButton(
              onPressed: _loading ? null : _signUp,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Cadastrar'),
            ),
          ],
        ),
      ),
    );
  }
}
