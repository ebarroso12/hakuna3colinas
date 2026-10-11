import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/acesso_service.dart';
import '../widgets/app_logo.dart';
import 'cadastro_legendario_screen.dart';
import 'login_numero_screen.dart';

/// PRIMEIRO ACESSO — número do Legendários + senha do Top.
///
/// Passo 1 de 2. A senha do Top é a mesma para todo mundo do evento: o
/// admin gera uma e anuncia ao grupo, em vez de liberar pessoa por pessoa.
/// No dia do Top isso é a diferença entre 20 pessoas instalando sozinhas e
/// 20 pessoas na fila do celular do admin.
///
/// Ela libera o **cadastro**, não a entrada. Quem termina este fluxo sai
/// com uma senha própria e nunca mais usa a do Top — ver
/// `CadastroLegendarioScreen`.
class PrimeiroAcessoScreen extends StatefulWidget {
  const PrimeiroAcessoScreen({super.key});

  @override
  State<PrimeiroAcessoScreen> createState() => _PrimeiroAcessoScreenState();
}

class _PrimeiroAcessoScreenState extends State<PrimeiroAcessoScreen> {
  final _numero = TextEditingController();
  final _senhaDoTop = TextEditingController();
  bool _verificando = false;
  String? _erro;

  @override
  void dispose() {
    _numero.dispose();
    _senhaDoTop.dispose();
    super.dispose();
  }

  Future<void> _continuar() async {
    final numero = _numero.text.trim();
    final senha = _senhaDoTop.text.trim();

    if (!AcessoService.numeroValido(numero)) {
      setState(() => _erro = 'Digite seu número do Legendários (só dígitos).');
      return;
    }
    if (senha.isEmpty) {
      setState(() => _erro = 'Digite a senha que o administrador passou.');
      return;
    }

    setState(() {
      _verificando = true;
      _erro = null;
    });
    try {
      final convite = await AcessoService.instance.validarConvite(
        numero: numero,
        senhaDoTop: senha,
      );
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CadastroLegendarioScreen(
            numero: numero,
            senhaDoTop: senha,
            convite: convite,
          ),
        ),
      );
    } on AcessoRecusado catch (e) {
      // A mensagem vem pronta do servidor — ver AcessoService._invocar.
      if (mounted) setState(() => _erro = e.mensagem);
    } catch (e) {
      if (mounted) {
        setState(() => _erro = 'Não foi possível verificar agora: $e');
      }
    } finally {
      if (mounted) setState(() => _verificando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Primeiro acesso')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: AppLogo(size: 110)),
              const SizedBox(height: 20),
              Text(
                'Passo 1 de 2',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              const Text(
                'Use seu número do Legendários e a senha que o administrador '
                'passou para este Top.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              TextField(
                controller: _numero,
                keyboardType: TextInputType.number,
                // `keyboardType` sozinho não barra letra em teclado de
                // terceiro nem ao colar. O formatter barra.
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Seu número do Legendários',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _senhaDoTop,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _continuar(),
                // Sem `obscureText`: a senha é anunciada ao grupo inteiro,
                // não é segredo pessoal. Esconder só faria a pessoa errar
                // ao digitar um código ditado em voz alta.
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Senha do Top',
                  helperText: 'A mesma para todos deste evento.',
                  border: OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 20),
              if (_erro != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _erro!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              FilledButton(
                onPressed: _verificando ? null : _continuar,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: _verificando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('CONTINUAR'),
              ),

              const SizedBox(height: 20),
              const Divider(),
              const SizedBox(height: 8),
              Text(
                'Já tem conta? Volte e entre com seu número e sua senha.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Voltar para a entrada'),
              ),
              // Caminho alternativo, um a um: para quem nao recebeu a
              // senha do grupo ou nao esta na lista daquele Top. Fica
              // discreto de proposito - o fluxo normal e o de cima.
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const LoginNumeroScreen(),
                  ),
                ),
                child: const Text(
                  'Não tem a senha do Top? Pedir código ao administrador',
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
