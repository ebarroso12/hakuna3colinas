import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/acesso_service.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/botao_inicio.dart';

/// Pedidos de acesso ao app.
///
/// O admin libera e **entrega o código à pessoa** — por WhatsApp,
/// pessoalmente, como for. Não há envio automático: decisão de produto
/// para manter custo zero e deixar o admin no controle de quem entra.
///
/// Liberar **aprova a conta** (vale para todos os Tops) e coloca a pessoa
/// no Top que ela informou. Quem pediu já logado — entrou pelo Google ou
/// por e-mail — não recebe código: já entra do jeito dela.
class AdminAcessosScreen extends StatefulWidget {
  const AdminAcessosScreen({super.key});

  @override
  State<AdminAcessosScreen> createState() => _AdminAcessosScreenState();
}

class _AdminAcessosScreenState extends State<AdminAcessosScreen> {
  late Future<List<PedidoAcesso>> _pedidos;
  bool _apenasPendentes = true;

  @override
  void initState() {
    super.initState();
    _recarregar();
  }

  void _recarregar() {
    setState(() {
      _pedidos = AcessoService.instance.pedidos(
        apenasPendentes: _apenasPendentes,
      );
    });
  }

  Future<void> _liberar(PedidoAcesso pedido, {bool confirmado = false}) async {
    try {
      final r = await AcessoService.instance.liberar(
        pedido.numero,
        confirmarTrocaDeSenha: confirmado,
      );
      if (!mounted) return;
      final codigo = r.codigo;
      if (codigo != null) {
        await _mostrarCodigo(pedido, codigo, r);
      } else {
        await _mostrarAprovado(pedido, r);
      }
      _recarregar();
    } on ContaComEmailProprio catch (e) {
      // Não é erro: o servidor está perguntando. A tela pergunta de volta,
      // com a consequência escrita, e só então repete a chamada.
      if (!mounted) return;
      final seguir = await _confirmarTrocaDeSenha(pedido, e.email);
      if (seguir == true && mounted) {
        await _liberar(pedido, confirmado: true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Não foi possível liberar: $e')));
    }
  }

  /// Pergunta antes de substituir a senha de uma conta que entra por e-mail.
  ///
  /// O texto É a correção, não enfeite: quem lê precisa saber que a senha
  /// antiga para de funcionar e que existe um caminho melhor quando a
  /// pessoa apenas esqueceu a senha. Sem isso o admin aperta "sim" sem
  /// saber o que está trocando.
  Future<bool?> _confirmarTrocaDeSenha(PedidoAcesso pedido, String email) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Essa pessoa já tem conta'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'O Legendário #${pedido.numero} entra hoje com e-mail '
                'próprio:',
              ),
              const SizedBox(height: 8),
              Text(email, style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              const Text(
                'Gerar um código SUBSTITUI a senha dessa conta. A senha '
                'que ela usa hoje deixa de funcionar, e ela passa a entrar '
                'só com o código que você entregar.',
              ),
              const SizedBox(height: 16),
              const Text(
                'Se ela apenas esqueceu a senha, o caminho melhor é '
                '"Esqueci minha senha" na tela de entrada — assim a conta '
                'continua dela e você não precisa entregar nada.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Substituir a senha'),
          ),
        ],
      ),
    );
  }

  /// Mostra o código uma única vez.
  ///
  /// O banco guarda só o hash — se o admin fechar sem anotar, precisa
  /// gerar outro. É de propósito: código legível guardado para sempre é
  /// senha em texto claro.
  /// Linha que diz em qual Top a pessoa entrou — ou por que não entrou.
  ///
  /// O pedido pode chegar com Top que não existe ("Top 1922"). A conta é
  /// aprovada do mesmo jeito; o que falta o admin precisa saber, senão
  /// acha que a pessoa está num Top em que ela não está.
  Widget _linhaDoTop(PedidoAcesso pedido, Liberacao r) {
    final String texto;
    if (r.topNome != null && r.aviso == null) {
      texto = 'Colocado no Top ${pedido.topNumero ?? ''} · ${r.topNome}.';
    } else if (r.topNome != null) {
      texto =
          'Aprovado, mas não deu para completar o Top ${r.topNome}: '
          '${r.aviso}. Confira em Participantes do Top.';
    } else if (pedido.topNumero != null) {
      texto =
          'O Top ${pedido.topNumero} não existe no app. A conta foi '
          'aprovada e vê os Tops em andamento.';
    } else {
      texto =
          'Sem Top no pedido. A conta foi aprovada e vê os Tops em '
          'andamento.';
    }
    return Text(texto, textAlign: TextAlign.center);
  }

  /// Pedido de quem já tinha conta: não há código para entregar.
  Future<void> _mostrarAprovado(PedidoAcesso pedido, Liberacao r) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Conta aprovada'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Legendário ${pedido.numero}'),
            if (pedido.nome != null) Text(pedido.nome!),
            const SizedBox(height: 16),
            _linhaDoTop(pedido, r),
            const SizedBox(height: 16),
            const Text(
              'Não há código para entregar: a pessoa já tinha conta e '
              'entra do jeito que entrou (Google ou e-mail). Avise para '
              'ela tocar em "Verificar de novo".',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _mostrarCodigo(PedidoAcesso pedido, String codigo, Liberacao r) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Código gerado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Legendário ${pedido.numero}'),
            if (pedido.nome != null) Text(pedido.nome!),
            const SizedBox(height: 16),
            SelectableText(
              codigo,
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                letterSpacing: 8,
              ),
            ),
            const SizedBox(height: 16),
            _linhaDoTop(pedido, r),
            const SizedBox(height: 16),
            const Text(
              'Entregue este código à pessoa. Ele aparece só agora — '
              'se fechar sem anotar, será preciso gerar outro.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: codigo));
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(
                  dialogContext,
                ).showSnackBar(const SnackBar(content: Text('Código copiado')));
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copiar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Anotei'),
          ),
        ],
      ),
    );
  }

  Future<void> _negar(PedidoAcesso pedido) async {
    final confirma = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Negar acesso ao ${pedido.numero}?'),
        content: const Text('A pessoa não receberá código.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Negar'),
          ),
        ],
      ),
    );
    if (confirma ?? false) {
      await AcessoService.instance.negar(pedido.numero);
      _recarregar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pedidos de acesso'),
        actions: [
          const BotaoInicio(),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _recarregar),
          const AppLogoTrailing(),
        ],
      ),
      body: Column(
        children: [
          SwitchListTile(
            value: _apenasPendentes,
            onChanged: (v) {
              _apenasPendentes = v;
              _recarregar();
            },
            title: const Text('Mostrar só pendentes'),
            dense: true,
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<List<PedidoAcesso>>(
              future: _pedidos,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Erro ao carregar: ${snapshot.error}'),
                    ),
                  );
                }
                final lista = snapshot.data ?? const [];
                if (lista.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Nenhum pedido de acesso.'),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: lista.length,
                  itemBuilder: (context, i) {
                    final p = lista[i];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: p.pendente
                              ? Theme.of(context).colorScheme.tertiaryContainer
                              : null,
                          child: Icon(
                            p.pendente
                                ? Icons.hourglass_empty
                                : p.status == 'liberado'
                                ? Icons.check
                                : Icons.block,
                          ),
                        ),
                        title: Text(
                          p.nome ?? 'Legendário ${p.numero}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Text(
                          '#${p.numero} · ${p.descricaoDoTop} · ${p.status}'
                          '${p.contaJaExiste ? " · já tem conta" : ""}'
                          '${p.telefone != null ? " · ${p.telefone}" : ""}',
                        ),
                        trailing: p.pendente
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.vpn_key),
                                    tooltip: p.contaJaExiste
                                        ? 'Aprovar a conta'
                                        : 'Liberar e gerar código',
                                    onPressed: () => _liberar(p),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.block),
                                    tooltip: 'Negar',
                                    onPressed: () => _negar(p),
                                  ),
                                ],
                              )
                            : null,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
