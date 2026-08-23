import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';
import '../models/top.dart';
import '../models/triage_rule.dart';

/// Operações exclusivas de admin/admin master: gestão de usuários, Tops e
/// regras de triagem. A autoridade real é imposta pelo RLS no banco (um
/// admin comum nunca consegue tocar no perfil do admin master, só o admin
/// master edita regras de triagem) — esta classe só chama as queries; se a
/// permissão faltar, o Supabase rejeita e o erro sobe pra UI.
class AdminService {
  AdminService._();

  static final AdminService instance = AdminService._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<List<Profile>> fetchAllProfiles() async {
    final rows = await _client.from('profiles').select().order('full_name');
    return rows.map((r) => Profile.fromMap(r)).toList();
  }

  /// Promove/rebaixa um usuário. Conceder papel 'admin' só é aceito pelo
  /// banco se quem chama for o admin master.
  Future<void> updateProfileRole(String profileId, UserRole role) {
    return _client.from('profiles').update({'role': role.name}).eq('id', profileId);
  }

  /// Libera o acesso de um cadastro pendente — sem isso o usuário fica
  /// preso na tela de "aguardando aprovação" pra sempre.
  Future<void> approveProfile(String profileId) => setApproved(profileId, true);

  /// Libera ou revoga o acesso de um usuário.
  Future<void> setApproved(String profileId, bool approved) {
    return _client.from('profiles').update({'approved': approved}).eq('id', profileId);
  }

  /// Dados usados na triagem por cor. Qualquer admin pode editar (só o
  /// papel 'admin' e a flag de admin master são exclusivos do admin master).
  Future<void> updateProfileTriageInfo(String profileId, {DateTime? birthDate, required List<String> comorbidities}) {
    return _client.from('profiles').update({
      'birth_date': birthDate?.toIso8601String().split('T').first,
      'comorbidities': comorbidities,
    }).eq('id', profileId);
  }

  /// Rejeitado pelo banco se [profileId] for o admin master.
  Future<void> deleteProfile(String profileId) {
    return _client.from('profiles').delete().eq('id', profileId);
  }

  Future<Top> createTop({
    required String name,
    String? topNumber,
    String? location,
    String? description,
    DateTime? startsAt,
    DateTime? endsAt,
  }) async {
    final row = await _client
        .from('tops')
        .insert({
          'name': name,
          'top_number': topNumber,
          'location': location,
          'description': description,
          'starts_at': startsAt?.toIso8601String(),
          'ends_at': endsAt?.toIso8601String(),
        })
        .select()
        .single();
    return Top.fromMap(row);
  }

  Future<void> updateTop({
    required String topId,
    required String name,
    String? topNumber,
    String? location,
    String? description,
    required TopStatus status,
    DateTime? startsAt,
    DateTime? endsAt,
  }) {
    return _client.from('tops').update({
      'name': name,
      'top_number': topNumber,
      'location': location,
      'description': description,
      'status': status.name,
      'starts_at': startsAt?.toIso8601String(),
      'ends_at': endsAt?.toIso8601String(),
    }).eq('id', topId);
  }

  Future<void> deleteTop(String topId) {
    return _client.from('tops').delete().eq('id', topId);
  }

  /// Estado atual de atribuição num Top: profileId -> liberado como Hakuna.
  Future<Map<String, bool>> fetchTopHakunaAssignments(String topId) async {
    final rows = await _client.from('top_hakunas').select('profile_id, released').eq('top_id', topId);
    return {for (final r in rows) r['profile_id'] as String: r['released'] as bool};
  }

  Future<Set<String>> fetchTopSenderistaIds(String topId) async {
    final rows = await _client.from('top_senderistas').select('profile_id').eq('top_id', topId);
    return rows.map((r) => r['profile_id'] as String).toSet();
  }

  /// Libera/atribui (ou revoga) um Hakuna num Top — "delegar função".
  Future<void> setHakunaReleased({required String topId, required String profileId, required bool released}) {
    return _client.from('top_hakunas').upsert({
      'top_id': topId,
      'profile_id': profileId,
      'released': released,
    });
  }

  Future<void> removeHakunaFromTop({required String topId, required String profileId}) {
    return _client.from('top_hakunas').delete().eq('top_id', topId).eq('profile_id', profileId);
  }

  Future<void> registerSenderista({required String topId, required String profileId}) {
    return _client.from('top_senderistas').upsert({'top_id': topId, 'profile_id': profileId});
  }

  Future<void> removeSenderistaFromTop({required String topId, required String profileId}) {
    return _client.from('top_senderistas').delete().eq('top_id', topId).eq('profile_id', profileId);
  }

  /// Todas as regras de triagem (inclusive inativas) — usado na tela de
  /// edição do admin master. Leitores comuns usam
  /// SupabaseService.fetchActiveTriageRules().
  Future<List<TriageRule>> fetchAllTriageRules() async {
    final rows = await _client.from('triage_rules').select().order('priority');
    return rows.map((r) => TriageRule.fromMap(r)).toList();
  }

  /// Rejeitado pelo banco se quem chama não for o admin master.
  Future<void> updateTriageRule(TriageRule rule) {
    return _client.from('triage_rules').update({
      'label': rule.label,
      'min_age': rule.minAge,
      'max_age': rule.maxAge,
      'min_comorbidities': rule.minComorbidities,
      'max_comorbidities': rule.maxComorbidities,
      'priority': rule.priority,
      'active': rule.active,
    }).eq('id', rule.id);
  }
}
