import 'package:flutter/material.dart';

/// Botão que volta direto para a tela inicial, de qualquer profundidade.
///
/// Fica no `actions` do AppBar, ao lado da seta de voltar — não no lugar
/// dela. São saídas diferentes e as duas precisam existir: a seta volta
/// **um** passo, e quem está em ficha → prontuário → atendimento precisa
/// de três toques para sair. Numa trilha, com o celular numa mão, isso é
/// caminho longo demais.
///
/// NÃO usar na tela inicial (não há para onde ir) nem nas telas de antes
/// do login (`login`, `primeiro acesso`, `cadastro`): ali a seta já leva
/// ao login, e um ícone de casa prometeria uma "página inicial" que a
/// pessoa ainda não tem.
///
/// `popUntil(isFirst)` em vez de `pushReplacement` para a tela inicial:
/// empilhar outra cópia da inicial faria a seta de voltar dela levar de
/// volta para dentro do app, em vez de sair.
class BotaoInicio extends StatelessWidget {
  const BotaoInicio({super.key});

  @override
  Widget build(BuildContext context) {
    // Sem rota para desempilhar, o botão não faz nada — e botão que não
    // faz nada é pior que botão ausente. Some.
    if (!Navigator.of(context).canPop()) return const SizedBox.shrink();

    return IconButton(
      icon: const Icon(Icons.home_outlined),
      tooltip: 'Voltar ao início',
      onPressed: () => Navigator.of(context).popUntil((rota) => rota.isFirst),
    );
  }
}
