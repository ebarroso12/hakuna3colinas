enum TopStatus { draft, active, finished }

TopStatus topStatusFromString(String value) {
  return TopStatus.values.firstWhere(
    (s) => s.name == value,
    orElse: () => TopStatus.draft,
  );
}

class Top {
  final String id;
  final String name;
  final String? description;
  final TopStatus status;
  final DateTime? startsAt;
  final DateTime? endsAt;

  Top({
    required this.id,
    required this.name,
    this.description,
    required this.status,
    this.startsAt,
    this.endsAt,
  });

  factory Top.fromMap(Map<String, dynamic> map) {
    return Top(
      id: map['id'] as String,
      name: map['name'] as String,
      description: map['description'] as String?,
      status: topStatusFromString(map['status'] as String),
      startsAt: map['starts_at'] != null ? DateTime.parse(map['starts_at'] as String) : null,
      endsAt: map['ends_at'] != null ? DateTime.parse(map['ends_at'] as String) : null,
    );
  }
}
