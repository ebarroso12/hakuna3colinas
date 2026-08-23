import 'package:flutter/material.dart';

import '../models/triage_rule.dart';

/// Selo colorido de triagem (azul/verde/amarelo/vermelho). [color] null
/// significa que não foi possível classificar (falta data de nascimento).
class TriageBadge extends StatelessWidget {
  const TriageBadge({super.key, required this.color});

  final TriageColor? color;

  @override
  Widget build(BuildContext context) {
    final c = color;
    if (c == null) {
      return const Chip(
        label: Text('Sem triagem'),
        visualDensity: VisualDensity.compact,
      );
    }
    return Chip(
      label: Text(c.label, style: const TextStyle(color: Colors.white)),
      backgroundColor: c.materialColor,
      visualDensity: VisualDensity.compact,
    );
  }
}
