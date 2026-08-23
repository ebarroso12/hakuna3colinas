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
  final bool isMasterAdmin;
  final DateTime? birthDate;
  final List<String> comorbidities;
  final bool approved;

  Profile({
    required this.id,
    required this.fullName,
    required this.legendariosNumber,
    required this.role,
    this.phone,
    this.medicalRegistry,
    this.weightKg,
    this.isMasterAdmin = false,
    this.birthDate,
    this.comorbidities = const [],
    this.approved = false,
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
      isMasterAdmin: map['is_master_admin'] as bool? ?? false,
      birthDate: map['birth_date'] != null ? DateTime.parse(map['birth_date'] as String) : null,
      comorbidities: (map['comorbidities'] as List<dynamic>?)?.cast<String>() ?? const [],
      approved: map['approved'] as bool? ?? false,
    );
  }

  /// Como o usuário deve ser identificado na tela: nome + número do Legendários.
  String get displayLabel => '$fullName · $legendariosNumber';

  /// Idade em anos completos a partir da data de nascimento, usada na
  /// triagem por cor. Null se o Senderista não informou a data.
  int? get age {
    final b = birthDate;
    if (b == null) return null;
    final now = DateTime.now();
    var years = now.year - b.year;
    if (now.month < b.month || (now.month == b.month && now.day < b.day)) years--;
    return years;
  }
}
