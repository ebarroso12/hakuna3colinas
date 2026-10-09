import 'package:flutter/material.dart';

/// As equipes de um Top. Espelha o enum `team_key` do Postgres — os nomes
/// precisam bater exatamente com os valores do banco, porque são eles que
/// vão e voltam na coluna `team`.
enum TeamKey {
  adm,
  logistica,
  voz,
  intercessao,
  producao,
  midia,
  eventos,
  seguranca,
  geral,
}

TeamKey? teamKeyFromString(String? value) {
  if (value == null) return null;
  for (final t in TeamKey.values) {
    if (t.name == value) return t;
  }
  return null;
}

extension TeamKeyUi on TeamKey {
  String get label => switch (this) {
    TeamKey.adm => 'Administração',
    TeamKey.logistica => 'Logística',
    TeamKey.voz => 'Voz',
    TeamKey.intercessao => 'Intercessão',
    TeamKey.producao => 'Produção',
    TeamKey.midia => 'Mídia',
    TeamKey.eventos => 'Eventos',
    TeamKey.seguranca => 'Segurança',
    TeamKey.geral => 'Geral',
  };

  IconData get icon => switch (this) {
    TeamKey.adm => Icons.badge_outlined,
    TeamKey.logistica => Icons.local_shipping_outlined,
    TeamKey.voz => Icons.campaign_outlined,
    TeamKey.intercessao => Icons.volunteer_activism_outlined,
    TeamKey.producao => Icons.build_outlined,
    TeamKey.midia => Icons.photo_camera_outlined,
    TeamKey.eventos => Icons.event_outlined,
    TeamKey.seguranca => Icons.shield_outlined,
    TeamKey.geral => Icons.forum_outlined,
  };

  /// O chat geral é o único que todo participante aprovado do Top enxerga —
  /// as outras equipes só aparecem para quem é membro. Essa regra é imposta
  /// pela RLS de `team_messages`, não pela UI: a UI só evita mostrar uma
  /// porta que o banco vai fechar.
  bool get isGeral => this == TeamKey.geral;

  /// As 8 equipes de verdade, sem o canal geral.
  static List<TeamKey> get equipes =>
      TeamKey.values.where((t) => !t.isGeral).toList();
}
