/// Identidade básica (nome + número do Legendários) de um perfil, sem
/// nenhum dado médico — o que as RPCs searchable_profiles e
/// member_names_for_team devolvem (ver supabase/teams.sql). Usado pra
/// roster e chat de equipe, onde a maioria não deveria ver dado clínico
/// de ninguém.
class MemberName {
  final String id;
  final String fullName;
  final String legendariosNumber;

  MemberName({
    required this.id,
    required this.fullName,
    required this.legendariosNumber,
  });

  factory MemberName.fromMap(Map<String, dynamic> map) {
    return MemberName(
      id: map['id'] as String,
      fullName: map['full_name'] as String,
      legendariosNumber: map['legendarios_number'] as String,
    );
  }

  String get displayLabel => '$fullName · $legendariosNumber';
}
