/// Notificação in-app (via Realtime — funciona enquanto o app está aberto,
/// não substitui push de verdade). Ver supabase/participants_and_attendance.sql.
class AppNotification {
  final int id;
  final String topId;
  final String? recipientId; // null = broadcast pra todos os Hakunas liberados
  final String type;
  final String title;
  final String? body;
  final String? relatedAttendanceId;
  final DateTime createdAt;
  final DateTime? readAt;

  AppNotification({
    required this.id,
    required this.topId,
    this.recipientId,
    required this.type,
    required this.title,
    this.body,
    this.relatedAttendanceId,
    required this.createdAt,
    this.readAt,
  });

  factory AppNotification.fromMap(Map<String, dynamic> map) {
    return AppNotification(
      id: map['id'] as int,
      topId: map['top_id'] as String,
      recipientId: map['recipient_id'] as String?,
      type: map['type'] as String,
      title: map['title'] as String,
      body: map['body'] as String?,
      relatedAttendanceId: map['related_attendance_id'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      readAt: map['read_at'] != null
          ? DateTime.parse(map['read_at'] as String)
          : null,
    );
  }

  bool get isUnread => readAt == null;
}
