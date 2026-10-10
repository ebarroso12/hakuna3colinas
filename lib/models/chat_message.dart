class ChatMessage {
  /// Null enquanto a mensagem só existe na fila do aparelho. Ver [pendente].
  final int? id;

  /// Gerado no aparelho. Torna o reenvio idempotente e casa a mensagem
  /// pendente com a que volta pelo realtime. Null nas mensagens anteriores
  /// à v1.0.18.
  final String? clientId;

  final String topId;
  final String senderId;
  final String body;
  final DateTime createdAt;

  ChatMessage({
    required this.topId,
    required this.senderId,
    required this.body,
    required this.createdAt,
    this.id,
    this.clientId,
  });

  /// Ainda na fila do aparelho, não entregue. A tela mostra o relógio.
  bool get pendente => id == null;

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      id: map['id'] as int?,
      clientId: map['client_id'] as String?,
      topId: map['top_id'] as String,
      senderId: map['sender_id'] as String,
      body: map['body'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
