import 'package:flutter/material.dart';

import '../services/supabase_service.dart';
import '../widgets/app_logo.dart';

/// Login sem senha: envia um código de 6 dígitos pro e-mail, o usuário
/// digita de volta. Serve tanto pra quem esqueceu a senha quanto pra
/// primeiro acesso — não depende de nenhum link de e-mail funcionando.
class LoginWithCodeScreen extends StatefulWidget {
  const LoginWithCodeScreen({super.key});

  @override
  State<LoginWithCodeScreen> createState() => _LoginWithCodeScreenState();
}

class _LoginWithCodeScreenState extends State<LoginWithCodeScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  bool _codeSent = false;
  bool _loading = false;
  String? _error;

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Informe o e-mail.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await SupabaseService.instance.sendLoginCode(email);
      if (!mounted) return;
      setState(() => _codeSent = true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Informe o código recebido por e-mail.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Não navega manualmente: o AuthGate reage à sessão nova sozinho.
      await SupabaseService.instance.verifyLoginCode(
        email: _emailController.text.trim(),
        code: code,
      );
    } catch (e) {
      if (mounted) setState(() => _error = friendlyAuthError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Entrar com código')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: AppLogo(size: 100)),
            const SizedBox(height: 24),
            TextField(
              controller: _emailController,
              enabled: !_codeSent,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'E-mail'),
            ),
            if (_codeSent) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _codeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Código recebido por e-mail',
                  helperText: 'Confira também a caixa de spam.',
                ),
              ),
            ],
            const SizedBox(height: 24),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            FilledButton(
              onPressed: _loading ? null : (_codeSent ? _verifyCode : _sendCode),
              child: _loading
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_codeSent ? 'Confirmar código' : 'Enviar código'),
            ),
            if (_codeSent)
              TextButton(
                onPressed: _loading ? null : () => setState(() => _codeSent = false),
                child: const Text('Trocar e-mail / reenviar'),
              ),
          ],
        ),
      ),
    );
  }
}
