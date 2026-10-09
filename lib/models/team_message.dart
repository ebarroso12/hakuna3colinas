import 'team.dart';

/// Mensagem de um chat de equipe (ou do chat geral, que é a equipe
/// [TeamKey.geral]). Tabela `team_messages`.
class TeamMessage {
  final int id;
  final String topId;
  final TeamKey team;
  final String senderId;
  final String body;
  final DateTime createdAt;

  /// Marcado só por admin da equipe ou admin geral — a RLS de INSERT
  /// rejeita `is_alert = true` de qualquer outro remetente.
  final bool isAlert;

  /// Preenchido quando a mensagem foi editada depois de enviada. Null em
  /// mensagem nunca editada.
  final DateTime? editedAt;

  TeamMessage({
    required this.id,
    required this.topId,
    required this.team,
    required this.senderId,
    required this.body,
    required this.createdAt,
    required this.isAlert,
    this.editedAt,
  });

  factory TeamMessage.fromMap(Map<String, dynamic> map) {
    return TeamMessage(
      id: map['id'] as int,
      topId: map['top_id'] as String,
      // Um valor de `team` que o app não conhece (equipe nova criada no
      // banco antes de o app ser atualizado) cai em geral em vez de
      // estourar — mensagem fora de lugar é melhor que tela quebrada.
      team: teamKeyFromString(map['team'] as String?) ?? TeamKey.geral,
      senderId: map['sender_id'] as String,
      body: map['body'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      isAlert: map['is_alert'] as bool? ?? false,
      editedAt: map['edited_at'] != null
          ? DateTime.parse(map['edited_at'] as String)
          : null,
    );
  }
}

/// Vínculo de um perfil com uma equipe dentro de um Top. Tabela
/// `top_team_members`.
class TeamMembership {
  final int id;
  final String topId;
  final TeamKey team;
  final String profileId;
  final bool isTeamAdmin;

  /// Liberado para atuar na equipe naquele Top. Um membro não liberado
  /// ainda não aparece para os outros membros (ver a policy de SELECT).
  final bool released;
  final bool blocked;

  TeamMembership({
    required this.id,
    required this.topId,
    required this.team,
    required this.profileId,
    required this.isTeamAdmin,
    required this.released,
    required this.blocked,
  });

  factory TeamMembership.fromMap(Map<String, dynamic> map) {
    return TeamMembership(
      id: map['id'] as int,
      topId: map['top_id'] as String,
      team: teamKeyFromString(map['team'] as String?) ?? TeamKey.geral,
      profileId: map['profile_id'] as String,
      isTeamAdmin: map['is_team_admin'] as bool? ?? false,
      released: map['released'] as bool? ?? false,
      blocked: map['blocked'] as bool? ?? false,
    );
  }

  /// Só quem está liberado e não bloqueado participa de fato da equipe.
  bool get isActive => released && !blocked;
}
