import 'package:flutter/material.dart';

import '../services/exclusao_service.dart';

/// Barra que aparece no lugar do título quando há itens marcados.
///
/// Fica no AppBar das telas de usuários e de senderistas. Mostra quantos
/// estão marcados, deixa marcar/desmarcar todos e dispara a exclusão.
class BarraDeSelecao extends StatelessWidget {
  const BarraDeSelecao({
    super.key,
    required this.marcados,
    required this.total,
    required this.aoMarcarTodos,
    required this.aoLimpar,
    required this.aoApagar,
  });

  final int marcados;
  final int total;
  final VoidCallback aoMarcarTodos;
  final VoidCallback aoLimpar;
  final VoidCallback aoApagar;

  @override
  Widget build(BuildContext context) {
    final excedeu = marcados > ExclusaoService.maxPorVez;
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Sair da seleção',
          onPressed: aoLimpar,
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('$marcados marcado(s)'),
              if (excedeu)
                Text(
                  'máximo ${ExclusaoService.maxPorVez} por vez',
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.select_all),
          tooltip: 'Marcar todos os $total',
          onPressed: aoMarcarTodos,
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Apagar marcados',
          // Desabilitado acima do teto em vez de truncar a lista em
          // silêncio: cortar os 51 marcados em 50 apagaria quase tudo e
          // deixaria um de fora sem ninguém entender por quê.
          onPressed: marcados == 0 || excedeu ? null : aoApagar,
        ),
      ],
    );
  }
}

/// O que o usuário escolheu no diálogo de confirmação.
enum DecisaoDaExclusao { apagar, desativar, cancelar }

/// Diálogo de confirmação da exclusão.
///
/// Mostra, nome por nome, quem sai e quem **não** sai — e por quê. Foi
/// desenhado assim porque a alternativa (apagar o que der e avisar depois)
/// é a que faz alguém perder dado sem perceber: a pessoa marca 30 nomes,
/// confirma, e não sabe que 4 ficaram.
///
/// Quando há bloqueados, oferece **desativar** como terceira via — é a
/// resposta certa para quem tem prontuário: tira das listas sem apagar a
/// história. [podeDesativar] é false na tela de usuários, onde não existe
/// esse conceito hoje.
Future<DecisaoDaExclusao> confirmarExclusao(
  BuildContext context, {
  required Map<String, String> nomes,
  required Map<String, Dependencias> dependencias,
  required bool podeDesativar,
}) async {
  final liberados = <String>[];
  final bloqueados = <String>[];
  for (final id in nomes.keys) {
    final d = dependencias[id];
    (d?.podeApagar ?? false ? liberados : bloqueados).add(id);
  }

  final escolha = await showDialog<DecisaoDaExclusao>(
    context: context,
    builder: (ctx) {
      final cores = Theme.of(ctx).colorScheme;
      return AlertDialog(
        title: Text(
          liberados.isEmpty
              ? 'Nada pode ser apagado'
              : 'Apagar ${liberados.length} definitivamente?',
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              if (liberados.isNotEmpty) ...[
                Text(
                  'SAI DE VEZ — não tem como desfazer:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: cores.error,
                  ),
                ),
                const SizedBox(height: 4),
                for (final id in liberados)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 2),
                    child: Text('• ${nomes[id]}'),
                  ),
                const SizedBox(height: 12),
              ],
              if (bloqueados.isNotEmpty) ...[
                const Text(
                  'FICA — tem registro clínico:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                for (final id in bloqueados)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, bottom: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('• ${nomes[id]}'),
                        Text(
                          '  ${dependencias[id]?.porque ?? "motivo desconhecido"}',
                          style: Theme.of(ctx).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  podeDesativar
                      ? 'Prontuário não se apaga junto com o cadastro. '
                            'Para tirar essas pessoas das listas sem perder '
                            'o histórico, use Desativar.'
                      : 'Prontuário não se apaga junto com o cadastro. '
                            'Essas contas continuam.',
                  style: Theme.of(ctx).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(DecisaoDaExclusao.cancelar),
            child: const Text('Cancelar'),
          ),
          if (podeDesativar && bloqueados.isNotEmpty)
            TextButton(
              onPressed: () =>
                  Navigator.of(ctx).pop(DecisaoDaExclusao.desativar),
              child: Text('Desativar ${bloqueados.length}'),
            ),
          if (liberados.isNotEmpty)
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cores.error),
              onPressed: () => Navigator.of(ctx).pop(DecisaoDaExclusao.apagar),
              child: Text('APAGAR ${liberados.length}'),
            ),
        ],
      );
    },
  );
  return escolha ?? DecisaoDaExclusao.cancelar;
}
