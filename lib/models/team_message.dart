import 'team.dart';

class TeamMessage {
  final int id;
  final String topId;
  final Team team;
  final String senderId;
  final String body;
  final bool isAlert;
  final DateTime? editedAt;
  final DateTime createdAt;

  TeamMessage({
    required this.id,
    required this.topId,
    required this.team,
    required this.senderId,
    required this.body,
    required this.isAlert,
    this.editedAt,
    required this.createdAt,
  });

  factory TeamMessage.fromMap(Map<String, dynamic> map) {
    return TeamMessage(
      id: map['id'] as int,
      topId: map['top_id'] as String,
      team: teamFromDbKey(map['team'] as String),
      senderId: map['sender_id'] as String,
      body: map['body'] as String,
      isAlert: map['is_alert'] as bool? ?? false,
      editedAt: map['edited_at'] != null
          ? DateTime.parse(map['edited_at'] as String)
          : null,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
