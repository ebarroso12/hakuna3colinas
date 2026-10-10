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
///
/// **Só usar em tela de onde não se volta** (a raiz, tipo a lista de Tops).
/// Num AppBar de tela empilhada, `leading` substitui a seta de voltar e o
/// usuário fica preso — foi o que aconteceu na tela de detalhe do Top. Em
/// tela interna, use [AppLogoTrailing] no `actions`, que convive com a seta.
class AppLogoAppBarLeading extends StatelessWidget {
  const AppLogoAppBarLeading({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(padding: EdgeInsets.all(8), child: AppLogo(size: 32));
  }
}

/// A logo como `leading`, abrindo a gaveta lateral ao toque.
///
/// Existe porque `Scaffold` só desenha o botão de hambúrguer quando
/// `leading` é nulo — e a tela raiz usa a logo ali. Sem isto a gaveta
/// ficaria acessível só arrastando a borda, que ninguém descobre.
///
/// [novidade] pinta um ponto sobre a logo quando há versão nova; é o único
/// aviso que o usuário recebe sem abrir a gaveta.
class AppLogoAbreGaveta extends StatelessWidget {
  const AppLogoAbreGaveta({super.key, this.novidade = false});

  final bool novidade;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Menu e versão do app',
      padding: const EdgeInsets.all(8),
      // `Scaffold.of` em vez de `Scaffold.maybeOf`: este widget só faz
      // sentido dentro de um Scaffold com gaveta, e falhar alto no
      // desenvolvimento é melhor que um botão que não faz nada em campo.
      onPressed: () => Scaffold.of(context).openDrawer(),
      icon: Badge(
        isLabelVisible: novidade,
        child: const AppLogo(size: 32),
      ),
    );
  }
}

/// A mesma logo, mas do lado direito do AppBar. Mantém a identidade visual
/// sem roubar o lugar da seta de voltar.
class AppLogoTrailing extends StatelessWidget {
  const AppLogoTrailing({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: AppLogo(size: 32),
    );
  }
}
