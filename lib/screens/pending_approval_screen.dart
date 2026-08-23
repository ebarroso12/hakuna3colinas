import 'package:flutter/material.dart';

import '../services/supabase_service.dart';
import '../widgets/app_logo.dart';

/// Mostrada pro usuário logado cujo cadastro ainda não foi aprovado pelo
/// admin master. Ninguém usa o app sem essa liberação.
class PendingApprovalScreen extends StatefulWidget {
  const PendingApprovalScreen({super.key, required this.onRecheck});

  /// Chamado ao tocar em "verificar de novo" — quem decide se o app deve
  /// trocar de tela é o AuthGate, não esta tela.
  final Future<bool> Function() onRecheck;

  @override
  State<PendingApprovalScreen> createState() => _PendingApprovalScreenState();
}

class _PendingApprovalScreenState extends State<PendingApprovalScreen> {
  bool _checking = false;

  Future<void> _checkAgain() async {
    setState(() => _checking = true);
    try {
      final approved = await widget.onRecheck();
      if (!mounted) return;
      if (!approved) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ainda aguardando aprovação.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível checar: $e')),
      );
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const AppLogo(size: 120),
            const SizedBox(height: 24),
            const Icon(Icons.hourglass_top, size: 48),
            const SizedBox(height: 16),
            const Text(
              'Cadastro aguardando aprovação',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Um administrador precisa liberar seu acesso antes que você possa usar o app.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _checking ? null : _checkAgain,
              child: _checking
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Já fui aprovado? Verificar de novo'),
            ),
            TextButton(
              onPressed: () => SupabaseService.instance.signOut(),
              child: const Text('Sair'),
            ),
          ],
        ),
      ),
    );
  }
}
