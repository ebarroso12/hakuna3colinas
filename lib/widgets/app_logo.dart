import 'package:flutter/material.dart';

/// Logomarca do Legendários 3 Colinas. Aparece grande na tela de login e
/// pequena, fixa no AppBar do resto do app, pra manter a identidade visual
/// sempre evidente.
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.12),
      child: Image.asset(
        'assets/images/logo_3colinas.jpg',
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}

/// Ícone pequeno da logo pra usar como leading do AppBar nas telas internas.
class AppLogoAppBarLeading extends StatelessWidget {
  const AppLogoAppBarLeading({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.all(8), child: AppLogo(size: 32));
  }
}

/// Título de AppBar com a logo embutida — tocar na logo volta pro menu
/// principal (Meus Tops) de qualquer tela, não importa a profundidade da
/// navegação. O botão de voltar padrão do Flutter continua funcionando
/// normalmente (não sobrescrevemos mais o `leading`, ele volta a aparecer
/// sozinho quando há uma tela anterior na pilha).
class AppBarLogoTitle extends StatelessWidget {
  const AppBarLogoTitle({super.key, required this.title});

  final Widget title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.of(context).popUntil((route) => route.isFirst),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: AppLogo(size: 32),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DefaultTextStyle.merge(
            overflow: TextOverflow.ellipsis,
            child: title,
          ),
        ),
      ],
    );
  }
}
