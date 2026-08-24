class ChatMessage {
  final int id;
  final String topId;
  final String senderId;
  final String body;
  final DateTime createdAt;
  final bool isSystem;

  ChatMessage({
    required this.id,
    required this.topId,
    required this.senderId,
    required this.body,
    required this.createdAt,
    this.isSystem = false,
  });

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'] as int,
      topId: map['top_id'] as String,
      senderId: map['sender_id'] as String,
      body: map['body'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      isSystem: map['is_system'] as bool? ?? false,
    );
  }
}
