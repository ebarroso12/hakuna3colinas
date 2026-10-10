import 'package:flutter/material.dart';

import '../services/supabase_service.dart';

/// Barra fixa no rodapé, no mesmo espírito do app oficial dos Legendários
/// (LER TAG · PRONTUÁRIOS · SAIR): as ações que o usuário precisa alcançar
/// de qualquer lugar, sem caçar menu.
///
/// Resolve três reclamações reais de uso:
///   - não havia como voltar à tela central depois de entrar num Top;
///   - "Sair" só existia escondido num menu "⋮", e só na lista de Tops;
///   - não havia atalho de edição para quem tem permissão.
class BarraInferior extends StatelessWidget {
  const BarraInferior({
    super.key,
    this.mostrarInicio = true,
    this.aoEditar,
    this.rotuloEditar = 'Editar',
    this.iconeEditar = Icons.edit_outlined,
    this.acaoExtra,
  });

  /// Volta à tela central (lista de Tops). Falso só na própria tela central.
  final bool mostrarInicio;

  /// Quando null, o botão de editar **não aparece**. Quem decide é a tela,
  /// com base no papel: admin, admin master ou coordenador de equipe.
  /// Esconder aqui é cortesia — quem barra de verdade é a RLS.
  final VoidCallback? aoEditar;

  final String rotuloEditar;
  final IconData iconeEditar;

  /// Espaço para uma ação específica da tela (ex: "Ler tag").
  final Widget? acaoExtra;

  Future<void> _confirmarSaida(BuildContext context) async {
    final sair = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sair do app?'),
        content: const Text(
          'Você vai precisar entrar de novo com e-mail e senha.\n\n'
          'Se estiver compartilhando sua posição num Top, o rastreamento '
          'também para.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (sair ?? false) {
      // Não navega manualmente: o AuthGate escuta authStateChanges e troca
      // para a tela de login sozinho.
      await SupabaseService.instance.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    return BottomAppBar(
      height: 64,
      padding: EdgeInsets.zero,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (acaoExtra != null) Expanded(child: acaoExtra!),
          if (mostrarInicio)
            Expanded(
              child: _BotaoBarra(
                icone: Icons.home_outlined,
                rotulo: 'Início',
                // Volta até a tela central em vez de um passo só: de dentro
                // de um chat de equipe, um pop deixaria o usuário no meio
                // do caminho.
                aoTocar: () =>
                    Navigator.of(context).popUntil((rota) => rota.isFirst),
              ),
            ),
          if (aoEditar != null)
            Expanded(
              child: _BotaoBarra(
                icone: iconeEditar,
                rotulo: rotuloEditar,
                aoTocar: aoEditar!,
              ),
            ),
          Expanded(
            child: _BotaoBarra(
              icone: Icons.logout,
              rotulo: 'Sair',
              aoTocar: () => _confirmarSaida(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _BotaoBarra extends StatelessWidget {
  const _BotaoBarra({
    required this.icone,
    required this.rotulo,
    required this.aoTocar,
  });

  final IconData icone;
  final String rotulo;
  final VoidCallback aoTocar;

  @override
  Widget build(BuildContext context) {
    final cor = Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: aoTocar,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 22, color: cor),
          const SizedBox(height: 2),
          Text(
            rotulo,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cor),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
