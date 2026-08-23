class TopAlert {
  final int id;
  final String topId;
  final String senderId;
  final String? message;
  final double? latitude;
  final double? longitude;
  final DateTime createdAt;

  TopAlert({
    required this.id,
    required this.topId,
    required this.senderId,
    this.message,
    this.latitude,
    this.longitude,
    required this.createdAt,
  });

  factory TopAlert.fromMap(Map<String, dynamic> map) {
    return TopAlert(
      id: map['id'] as int,
      topId: map['top_id'] as String,
      senderId: map['sender_id'] as String,
      message: map['message'] as String?,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
