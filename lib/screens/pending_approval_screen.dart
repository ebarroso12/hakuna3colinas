import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/acesso_service.dart';
import '../services/supabase_service.dart';
import '../widgets/app_logo.dart';

/// Mostrada pro usuário logado cujo cadastro ainda não foi aprovado pelo
/// admin master. Ninguém usa o app sem essa liberação.
///
/// Quem cai aqui entrou pelo Google ou por e-mail, e esses caminhos não
/// pedem número nem Top. Por isso esta tela pede os dois e manda ao admin:
/// sem isso a pessoa esperava calada numa lista que o admin não abria, e
/// a conta nascia sem o número do Legendários (o caso do Pedro, 28/10).
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

  final _numero = TextEditingController();
  final _top = TextEditingController();
  bool _enviando = false;
  String? _erro;
  String? _enviado;

  @override
  void dispose() {
    _numero.dispose();
    _top.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    final numero = _numero.text.trim();
    final top = _top.text.trim();
    if (!AcessoService.numeroValido(numero)) {
      setState(() => _erro = 'Digite o número do Legendários (só números).');
      return;
    }
    if (!RegExp(r'^[0-9]{1,8}$').hasMatch(top)) {
      setState(() => _erro = 'Digite o número do Top (só números).');
      return;
    }
    setState(() {
      _enviando = true;
      _erro = null;
    });
    try {
      // A sessão vai junto: o servidor liga o pedido a ESTA conta, e o
      // admin aprova a conta que existe em vez de criar outra.
      await AcessoService.instance.solicitar(numero: numero, top: top);
      if (mounted) {
        setState(
          () => _enviado =
              'Enviado ao administrador. Quando ele liberar, toque em '
              '"Verificar de novo".',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _erro =
              'Não foi possível enviar. Confira a internet e tente de novo.',
        );
      }
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Não foi possível checar: $e')));
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AppLogo(size: 96),
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
                const SizedBox(height: 20),
                const Text(
                  'Mande seu número e o número do Top para o administrador:',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _numero,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Seu número do Legendários',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _top,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: 'Número do Top',
                    helperText: 'Ex.: 1782',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _enviando ? null : _enviar,
                  icon: _enviando
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_outlined),
                  label: const Text('Enviar ao administrador'),
                ),
                if (_erro != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _erro!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                if (_enviado != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _enviado!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _checking ? null : _checkAgain,
                  child: _checking
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Já fui aprovado? Verificar de novo'),
                ),
                TextButton(
                  onPressed: () => SupabaseService.instance.signOut(),
                  child: const Text('Sair'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
