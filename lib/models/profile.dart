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
  final UserRole role;
  final String? phone;
  final String? medicalRegistry;

  Profile({
    required this.id,
    required this.fullName,
    required this.role,
    this.phone,
    this.medicalRegistry,
  });

  factory Profile.fromMap(Map<String, dynamic> map) {
    return Profile(
      id: map['id'] as String,
      fullName: map['full_name'] as String,
      role: userRoleFromString(map['role'] as String),
      phone: map['phone'] as String?,
      medicalRegistry: map['medical_registry'] as String?,
    );
  }
}
