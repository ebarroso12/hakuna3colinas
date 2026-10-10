import 'package:flutter/material.dart';

import '../models/participant.dart';
import '../models/profile.dart';
import '../models/team.dart';

/// Cores e símbolos que identificam quem é quem na lista, de longe e no
/// meio do mato, sem precisar ler o texto.
///
/// Verde = Legendário (tem número). Azul = Senderista (participante, não
/// usa o app). Vermelho = quem coordena. A cor é o primeiro sinal; o
/// símbolo confirma.
abstract final class CoresEmblema {
  static const legendario = Color(0xFF1B7F4C);
  static const senderista = Color(0xFF1565C0);
  static const coordenador = Color(0xFFC62828);
  static const hakuna = Color(0xFFD84315);
}

/// Emblema do Legendário: verde com a insígnia.
class EmblemaLegendario extends StatelessWidget {
  const EmblemaLegendario({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return _Selo(
      cor: CoresEmblema.legendario,
      icone: Icons.military_tech,
      size: size,
      tooltip: 'Legendário',
    );
  }
}

/// Emblema do Senderista: azul, com símbolo que remete à salvação —
/// a mão que ampara.
class EmblemaSenderista extends StatelessWidget {
  const EmblemaSenderista({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return _Selo(
      cor: CoresEmblema.senderista,
      icone: Icons.volunteer_activism,
      size: size,
      tooltip: 'Senderista',
    );
  }
}

/// Emblema de quem coordena. Maior e em vermelho de propósito: precisa
/// saltar aos olhos em meio a 215 linhas de lista.
class EmblemaCoordenador extends StatelessWidget {
  const EmblemaCoordenador({
    super.key,
    this.size = 40,
    this.subcoordenador = false,
  });

  final double size;
  final bool subcoordenador;

  @override
  Widget build(BuildContext context) {
    return _Selo(
      cor: CoresEmblema.coordenador,
      icone: subcoordenador ? Icons.shield_moon : Icons.workspace_premium,
      size: size,
      tooltip: subcoordenador ? 'Subcoordenador' : 'Coordenador',
      destacado: true,
    );
  }
}

/// Ícone da equipe em que a pessoa serve neste Top.
class EmblemaEquipe extends StatelessWidget {
  const EmblemaEquipe({super.key, required this.team, this.size = 28});

  final TeamKey team;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: team.label,
      child: Icon(team.iconeOperacional, size: size, color: team.cor),
    );
  }
}

class _Selo extends StatelessWidget {
  const _Selo({
    required this.cor,
    required this.icone,
    required this.size,
    required this.tooltip,
    this.destacado = false,
  });

  final Color cor;
  final IconData icone;
  final double size;
  final String tooltip;
  final bool destacado;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: cor,
          borderRadius: BorderRadius.circular(size * 0.25),
          border: destacado
              ? Border.all(color: Colors.amber.shade600, width: 2.5)
              : null,
        ),
        child: Icon(icone, size: size * 0.62, color: Colors.white),
      ),
    );
  }
}

/// Decide qual emblema uma pessoa recebe na lista.
///
/// A ordem é de prioridade: coordenar a equipe é o que mais importa
/// enxergar; depois ser Hakuna (quem atende); depois Legendário ou
/// Senderista.
Widget emblemaPara({
  required bool ehLegendario,
  UserRole? papel,
  bool coordenador = false,
  bool subcoordenador = false,
  double size = 36,
}) {
  if (coordenador || subcoordenador) {
    return EmblemaCoordenador(size: size + 4, subcoordenador: subcoordenador);
  }
  if (papel == UserRole.hakuna) {
    return _Selo(
      cor: CoresEmblema.hakuna,
      icone: Icons.emergency,
      size: size,
      tooltip: 'Hakuna — equipe de saúde',
    );
  }
  return ehLegendario
      ? EmblemaLegendario(size: size)
      : EmblemaSenderista(size: size);
}

/// Cor da triagem aplicada à linha do participante, quando houver.
Color? corDeFundoPorTriagem(Participant p) => null;
