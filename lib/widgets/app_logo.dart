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
    return Padding(
      padding: const EdgeInsets.all(8),
      child: AppLogo(size: 32),
    );
  }
}
