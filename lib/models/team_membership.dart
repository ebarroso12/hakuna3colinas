import 'team.dart';

/// Uma linha de top_team_members: o vínculo de uma pessoa com uma equipe
/// dentro de um Top específico.
class TeamMembership {
  final int id;
  final String topId;
  final Team team;
  final String profileId;
  final bool isTeamAdmin;
  final bool released;
  final bool blocked;
  final DateTime createdAt;

  TeamMembership({
    required this.id,
    required this.topId,
    required this.team,
    required this.profileId,
    required this.isTeamAdmin,
    required this.released,
    required this.blocked,
    required this.createdAt,
  });

  factory TeamMembership.fromMap(Map<String, dynamic> map) {
    return TeamMembership(
      id: map['id'] as int,
      topId: map['top_id'] as String,
      team: teamFromDbKey(map['team'] as String),
      profileId: map['profile_id'] as String,
      isTeamAdmin: map['is_team_admin'] as bool? ?? false,
      released: map['released'] as bool? ?? false,
      blocked: map['blocked'] as bool? ?? false,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
