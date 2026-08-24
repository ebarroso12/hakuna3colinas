/// Participante de um Top: pode ser um cadastro rápido feito por um Hakuna
/// em campo (sem conta de login) ou já estar vinculado a um Senderista com
/// conta própria via [linkedProfileId] — ver supabase/participants_and_attendance.sql
/// pra entender por que não reaproveitamos profiles/Senderista diretamente.
class Participant {
  final String id;
  final String topId;
  final String? linkedProfileId;
  final String? participantCode;
  final String fullName;
  final String? nickname;
  final String? phone;
  final DateTime? birthDate;
  final String? emergencyContact;
  final String? notes;
  final String? tagUid;
  final String registeredBy;
  final bool active;
  final DateTime createdAt;

  Participant({
    required this.id,
    required this.topId,
    this.linkedProfileId,
    this.participantCode,
    required this.fullName,
    this.nickname,
    this.phone,
    this.birthDate,
    this.emergencyContact,
    this.notes,
    this.tagUid,
    required this.registeredBy,
    this.active = true,
    required this.createdAt,
  });

  factory Participant.fromMap(Map<String, dynamic> map) {
    return Participant(
      id: map['id'] as String,
      topId: map['top_id'] as String,
      linkedProfileId: map['linked_profile_id'] as String?,
      participantCode: map['participant_code'] as String?,
      fullName: map['full_name'] as String,
      nickname: map['nickname'] as String?,
      phone: map['phone'] as String?,
      birthDate: map['birth_date'] != null
          ? DateTime.parse(map['birth_date'] as String)
          : null,
      emergencyContact: map['emergency_contact'] as String?,
      notes: map['notes'] as String?,
      tagUid: map['tag_uid'] as String?,
      registeredBy: map['registered_by'] as String,
      active: map['active'] as bool? ?? true,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  /// Como identificar o participante na tela: nome + apelido, quando houver.
  String get displayLabel => nickname == null || nickname!.isEmpty
      ? fullName
      : '$fullName ($nickname)';
}
