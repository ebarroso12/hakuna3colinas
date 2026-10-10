import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/acesso_service.dart';
import '../../widgets/app_logo.dart';

/// Pedidos de acesso ao app.
///
/// O admin libera e **entrega o código à pessoa** — por WhatsApp,
/// pessoalmente, como for. Não há envio automático: decisão de produto
/// para manter custo zero e deixar o admin no controle de quem entra.
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

  Future<void> _liberar(PedidoAcesso pedido) async {
    try {
      final codigo = await AcessoService.instance.liberar(pedido.numero);
      if (!mounted) return;
      await _mostrarCodigo(pedido, codigo);
      _recarregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Não foi possível liberar: $e')));
    }
  }

  /// Mostra o código uma única vez.
  ///
  /// O banco guarda só o hash — se o admin fechar sem anotar, precisa
  /// gerar outro. É de propósito: código legível guardado para sempre é
  /// senha em texto claro.
  Future<void> _mostrarCodigo(PedidoAcesso pedido, String codigo) {
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
                          '#${p.numero} · ${p.status}'
                          '${p.telefone != null ? " · ${p.telefone}" : ""}',
                        ),
                        trailing: p.pendente
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.vpn_key),
                                    tooltip: 'Liberar e gerar código',
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
