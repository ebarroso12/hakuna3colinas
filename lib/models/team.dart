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

  /// Ícone operacional da equipe — o que a equipe FAZ, pra ser
  /// reconhecida de relance na lista de participantes.
  IconData get iconeOperacional => switch (this) {
    TeamKey.adm => Icons.assignment_ind,
    TeamKey.logistica => Icons.local_shipping, // carro/transporte
    TeamKey.voz => Icons.campaign,
    TeamKey.intercessao => Icons.favorite,
    TeamKey.producao => Icons.handyman,
    TeamKey.midia => Icons.photo_camera, // máquina fotográfica
    TeamKey.eventos => Icons.celebration,
    TeamKey.seguranca => Icons.local_police,
    TeamKey.geral => Icons.forum,
  };

  /// Cor própria de cada equipe, pra diferenciar no meio da lista.
  Color get cor => switch (this) {
    TeamKey.adm => const Color(0xFF5E35B1),
    TeamKey.logistica => const Color(0xFF00897B),
    TeamKey.voz => const Color(0xFFF4511E),
    TeamKey.intercessao => const Color(0xFFAD1457),
    TeamKey.producao => const Color(0xFF6D4C41),
    TeamKey.midia => const Color(0xFF1E88E5),
    TeamKey.eventos => const Color(0xFFFB8C00),
    TeamKey.seguranca => const Color(0xFF37474F),
    TeamKey.geral => const Color(0xFF546E7A),
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
