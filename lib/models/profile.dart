enum UserRole { admin, hakuna, senderista }

UserRole userRoleFromString(String value) {
  return UserRole.values.firstWhere(
    (r) => r.name == value,
    orElse: () => UserRole.senderista,
  );
}

class Profile {
  final String id;
  final String fullName;
  final String legendariosNumber;
  final UserRole role;
  final String? phone;
  final String? medicalRegistry;
  final double? weightKg;

  Profile({
    required this.id,
    required this.fullName,
    required this.legendariosNumber,
    required this.role,
    this.phone,
    this.medicalRegistry,
    this.weightKg,
  });

  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      id: map['id'] as String,
      fullName: map['full_name'] as String,
      legendariosNumber: map['legendarios_number'] as String,
      role: userRoleFromString(map['role'] as String),
      phone: map['phone'] as String?,
      medicalRegistry: map['medical_registry'] as String?,
      weightKg: (map['weight_kg'] as num?)?.toDouble(),
    );
  }

  /// Como o usuário deve ser identificado na tela: nome + número do Legendários.
  String get displayLabel => '$fullName · $legendariosNumber';
}
