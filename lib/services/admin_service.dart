import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile.dart';
import '../models/team.dart';
import '../models/team_message.dart';
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
    return _client
        .from('profiles')
        .update({'role': role.name})
        .eq('id', profileId);
  }

  /// Libera o acesso de um cadastro pendente — sem isso o usuário fica
  /// preso na tela de "aguardando aprovação" pra sempre.
  Future<void> approveProfile(String profileId) => setApproved(profileId, true);

  /// Libera ou revoga o acesso de um usuário.
  Future<void> setApproved(String profileId, bool approved) {
    return _client
        .from('profiles')
        .update({'approved': approved})
        .eq('id', profileId);
  }

  /// Dados usados na triagem por cor. Qualquer admin pode editar (só o
  /// papel 'admin' e a flag de admin master são exclusivos do admin master).
  Future<void> updateProfileTriageInfo(
    String profileId, {
    DateTime? birthDate,
    required List<String> comorbidities,
  }) {
    return _client
        .from('profiles')
        .update({
          'birth_date': birthDate?.toIso8601String().split('T').first,
          'comorbidities': comorbidities,
        })
        .eq('id', profileId);
  }

  /// Rejeitado pelo banco se [profileId] for o admin master.
  Future<void> deleteProfile(String profileId) {
    return _client.from('profiles').delete().eq('id', profileId);
  }

  Future<Top> createTop({
    required String name,
    String? topNumber,
    String? location,
    String? cidade,
    String? diretorResponsavel,
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
          'cidade': cidade,
          'diretor_responsavel': diretorResponsavel,
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
    String? cidade,
    String? diretorResponsavel,
    String? description,
    required TopStatus status,
    DateTime? startsAt,
    DateTime? endsAt,
  }) {
    return _client
        .from('tops')
        .update({
          'name': name,
          'top_number': topNumber,
          'location': location,
          'cidade': cidade,
          'diretor_responsavel': diretorResponsavel,
          'description': description,
          'status': status.name,
          'starts_at': startsAt?.toIso8601String(),
          'ends_at': endsAt?.toIso8601String(),
        })
        .eq('id', topId);
  }

  /// Sobe o emblema da pista pro Storage e devolve o caminho.
  ///
  /// Guarda o CAMINHO na tabela, nao a imagem: blob em coluna faria a
  /// listagem de Tops baixar megabytes a toa.
  Future<String> uploadEmblema({
    required String topId,
    required Uint8List bytes,
    required String extensao,
  }) async {
    final caminho = 'tops/$topId/emblema$extensao';
    await _client.storage
        .from('emblemas')
        .uploadBinary(
          caminho,
          bytes,
          fileOptions: const FileOptions(upsert: true),
        );
    await _client
        .from('tops')
        .update({'emblema_path': caminho})
        .eq('id', topId);
    return caminho;
  }

  /// URL publica do emblema. Null quando o Top nao tem um.
  String? urlEmblema(String? caminho) {
    if (caminho == null || caminho.isEmpty) return null;
    return _client.storage.from('emblemas').getPublicUrl(caminho);
  }

  Future<void> deleteTop(String topId) {
    return _client.from('tops').delete().eq('id', topId);
  }

  /// Estado atual de atribuição num Top: profileId -> liberado como Hakuna.
  Future<Map<String, bool>> fetchTopHakunaAssignments(String topId) async {
    final rows = await _client
        .from('top_hakunas')
        .select('profile_id, released')
        .eq('top_id', topId);
    return {
      for (final r in rows) r['profile_id'] as String: r['released'] as bool,
    };
  }

  Future<Set<String>> fetchTopSenderistaIds(String topId) async {
    final rows = await _client
        .from('top_senderistas')
        .select('profile_id')
        .eq('top_id', topId);
    return rows.map((r) => r['profile_id'] as String).toSet();
  }

  /// Libera/atribui (ou revoga) um Hakuna num Top — "delegar função".
  Future<void> setHakunaReleased({
    required String topId,
    required String profileId,
    required bool released,
  }) {
    return _client.from('top_hakunas').upsert({
      'top_id': topId,
      'profile_id': profileId,
      'released': released,
    });
  }

  Future<void> removeHakunaFromTop({
    required String topId,
    required String profileId,
  }) {
    return _client
        .from('top_hakunas')
        .delete()
        .eq('top_id', topId)
        .eq('profile_id', profileId);
  }

  Future<void> registerSenderista({
    required String topId,
    required String profileId,
  }) {
    return _client.from('top_senderistas').upsert({
      'top_id': topId,
      'profile_id': profileId,
    });
  }

  Future<void> removeSenderistaFromTop({
    required String topId,
    required String profileId,
  }) {
    return _client
        .from('top_senderistas')
        .delete()
        .eq('top_id', topId)
        .eq('profile_id', profileId);
  }

  /// Todas as regras de triagem (inclusive inativas) — usado na tela de
  /// edição do admin master. Leitores comuns usam
  /// SupabaseService.fetchActiveTriageRules().
  // --- Equipes do Top ------------------------------------------------

  /// Todos os vinculos de equipe de um Top.
  ///
  /// Quem pode ver o que e decidido pela RLS: admin ve tudo, coordenador ve
  /// a propria equipe. Esta consulta nao filtra - deixa o banco filtrar.
  Future<List<TeamMembership>> fetchTeamMembers(String topId) async {
    final rows = await _client
        .from('top_team_members')
        .select()
        .eq('top_id', topId);
    return rows.map((r) => TeamMembership.fromMap(r)).toList();
  }

  /// Inclui alguem numa equipe.
  ///
  /// [papel] diferente de `membro` so passa se quem chama for admin - a
  /// policy de INSERT exige isso. Coordenador inclui membro, nao cria
  /// outro coordenador.
  Future<void> addTeamMember({
    required String topId,
    required TeamKey team,
    required String profileId,
    TeamRole papel = TeamRole.membro,
    bool released = true,
  }) {
    return _client.from('top_team_members').insert({
      'top_id': topId,
      'team': team.name,
      'profile_id': profileId,
      'team_role': papel.name,
      'released': released,
      'blocked': false,
    });
  }

  /// Muda o papel de alguem dentro da equipe.
  ///
  /// Promover a coordenador/subcoordenador e exclusivo do admin: a policy
  /// de UPDATE recusa de qualquer outro, mesmo do coordenador da equipe.
  Future<void> setTeamRole({
    required int membershipId,
    required TeamRole papel,
  }) {
    return _client
        .from('top_team_members')
        .update({'team_role': papel.name})
        .eq('id', membershipId);
  }

  Future<void> setTeamReleased({
    required int membershipId,
    required bool released,
  }) {
    return _client
        .from('top_team_members')
        .update({'released': released})
        .eq('id', membershipId);
  }

  /// Bloqueia sem remover: o historico de quem passou pela equipe fica, e
  /// o bloqueado perde acesso ao chat na hora.
  Future<void> setTeamBlocked({
    required int membershipId,
    required bool blocked,
  }) {
    return _client
        .from('top_team_members')
        .update({'blocked': blocked})
        .eq('id', membershipId);
  }

  /// Remove de vez. So coordenador ou admin - subcoordenador nao remove.
  Future<void> removeTeamMember(int membershipId) {
    return _client.from('top_team_members').delete().eq('id', membershipId);
  }

  Future<List<TriageRule>> fetchAllTriageRules() async {
    final rows = await _client.from('triage_rules').select().order('priority');
    return rows.map((r) => TriageRule.fromMap(r)).toList();
  }

  /// Rejeitado pelo banco se quem chama não for o admin master.
  Future<void> updateTriageRule(TriageRule rule) {
    return _client
        .from('triage_rules')
        .update({
          'label': rule.label,
          'min_age': rule.minAge,
          'max_age': rule.maxAge,
          'min_comorbidities': rule.minComorbidities,
          'max_comorbidities': rule.maxComorbidities,
          'priority': rule.priority,
          'active': rule.active,
        })
        .eq('id', rule.id);
  }
}
