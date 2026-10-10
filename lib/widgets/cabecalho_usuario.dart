import 'package:flutter/material.dart';

import '../models/profile.dart';
import '../services/supabase_service.dart';

/// Cabeçalho "TOP# 1782 · HAKUNA 203460 ✏️", como no app oficial.
///
/// Tocar abre o cartão de identidade do usuário. É onde ele confere quem
/// está logado naquele aparelho — importante quando vários Hakunas
/// compartilham celular em campo.
class CabecalhoUsuario extends StatelessWidget {
  const CabecalhoUsuario({
    super.key,
    required this.perfil,
    this.numeroTop,
    this.aoEditar,
  });

  final Profile? perfil;
  final String? numeroTop;

  /// Null esconde o lápis. Editar o próprio nome é de qualquer usuário;
  /// mudar papel, não — e isso a RLS de `profiles` já garante.
  final VoidCallback? aoEditar;

  @override
  Widget build(BuildContext context) {
    final p = perfil;
    return InkWell(
      onTap: p == null ? null : () => mostrarCartaoUsuario(context, p),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (numeroTop != null) ...[
              Text(
                'TOP# $numeroTop',
                style: Theme.of(context).textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 12),
            ],
            Flexible(
              child: Text(
                p == null ? '—' : '${_titulo(p)} ${p.legendariosNumber}',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.amber.shade700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (aoEditar != null)
              IconButton(
                icon: const Icon(Icons.edit, size: 16),
                visualDensity: VisualDensity.compact,
                tooltip: 'Editar meus dados',
                onPressed: aoEditar,
              ),
          ],
        ),
      ),
    );
  }

  static String _titulo(Profile p) => switch (p.role) {
    UserRole.admin => 'ADMIN',
    UserRole.hakuna => 'HAKUNA',
    UserRole.senderista => 'LGND',
  };
}

/// Cartão de identidade de quem está logado.
///
/// O que aparece depende do papel, mas nada aqui concede poder: é um
/// espelho do que a RLS já permite. Mostrar o papel errado não daria
/// acesso a nada — só confundiria o usuário.
Future<void> mostrarCartaoUsuario(BuildContext context, Profile perfil) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'NOME',
            style: Theme.of(dialogContext).textTheme.labelSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          _Caixa(texto: perfil.fullName.toUpperCase(), destaque: true),
          const SizedBox(height: 16),
          Text(
            'NÚMERO LEGENDÁRIOS',
            style: Theme.of(dialogContext).textTheme.labelSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          _Caixa(texto: perfil.legendariosNumber, destaque: true, centro: true),
          const SizedBox(height: 16),
          _LinhaPapel(perfil: perfil),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Fechar'),
        ),
        FilledButton(
          onPressed: () async {
            Navigator.of(dialogContext).pop();
            await SupabaseService.instance.signOut();
          },
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
          ),
          child: const Text('Sair'),
        ),
      ],
    ),
  );
}

class _Caixa extends StatelessWidget {
  const _Caixa({
    required this.texto,
    this.destaque = false,
    this.centro = false,
  });

  final String texto;
  final bool destaque;
  final bool centro;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: centro ? Alignment.center : Alignment.centerLeft,
      child: Text(
        texto,
        textAlign: centro ? TextAlign.center : TextAlign.start,
        style: destaque
            ? Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: centro ? 3 : 0,
              )
            : null,
      ),
    );
  }
}

/// Mostra o papel e o que ele permite, em uma linha legível.
class _LinhaPapel extends StatelessWidget {
  const _LinhaPapel({required this.perfil});

  final Profile perfil;

  @override
  Widget build(BuildContext context) {
    final (rotulo, descricao, cor) = _papel(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.12),
        border: Border.all(color: cor),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.verified_user_outlined, size: 18, color: cor),
              const SizedBox(width: 6),
              Text(
                rotulo,
                style: TextStyle(fontWeight: FontWeight.bold, color: cor),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(descricao, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }

  (String, String, Color) _papel(BuildContext context) {
    if (perfil.isMasterAdmin) {
      return (
        'ADMIN MASTER',
        'Controle total: usuários, equipes, Tops, coordenadores e regras '
            'de triagem.',
        const Color(0xFFC62828),
      );
    }
    if (perfil.role == UserRole.admin) {
      return (
        'ADMIN GERAL',
        'Mesmas funções do master, exceto mexer no próprio admin master.',
        const Color(0xFFEF6C00),
      );
    }
    if (perfil.role == UserRole.hakuna) {
      return (
        'HAKUNA',
        'Equipe de saúde: lê tags, vê fichas e registra atendimentos.',
        const Color(0xFFD84315),
      );
    }
    return (
      'LEGENDÁRIO',
      'Participa dos Tops e dos chats das suas equipes.',
      const Color(0xFF1B7F4C),
    );
  }
}
