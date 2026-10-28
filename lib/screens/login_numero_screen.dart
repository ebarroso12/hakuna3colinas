import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/acesso_service.dart';
import '../widgets/app_logo.dart';

/// Entrada pelo número do Legendários.
///
/// Dois passos: pedir acesso (uma vez) e entrar com o código que o
/// administrador entrega. Depois disso a sessão persiste — não é preciso
/// entrar de novo até deslogar.
class LoginNumeroScreen extends StatefulWidget {
  const LoginNumeroScreen({super.key});

  @override
  State<LoginNumeroScreen> createState() => _LoginNumeroScreenState();
}

class _LoginNumeroScreenState extends State<LoginNumeroScreen> {
  final _numero = TextEditingController();
  final _codigo = TextEditingController();
  final _nome = TextEditingController();
  final _top = TextEditingController();

  bool _pedindo = false;
  bool _entrando = false;
  String? _erro;
  String? _aviso;

  @override
  void dispose() {
    _numero.dispose();
    _codigo.dispose();
    _nome.dispose();
    _top.dispose();
    super.dispose();
  }

  Future<void> _pedirAcesso() async {
    final numero = _numero.text.trim();
    if (!AcessoService.numeroValido(numero)) {
      setState(() => _erro = 'Digite o número do Legendários (só números).');
      return;
    }
    // O Top é o que diz ao admin para qual evento liberar. Sem ele o
    // pedido chega sem contexto e o admin tem de perguntar por fora.
    final top = _top.text.trim();
    if (!RegExp(r'^[0-9]{1,8}$').hasMatch(top)) {
      setState(() => _erro = 'Digite o número do Top (só números).');
      return;
    }
    setState(() {
      _pedindo = true;
      _erro = null;
      _aviso = null;
    });
    try {
      final msg = await AcessoService.instance.solicitar(
        numero: numero,
        top: top,
        nome: _nome.text,
      );
      if (mounted) setState(() => _aviso = msg);
    } catch (e) {
      if (mounted) setState(() => _erro = 'Não foi possível pedir acesso: $e');
    } finally {
      if (mounted) setState(() => _pedindo = false);
    }
  }

  Future<void> _entrar() async {
    final numero = _numero.text.trim();
    final codigo = _codigo.text.trim();
    if (!AcessoService.numeroValido(numero)) {
      setState(() => _erro = 'Digite o número do Legendários.');
      return;
    }
    if (codigo.isEmpty) {
      setState(() => _erro = 'Digite o código que o administrador passou.');
      return;
    }
    setState(() {
      _entrando = true;
      _erro = null;
    });
    try {
      // Não navega: o AuthGate escuta authStateChanges e troca a tela.
      await AcessoService.instance.entrarComCodigo(
        numero: numero,
        codigo: codigo,
      );
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _erro =
            'Número ou código incorreto. Se o código for antigo, peça um novo '
            'ao administrador.',
      );
    } finally {
      if (mounted) setState(() => _entrando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Entrar com número')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: AppLogo(size: 110)),
              const SizedBox(height: 24),

              TextField(
                controller: _numero,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
                decoration: const InputDecoration(
                  labelText: 'NÚMERO DO LEGENDÁRIOS',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),

              TextField(
                controller: _codigo,
                textCapitalization: TextCapitalization.characters,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 6,
                ),
                decoration: const InputDecoration(
                  labelText: 'CÓDIGO DE ACESSO',
                  hintText: 'A1B2C3',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _entrar(),
              ),

              if (_erro != null) ...[
                const SizedBox(height: 12),
                Text(
                  _erro!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                  textAlign: TextAlign.center,
                ),
              ],
              if (_aviso != null) ...[
                const SizedBox(height: 12),
                Card(
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_aviso!, textAlign: TextAlign.center),
                  ),
                ),
              ],

              const SizedBox(height: 20),
              FilledButton(
                onPressed: _entrando ? null : _entrar,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: _entrando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('ENTRAR'),
              ),

              const SizedBox(height: 28),
              const Divider(),
              const SizedBox(height: 12),
              Text(
                'Primeira vez?',
                style: Theme.of(context).textTheme.titleSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Peça acesso com o seu número e o número do Top. Um '
                'administrador vai liberar e te passar o código.',
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
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
              TextField(
                controller: _nome,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Seu nome (ajuda o admin a te reconhecer)',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _pedindo ? null : _pedirAcesso,
                icon: _pedindo
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.how_to_reg_outlined),
                label: const Text('Pedir acesso'),
              ),
              const SizedBox(height: 20),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Entrar com e-mail e senha'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
