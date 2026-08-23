class HakunaPosition {
  final String profileId;
  final String topId;
  final double latitude;
  final double longitude;
  final DateTime recordedAt;

  HakunaPosition({
    required this.profileId,
    required this.topId,
    required this.latitude,
    required this.longitude,
    required this.recordedAt,
  });

  factory HakunaPosition.fromMap(Map<String, dynamic> map) {
    return HakunaPosition(
      profileId: map['profile_id'] as String,
      topId: map['top_id'] as String,
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      recordedAt: DateTime.parse(map['recorded_at'] as String),
    );
  }
}
