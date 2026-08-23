import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/hakuna_position.dart';
import '../models/profile.dart';
import '../models/top.dart';

/// Wrapper fino sobre o client do Supabase. Mantém as queries do app
/// centralizadas em um único lugar.
class SupabaseService {
  SupabaseService._();

  static final SupabaseService instance = SupabaseService._();

  SupabaseClient get _client => Supabase.instance.client;

  static Future<void> initialize({
    required String url,
    required String anonKey,
  }) {
    return Supabase.initialize(url: url, publishableKey: anonKey);
  }

  User? get currentUser => _client.auth.currentUser;

  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  Future<AuthResponse> signIn({required String email, required String password}) {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signOut() => _client.auth.signOut();

  Future<Profile> fetchMyProfile() async {
    final uid = currentUser!.id;
    final row = await _client.from('profiles').select().eq('id', uid).single();
    return Profile.fromMap(row);
  }

  /// Tops (eventos) aos quais o usuário atual está vinculado (como hakuna
  /// liberado ou senderista inscrito), respeitando a RLS do banco.
  Future<List<Top>> fetchMyTops() async {
    final rows = await _client.from('tops').select().order('starts_at', ascending: false);
    return rows.map((r) => Top.fromMap(r)).toList();
  }

  /// Registra a posição atual do Hakuna para um Top ativo.
  ///
  /// Retorna um Future com erro (em vez de lançar de forma síncrona) se a
  /// sessão tiver expirado — assim quem chama pode tratar com .catchError
  /// mesmo estando dentro de um callback de stream (ex: LocationService).
  Future<void> publishPosition({
    required String topId,
    required double latitude,
    required double longitude,
  }) {
    final uid = currentUser?.id;
    if (uid == null) {
      return Future.error(StateError('Sessão expirada — não é possível publicar posição'));
    }
    return _client.from('hakuna_positions').insert({
      'top_id': topId,
      'profile_id': uid,
      'latitude': latitude,
      'longitude': longitude,
    });
  }

  /// Perfis (nome + número do Legendários) dos Hakunas liberados num Top,
  /// indexados por id — usado pra identificar quem é quem na lista de
  /// posições (que só tem o profile_id cru).
  Future<Map<String, Profile>> fetchHakunaProfiles(String topId) async {
    final rows = await _client
        .from('top_hakunas')
        .select('profile_id, profiles(id, full_name, legendarios_number, role, phone, medical_registry)')
        .eq('top_id', topId)
        .eq('released', true);
    final map = <String, Profile>{};
    for (final row in rows) {
      final profileMap = row['profiles'] as Map<String, dynamic>?;
      if (profileMap != null) {
        final profile = Profile.fromMap(profileMap);
        map[profile.id] = profile;
      }
    }
    return map;
  }

  /// Stream em tempo real das posições dos Hakunas de um Top específico.
  /// Emite a lista completa (mais recente por hakuna) a cada mudança.
  Stream<List<HakunaPosition>> watchTopPositions(String topId) {
    return _client
        .from('hakuna_positions')
        .stream(primaryKey: ['id'])
        .eq('top_id', topId)
        .order('recorded_at')
        .map((rows) {
          // mantém apenas a posição mais recente de cada hakuna
          final latestByProfile = <String, Map<String, dynamic>>{};
          for (final row in rows) {
            latestByProfile[row['profile_id'] as String] = row;
          }
          return latestByProfile.values.map((r) => HakunaPosition.fromMap(r)).toList();
        });
  }
}
