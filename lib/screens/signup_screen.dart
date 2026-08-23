import 'package:flutter/material.dart';

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
        // Confirmação de e-mail está ligada no projeto: sem sessão ainda.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cadastro feito! Confirme seu e-mail antes de entrar.')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() => _error = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
              decoration: const InputDecoration(labelText: 'Número do Legendários'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _weightController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
