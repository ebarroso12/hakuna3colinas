import 'package:flutter/material.dart';

/// As 9 equipes de "Legendários 3 Colinas" + o canal geral, aberto a
/// todos. Ver supabase/teams.sql.
enum Team {
  adm,
  logistica,
  hakunas,
  voz,
  intercessao,
  producao,
  midia,
  eventos,
  seguranca,
  geral;

  String get label => switch (this) {
    Team.adm => 'ADM',
    Team.logistica => 'Logística',
    Team.hakunas => 'Hakunas',
    Team.voz => 'Voz',
    Team.intercessao => 'Intercessão',
    Team.producao => 'Produção',
    Team.midia => 'Mídia',
    Team.eventos => 'Eventos',
    Team.seguranca => 'Segurança',
    Team.geral => 'Legendários 3 Colinas',
  };

  IconData get icon => switch (this) {
    Team.adm => Icons.badge_outlined,
    Team.logistica => Icons.local_shipping_outlined,
    Team.hakunas => Icons.medical_services_outlined,
    Team.voz => Icons.mic_outlined,
    Team.intercessao => Icons.volunteer_activism_outlined,
    Team.producao => Icons.movie_creation_outlined,
    Team.midia => Icons.camera_alt_outlined,
    Team.eventos => Icons.event_outlined,
    Team.seguranca => Icons.shield_outlined,
    Team.geral => Icons.groups_outlined,
  };

  /// Hakunas já tem toda a infraestrutura própria (top_hakunas, chat,
  /// atendimento, despacho) — não duplicada nas tabelas novas de equipe.
  bool get hasOwnInfrastructure => this == Team.hakunas;

  /// Chave usada em top_team_members/team_messages. Null pra Hakunas —
  /// ver [hasOwnInfrastructure].
  String? get dbKey => hasOwnInfrastructure ? null : name;

  /// Mesma chave de [dbKey], mas falha alto e com mensagem clara em vez de
  /// um null-check genérico (ou de um fallback silencioso pro canal
  /// 'geral') quando chamado com Team.hakunas — nenhuma tabela nova de
  /// equipe (top_team_members/team_messages) tem linha pra Hakunas, que
  /// usa a infraestrutura própria (ver [hasOwnInfrastructure]). Toda
  /// SupabaseService que opera nessas tabelas deve usar este getter, nunca
  /// `dbKey!` ou `dbKey ?? 'geral'` diretamente.
  String get requiredDbKey {
    final key = dbKey;
    if (key == null) {
      throw ArgumentError(
        'Team.hakunas não tem linha em top_team_members/team_messages — '
        'usa a infraestrutura própria (top_hakunas/top_chat_screen).',
      );
    }
    return key;
  }

  /// Todas as equipes exclusivas (isoladas entre si), sem contar o canal
  /// geral — na ordem pedida.
  static const exclusive = [
    Team.adm,
    Team.logistica,
    Team.hakunas,
    Team.voz,
    Team.intercessao,
    Team.producao,
    Team.midia,
    Team.eventos,
    Team.seguranca,
  ];
}

Team teamFromDbKey(String key) {
  return Team.values.firstWhere(
    (t) => t.dbKey == key,
    orElse: () => Team.geral,
  );
}
