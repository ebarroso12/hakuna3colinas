import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dart:io';

import '../models/atendimento.dart';
import '../models/chat_message.dart';
import '../models/team.dart';
import '../models/team_message.dart';
import '../models/hakuna_position.dart';
import '../models/participant.dart';
import '../models/participant_tag.dart';
import '../models/profile.dart';
import '../models/top.dart';
import '../models/top_alert.dart';
import '../models/triage_rule.dart';
import '../models/vital_signs.dart';

/// Traduz os erros mais comuns de autenticação do Supabase pra mensagens
/// que fazem sentido pro usuário — sem isso ele via a exceção crua (em
/// inglês, com jargão técnico) toda vez que algo dava errado no login.
String friendlyAuthError(Object error) {
  final message = error is AuthException ? error.message : error.toString();
  final lower = message.toLowerCase();
  if (lower.contains('email rate limit') ||
      lower.contains('rate limit') ||
      lower.contains('429')) {
    return 'Muitos e-mails pedidos em pouco tempo. Aguarde alguns minutos e tente de novo.';
  }
  if (lower.contains('invalid') &&
      (lower.contains('otp') || lower.contains('token'))) {
    return 'Código inválido ou expirado. Confira o número ou peça um código novo.';
  }
  if (lower.contains('invalid login credentials')) {
    return 'E-mail ou senha incorretos.';
  }
  if (lower.contains('email not confirmed')) {
    return 'E-mail ainda não confirmado. Confira sua caixa de entrada.';
  }
  if (lower.contains('user not found') ||
      lower.contains('signups not allowed')) {
    return 'Não encontramos essa conta.';
  }
  return message;
}

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

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  /// Cadastro de um novo participante (Senderista por padrão — um admin
  /// promove pra Hakuna depois). O trigger handle_new_user() no banco cria
  /// a linha em profiles automaticamente a partir desses metadados.
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String fullName,
    required String legendariosNumber,
    double? weightKg,
  }) {
    return _client.auth.signUp(
      email: email,
      password: password,
      data: {
        'full_name': fullName,
        'legendarios_number': legendariosNumber,
        if (weightKg != null) 'weight_kg': weightKg.toString(),
      },
    );
  }

  Future<void> signOut() => _client.auth.signOut();

  /// Client ID "Aplicativo da Web" do projeto hakuna3colinas-app no Google
  /// Cloud — usado como audiência do ID token, tanto aqui quanto na
  /// configuração do provedor Google no Supabase. Precisa também existir
  /// um client Android (mesmo projeto, com o applicationId e a assinatura
  /// do app) pra o login nativo não travar com DEVELOPER_ERROR — ver
  /// supabase/README de setup se isso ainda não tiver sido criado.
  static const _googleWebClientId =
      '1041273208236-amlguf3rdm6pp6lnpfuacc68hc0fjj5q.apps.googleusercontent.com';

  /// Login nativo com Google: pega o ID token da conta Google do aparelho
  /// e troca por uma sessão do Supabase — sem senha, sem e-mail.
  Future<void> signInWithGoogle() async {
    // No web o plugin exige `clientId`; no Android/iOS o fluxo nativo usa
    // `serverClientId` pra devolver um idToken aceito pelo Supabase. Passar
    // o parametro errado dispara `appClientId != null` / DEVELOPER_ERROR.
    final googleSignIn = GoogleSignIn(
      clientId: kIsWeb ? _googleWebClientId : null,
      serverClientId: kIsWeb ? null : _googleWebClientId,
    );
    final googleUser = await googleSignIn.signIn();
    if (googleUser == null) {
      // usuário cancelou a tela de escolha de conta — não é erro
      return;
    }
    final googleAuth = await googleUser.authentication;
    final idToken = googleAuth.idToken;
    if (idToken == null) {
      throw StateError('Não foi possível obter o token do Google.');
    }
    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
      accessToken: googleAuth.accessToken,
    );
  }

  /// Envia um código de 6 dígitos por e-mail — usado tanto pra "esqueci
  /// minha senha" quanto pra login sem senha. Não depende de link nenhum
  /// (o link de confirmação do Supabase só funciona se a URL de redirect
  /// do projeto estiver configurada, o que hoje não é o caso).
  Future<void> sendLoginCode(String email) {
    return _client.auth.signInWithOtp(email: email);
  }

  /// Confirma o código recebido por e-mail e efetiva o login.
  Future<void> verifyLoginCode({required String email, required String code}) {
    return _client.auth.verifyOTP(
      email: email,
      token: code,
      type: OtpType.email,
    );
  }

  /// Só funciona com uma sessão ativa (usuário já logado) — troca a
  /// própria senha, digitada pelo próprio usuário na tela do app.
  Future<void> updateMyPassword(String newPassword) {
    return _client.auth.updateUser(UserAttributes(password: newPassword));
  }

  Future<Profile> fetchMyProfile() async {
    final uid = currentUser!.id;
    final row = await _client.from('profiles').select().eq('id', uid).single();
    return Profile.fromMap(row);
  }

  /// Tops (eventos) aos quais o usuário atual está vinculado (como hakuna
  /// liberado ou senderista inscrito), respeitando a RLS do banco.
  Future<List<Top>> fetchMyTops() async {
    final rows = await _client
        .from('tops')
        .select()
        .order('starts_at', ascending: false);
    return rows.map((r) => Top.fromMap(r)).toList();
  }

  /// Registra a posição atual do Hakuna para um Top ativo.
  ///
  /// Retorna um Future com erro (em vez de lançar de forma síncrona) se a
  /// sessão tiver expirado — assim quem chama pode tratar com .catchError
  /// mesmo estando dentro de um callback de stream (ex: LocationService).
  /// [recordedAt] e o instante em que o GPS mediu, nao o do envio.
  ///
  /// Importa porque a posicao pode ficar horas na fila antes de subir: sem
  /// isso, uma trilha de duas horas chegaria ao banco toda carimbada com o
  /// mesmo minuto em que o sinal voltou, e a distancia percorrida sairia
  /// errada.
  Future<void> publishPosition({
    required String topId,
    required double latitude,
    required double longitude,
    String? recordedAt,
  }) {
    final uid = currentUser?.id;
    if (uid == null) {
      return Future.error(
        StateError('Sessão expirada — não é possível publicar posição'),
      );
    }
    return _client.from('hakuna_positions').insert({
      'top_id': topId,
      'profile_id': uid,
      'latitude': latitude,
      'longitude': longitude,
      'recorded_at': ?recordedAt,
    });
  }

  /// Perfis (nome + número do Legendários) dos Hakunas liberados num Top,
  /// indexados por id — usado pra identificar quem é quem na lista de
  /// posições (que só tem o profile_id cru).
  Future<Map<String, Profile>> fetchHakunaProfiles(String topId) async {
    final rows = await _client
        .from('top_hakunas')
        .select(
          'profile_id, profiles(id, full_name, legendarios_number, role, phone, medical_registry, '
          'weight_kg, is_master_admin, birth_date, comorbidities)',
        )
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

  /// Perfis dos Senderistas inscritos num Top — usado pra escolher em quem
  /// registrar sinais vitais.
  Future<List<Profile>> fetchTopSenderistaProfiles(String topId) async {
    final rows = await _client
        .from('top_senderistas')
        .select(
          'profile_id, profiles(id, full_name, legendarios_number, role, phone, medical_registry, '
          'weight_kg, is_master_admin, birth_date, comorbidities)',
        )
        .eq('top_id', topId);
    return rows
        .map((r) => r['profiles'] as Map<String, dynamic>?)
        .whereType<Map<String, dynamic>>()
        .map((m) => Profile.fromMap(m))
        .toList();
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
          return latestByProfile.values
              .map((r) => HakunaPosition.fromMap(r))
              .toList();
        });
  }

  /// Histórico completo (não só a última posição) das próprias posições do
  /// Hakuna logado num Top, em ordem cronológica — usado para calcular
  /// distância percorrida, velocidade média e gasto calórico localmente,
  /// sem depender de nenhuma API externa.
  Stream<List<HakunaPosition>> watchMyPositionHistory(String topId) {
    final uid = currentUser?.id;
    if (uid == null) return Stream.value(const []);
    return _client
        .from('hakuna_positions')
        .stream(primaryKey: ['id'])
        .eq('top_id', topId)
        .order('recorded_at')
        .map(
          (rows) => rows
              .where((r) => r['profile_id'] == uid)
              .map((r) => HakunaPosition.fromMap(r))
              .toList(),
        );
  }

  /// Chat interno dos Hakunas liberados num Top, em tempo real. Substitui a
  /// necessidade de um sistema externo (tipo Chatwoot) só pra comunicação
  /// de equipe durante o evento.
  Stream<List<ChatMessage>> watchTopMessages(String topId) {
    return _client
        .from('top_hakuna_messages')
        .stream(primaryKey: ['id'])
        .eq('top_id', topId)
        .order('created_at')
        .map((rows) => rows.map((r) => ChatMessage.fromMap(r)).toList());
  }

  /// Chat de uma equipe dentro de um Top, em tempo real.
  ///
  /// [team] = [TeamKey.geral] é o chat geral, visível para todo usuário
  /// aprovado enquanto o Top não estiver em `draft`. As outras equipes só
  /// são visíveis para quem é membro ou admin daquela equipe naquele Top.
  ///
  /// Quem impõe isso é a RLS de `team_messages`, não este método: uma
  /// equipe da qual o usuário não participa simplesmente devolve lista
  /// vazia, sem erro.
  Stream<List<TeamMessage>> watchTeamMessages({
    required String topId,
    required TeamKey team,
  }) {
    return _client
        .from('team_messages')
        .stream(primaryKey: ['id'])
        .eq('top_id', topId)
        .order('created_at')
        .map(
          (rows) => rows
              .map((r) => TeamMessage.fromMap(r))
              .where((m) => m.team == team)
              .toList(),
        );
  }

  /// Envia mensagem para o chat de uma equipe.
  ///
  /// [isAlert] só é aceito pela RLS se o remetente for admin da equipe ou
  /// admin geral — para qualquer outro, o insert é rejeitado em vez de
  /// gravar a mensagem sem o destaque.
  Future<void> sendTeamMessage({
    required String topId,
    required TeamKey team,
    required String body,
    bool isAlert = false,
  }) {
    final uid = currentUser?.id;
    if (uid == null) {
      return Future.error(
        StateError('Sessão expirada — não é possível enviar mensagem'),
      );
    }
    return _client.from('team_messages').insert({
      'top_id': topId,
      'team': team.name,
      'sender_id': uid,
      'body': body,
      'is_alert': isAlert,
    });
  }

  /// Busca a tag pelo token. Null quando o token nao existe.
  ///
  /// A RLS decide se quem pergunta pode saber: nao-autenticado e quem nao
  /// e Hakuna liberado no Top recebem lista vazia, que aqui vira o mesmo
  /// "desconhecida" de um token inventado. Isso e proposital - a resposta
  /// nao pode confirmar a existencia de um token para quem nao tem acesso.
  Future<ParticipantTag?> buscarTagPorToken(String token) async {
    final rows = await _client
        .from('participant_tags')
        .select()
        .eq('token', token)
        .limit(1);
    if (rows.isEmpty) return null;
    return ParticipantTag.fromMap(rows.first);
  }

  /// Registra a leitura para auditoria LGPD. Toda leitura entra, inclusive
  /// as que falham: tentativa com tag revogada e exatamente o que a
  /// auditoria precisa mostrar.
  Future<void> registrarLeituraTag({
    required String token,
    required String topId,
    required String resultado,
    String? participantId,
    double? latitude,
    double? longitude,
  }) async {
    final uid = currentUser?.id;
    if (uid == null) return;
    await _client.from('tag_leituras').insert({
      'token': token,
      'top_id': topId,
      'participant_id': participantId,
      'lida_por': uid,
      'resultado': resultado,
      'latitude': latitude,
      'longitude': longitude,
    });
  }

  /// Tags de um Top, para o admin gerenciar e para o app cachear antes de
  /// entrar em area sem sinal.
  Future<List<ParticipantTag>> fetchTags(String topId) async {
    final rows = await _client
        .from('participant_tags')
        .select()
        .eq('top_id', topId)
        .order('issued_at', ascending: false);
    return rows.map((r) => ParticipantTag.fromMap(r)).toList();
  }

  /// Sobe um atendimento que estava na fila offline.
  ///
  /// `upsert` por `client_id` e nao `insert`: se a rede caiu depois de o
  /// servidor ja ter gravado, reenviar nao pode criar um segundo registro
  /// no historico clinico da pessoa.
  Future<void> enviarAtendimento(Map<String, dynamic> payload) async {
    await _client
        .from('atendimentos')
        .upsert(payload, onConflict: 'client_id', ignoreDuplicates: true);
  }

  /// Sobe uma foto de atendimento: primeiro o arquivo para o Storage,
  /// depois a linha que aponta para ele.
  Future<void> enviarFotoAtendimento(Map<String, dynamic> payload) async {
    final caminhoLocal = payload['local_path'] as String?;
    final atendimentoClientId = payload['atendimento_client_id'] as String?;
    if (caminhoLocal == null || atendimentoClientId == null) return;

    final arquivo = File(caminhoLocal);
    if (!await arquivo.exists()) {
      // A foto sumiu do aparelho (usuario limpou, sistema removeu). Nao da
      // pra recuperar, e insistir deixaria a fila travada para sempre.
      return;
    }

    // Descobre o id real do atendimento pelo client_id. Se ele ainda nao
    // subiu, lanca: a entrada volta pra fila e tenta depois, ja que a
    // ordem de envio garante que o atendimento vem antes da foto.
    final linhas = await _client
        .from('atendimentos')
        .select('id')
        .eq('client_id', atendimentoClientId)
        .limit(1);
    if (linhas.isEmpty) {
      throw StateError(
        'Atendimento $atendimentoClientId ainda nao subiu; foto aguarda.',
      );
    }
    final atendimentoId = linhas.first['id'] as String;

    final nomeNoStorage =
        '${payload['top_id']}/$atendimentoClientId/${arquivo.uri.pathSegments.last}';
    await _client.storage
        .from('atendimentos')
        .upload(
          nomeNoStorage,
          arquivo,
          fileOptions: const FileOptions(upsert: true),
        );

    await _client
        .from('atendimento_fotos')
        .upsert(
          {
            'atendimento_id': atendimentoId,
            'top_id': payload['top_id'],
            'client_id': atendimentoClientId,
            'local_path': caminhoLocal,
            'storage_path': nomeNoStorage,
            'taken_by': payload['taken_by'],
            'taken_at': payload['taken_at'],
            'uploaded_at': DateTime.now().toUtc().toIso8601String(),
          },
          onConflict: 'client_id',
          ignoreDuplicates: true,
        );
  }

  /// Atendimentos de um participante, do mais recente para o mais antigo —
  /// a ordem do HISTORICO DE ATENDIMENTOS.
  Future<List<Atendimento>> fetchAtendimentos({
    required String topId,
    required String participantId,
  }) async {
    final rows = await _client
        .from('atendimentos')
        .select()
        .eq('top_id', topId)
        .eq('participant_id', participantId)
        .order('opened_at', ascending: false);
    return rows.map((r) => Atendimento.fromMap(r)).toList();
  }

  /// Participantes (Senderistas) de um Top.
  ///
  /// Baixa a lista inteira de uma vez de proposito: a busca por nome e por
  /// familia tem que funcionar no mato, sem sinal. 215 registros cabem
  /// tranquilamente na memoria, e filtrar localmente e instantaneo —
  /// enquanto uma busca por rede falharia justamente onde o app e usado.
  Future<List<Participant>> fetchParticipants(String topId) async {
    final rows = await _client
        .from('top_participants')
        .select()
        .eq('top_id', topId)
        .eq('active', true)
        .order('full_name');
    return rows.map((r) => Participant.fromMap(r)).toList();
  }

  Future<Participant?> fetchParticipant(String participantId) async {
    final rows = await _client
        .from('top_participants')
        .select()
        .eq('id', participantId)
        .limit(1);
    if (rows.isEmpty) return null;
    return Participant.fromMap(rows.first);
  }

  /// Equipes de cada participante do Top, para mostrar o icone da equipe
  /// na lista. Devolve profileId -> equipes.
  Future<Map<String, List<TeamKey>>> fetchEquipesPorPerfil(String topId) async {
    final rows = await _client
        .from('top_team_members')
        .select('profile_id, team')
        .eq('top_id', topId)
        .eq('released', true)
        .eq('blocked', false);
    final mapa = <String, List<TeamKey>>{};
    for (final row in rows) {
      final pid = row['profile_id'] as String?;
      final team = teamKeyFromString(row['team'] as String?);
      if (pid == null || team == null || team.isGeral) continue;
      mapa.putIfAbsent(pid, () => []).add(team);
    }
    return mapa;
  }

  /// Equipes em que o usuário logado participa neste Top.
  ///
  /// O chat geral não vem daqui: ele é aberto para todo aprovado, então a
  /// UI o adiciona sempre, sem depender de vínculo.
  Future<List<TeamMembership>> fetchMyTeams(String topId) async {
    final uid = currentUser?.id;
    if (uid == null) return const [];
    final rows = await _client
        .from('top_team_members')
        .select()
        .eq('top_id', topId)
        .eq('profile_id', uid);
    return rows
        .map((r) => TeamMembership.fromMap(r))
        .where((m) => m.isActive)
        .toList();
  }

  /// Membros liberados de uma equipe, para identificar quem é quem no chat.
  Future<Map<String, Profile>> fetchTeamProfiles({
    required String topId,
    required TeamKey team,
  }) async {
    final rows = await _client
        .from('top_team_members')
        .select('profile_id, profiles(*)')
        .eq('top_id', topId)
        .eq('team', team.name)
        .eq('released', true);
    final map = <String, Profile>{};
    for (final row in rows) {
      final p = row['profiles'] as Map<String, dynamic>?;
      if (p != null) {
        final profile = Profile.fromMap(p);
        map[profile.id] = profile;
      }
    }
    return map;
  }

  Future<void> sendTopMessage({required String topId, required String body}) {
    final uid = currentUser?.id;
    if (uid == null) {
      return Future.error(
        StateError('Sessão expirada — não é possível enviar mensagem'),
      );
    }
    return _client.from('top_hakuna_messages').insert({
      'top_id': topId,
      'sender_id': uid,
      'body': body,
    });
  }

  /// Sinal de alarme do Top (acidente/atendimento crítico), em tempo real.
  /// Só visível pra quem estiver com a tela do Top aberta — sem push
  /// notification neste momento.
  Stream<List<TopAlert>> watchTopAlerts(String topId) {
    return _client
        .from('top_alerts')
        .stream(primaryKey: ['id'])
        .eq('top_id', topId)
        .order('created_at', ascending: false)
        .map((rows) => rows.map((r) => TopAlert.fromMap(r)).toList());
  }

  Future<void> sendTopAlert({
    required String topId,
    String? message,
    double? latitude,
    double? longitude,
  }) {
    final uid = currentUser?.id;
    if (uid == null) {
      return Future.error(
        StateError('Sessão expirada — não é possível disparar o alarme'),
      );
    }
    return _client.from('top_alerts').insert({
      'top_id': topId,
      'sender_id': uid,
      'message': message,
      'latitude': latitude,
      'longitude': longitude,
    });
  }

  /// Regras de triagem ativas, usadas por qualquer usuário logado pra
  /// calcular a cor de um participante — a edição delas é exclusiva do
  /// admin master (AdminService).
  Future<List<TriageRule>> fetchActiveTriageRules() async {
    final rows = await _client
        .from('triage_rules')
        .select()
        .eq('active', true)
        .order('priority');
    return rows.map((r) => TriageRule.fromMap(r)).toList();
  }

  /// Sinais vitais de um participante num Top, em tempo real, do mais
  /// recente pro mais antigo.
  Stream<List<VitalSigns>> watchVitalSigns({
    required String topId,
    required String profileId,
  }) {
    return _client
        .from('vital_signs')
        .stream(primaryKey: ['id'])
        .eq('top_id', topId)
        .order('recorded_at', ascending: false)
        .map(
          (rows) => rows
              .where((r) => r['profile_id'] == profileId)
              .map((r) => VitalSigns.fromMap(r))
              .toList(),
        );
  }

  Future<void> recordVitalSigns({
    required String topId,
    required String profileId,
    int? heartRate,
    int? systolicBp,
    int? diastolicBp,
    int? spo2,
    double? temperatureC,
    int? respiratoryRate,
    String? notes,
  }) {
    final uid = currentUser?.id;
    if (uid == null) {
      return Future.error(
        StateError('Sessão expirada — não é possível registrar sinais vitais'),
      );
    }
    return _client.from('vital_signs').insert({
      'top_id': topId,
      'profile_id': profileId,
      'recorded_by': uid,
      'heart_rate': heartRate,
      'systolic_bp': systolicBp,
      'diastolic_bp': diastolicBp,
      'spo2': spo2,
      'temperature_c': temperatureC,
      'respiratory_rate': respiratoryRate,
      'notes': notes,
    });
  }
}
