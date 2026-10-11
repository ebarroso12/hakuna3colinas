import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'dart:async';
import 'dart:io';

import '../offline/cache_local.dart';
import '../offline/tabelas.dart';
import '../models/anotacao.dart';
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
import '../offline/falha_de_envio.dart';
import 'atendimento_service.dart';

/// Traduz os erros mais comuns de autenticação do Supabase pra mensagens
/// que fazem sentido pro usuário — sem isso ele via a exceção crua (em
/// inglês, com jargão técnico) toda vez que algo dava errado no login.
String friendlyAuthError(Object error, {bool usouNumero = false}) {
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
    // Quem digitou NUMERO nao digitou e-mail nenhum, e dizer "e-mail ou
    // senha incorretos" manda a pessoa conferir uma coisa que ela nem
    // escreveu.
    //
    // A causa real, quase sempre, e a armadilha documentada em
    // `AcessoService.identificadorParaEmail`: numero vira
    // `<numero>@legendarios.app`, e quem criou a conta com e-mail proprio
    // ou pelo Google nao tem essa conta interna. Aconteceu com o proprio
    // admin master em 11/10/2026 — numero 203460, conta no Gmail.
    //
    // O texto enuncia a REGRA, nao o caso: nao revela se aquele numero
    // existe ou nao, entao nao serve para enumerar cadastro.
    if (usouNumero) {
      return 'Número ou senha incorretos.\n\n'
          'Se o número não entrar de jeito nenhum, tente o e-mail da '
          'conta — e avise o admin, porque número tem de funcionar.';
    }
    return 'E-mail ou senha incorretos.';
  }
  if (lower.contains('email not confirmed')) {
    return 'E-mail ainda não confirmado. Confira sua caixa de entrada.';
  }
  if (lower.contains('user not found') ||
      lower.contains('signups not allowed')) {
    return 'Não encontramos essa conta.';
  }
  if (lower.contains('already registered') ||
      lower.contains('user_already_exists')) {
    return 'Esse e-mail já está cadastrado. Entre em vez de se cadastrar.';
  }
  // O cadastro falha DENTRO do trigger `handle_new_user`, que insere em
  // `profiles`. A única restrição que ele pode violar é
  // `profiles_legendarios_number_key` (o id é novo, então a chave primária
  // não colide). O GoTrue embrulha isso como "Database error saving new
  // user" — texto que não diz nada a quem está se cadastrando e some com a
  // informação útil: o número já é de outra pessoa.
  if (lower.contains('database error saving new user')) {
    return 'Esse número do Legendários já está cadastrado por outra pessoa. '
        'Confira o número; se estiver certo, fale com o administrador.';
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

  /// Id de quem está logado, ou null.
  ///
  /// Existe separado de [currentUser] por dois motivos concretos:
  ///
  /// 1. É o único dado que a camada offline (`Outbox`, `ChatRepositorio`,
  ///    `AuditoriaService`) precisa da sessão — pedir o `User` inteiro para
  ///    ler o id acopla a fila ao pacote do Supabase sem necessidade.
  /// 2. `Supabase.instance` **lança** quando `initialize` não rodou. Isso
  ///    acontece nos testes de unidade da fila, que exercitam o SQLite de
  ///    verdade sem subir o app. Aqui vira null em vez de exceção, e null
  ///    já é o caminho tratado ("sem sessão, não enfileira").
  ///
  /// Em produção `main()` inicializa antes do `runApp`, então o `catch`
  /// nunca é atingido no app rodando.
  String? get currentUserId {
    final forcado = idDeUsuarioParaTestes;
    if (forcado != null) return forcado;
    try {
      return _client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  /// Finge uma sessão nos testes da camada offline. Null em produção.
  @visibleForTesting
  static String? idDeUsuarioParaTestes;

  /// Envolve um envio da fila e classifica a falha.
  ///
  /// Sem isto, uma recusa definitiva da RLS é tratada como queda de rede e
  /// **bloqueia a fila inteira para sempre** — o [SyncService] para na
  /// primeira falha, relê a fila na mesma ordem e trava na mesma entrada.
  /// Ver [FalhaPermanente].
  ///
  /// Na dúvida, classifica como TRANSITÓRIA. Errar para "permanente"
  /// descarta dado clínico de verdade; errar para "transitória" só atrasa,
  /// e o teto de tentativas do [SyncService] é a rede de segurança para
  /// esse caso.
  Future<void> _envioDaFila(String oQue, Future<void> Function() acao) async {
    try {
      await acao();
    } on PostgrestException catch (e) {
      final motivo = _motivoPermanente(e);
      if (motivo != null) throw FalhaPermanente('$oQue: $motivo', e);
      rethrow;
    }
  }

  /// Devolve a explicação se o erro for definitivo, ou null se vale
  /// insistir.
  ///
  /// `PostgrestException.code` chega de dois jeitos: SQLSTATE do Postgres
  /// (`42501`) quando o banco recusou, ou status HTTP em texto (`403`)
  /// quando o PostgREST recusou antes. Trata os dois.
  static String? _motivoPermanente(PostgrestException e) {
    final code = e.code ?? '';

    // SQLSTATE 42501 = insufficient_privilege. É o código da RLS: a linha
    // não passou no `with check` da policy.
    if (code == '42501') {
      return 'recusado pelas permissões do servidor (RLS)';
    }
    // Classe 23 = violação de integridade. 23505 é unicidade, que no nosso
    // caso quer dizer "já subiu" — e isso é sucesso disfarçado de erro.
    if (code == '23505') return 'registro já existe no servidor';
    if (code.startsWith('23')) return 'dado recusado pelo banco ($code)';
    // Classe 22 = dado fora de domínio (texto longo demais, data inválida).
    if (code.startsWith('22')) return 'dado inválido ($code)';
    // 42xxx restante = coluna/tabela que não existe. App mais novo que o
    // banco, ou o contrário. Insistir não resolve.
    if (code.startsWith('42')) return 'esquema incompatível ($code)';

    final status = int.tryParse(code) ?? 0;
    // 408 e 429 ficam de fora: timeout e limite de taxa passam.
    if (status == 400 ||
        status == 401 ||
        status == 403 ||
        status == 404 ||
        status == 409 ||
        status == 422) {
      return 'servidor recusou ($status)';
    }

    // 5xx, rede, timeout e qualquer coisa não reconhecida: transitória.
    return null;
  }

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
    //
    // Nos dois casos o valor é o Client ID do tipo **Aplicativo da Web** —
    // é ele que o Supabase valida como audiência do idToken. Isto já estava
    // certo; não é a causa da falha no APK (ver [googleIndisponivelNoApk]).
    final googleSignIn = GoogleSignIn(
      clientId: kIsWeb ? _googleWebClientId : null,
      serverClientId: kIsWeb ? null : _googleWebClientId,
    );

    final GoogleSignInAccount? googleUser;
    try {
      googleUser = await googleSignIn.signIn();
    } on PlatformException catch (e) {
      // Sem este tratamento o usuário via a exceção crua do Android
      // ("PlatformException(sign_in_failed, com.google.android.gms.common
      // .api.ApiException: 10: , null, null)") e não tinha como saber que o
      // problema é de configuração e não dele.
      throw StateError(_erroDoGoogle(e));
    }

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

  /// Mensagem explicando o que fazer. **Nunca** devolve o erro cru.
  ///
  /// Os códigos vêm de `com.google.android.gms.common.api.ApiException`.
  static String _erroDoGoogle(PlatformException e) {
    final texto = '${e.code} ${e.message ?? ''}';

    // 10 = DEVELOPER_ERROR. No nosso caso tem uma causa específica e
    // conhecida; ver [googleIndisponivelNoApk].
    if (texto.contains('ApiException: 10') ||
        texto.contains('DEVELOPER_ERROR')) {
      return googleIndisponivelNoApk;
    }
    // 7 = NETWORK_ERROR.
    if (texto.contains('ApiException: 7')) {
      return 'Sem conexão para falar com o Google. '
          'Entre com número e senha — isso funciona offline depois do '
          'primeiro login.';
    }
    // 12500 = sem Play Services; 12501 = cancelado pelo usuário.
    if (texto.contains('ApiException: 12500')) {
      return 'Este aparelho não tem o Google Play Services necessário. '
          'Entre com número e senha.';
    }
    return 'O Google recusou o login ($texto). Entre com número e senha.';
  }

  /// Por que o login com Google NÃO funciona no APK distribuído.
  ///
  /// **Verificado em 10/10/2026, lendo os certificados dos próprios APKs:**
  ///
  /// ```
  /// legendarios1.0.18.apk  SHA-1 AB24D950BC3280D8E391943DE9FD026B32AC05AC
  /// legendarios1.0.19.apk  SHA-1 E882B41E837A8CAC67944CF168585249474CFF11
  /// ```
  ///
  /// Os dois são "Android Debug" e **são diferentes**: cada execução do
  /// GitHub Actions gera um keystore de debug novo e aleatório.
  ///
  /// O login nativo do Google exige um client OAuth do tipo *Android* no
  /// Google Cloud, registrado com o nome do pacote **mais o SHA-1 do
  /// certificado de assinatura**. Com o SHA-1 mudando a cada build, nenhum
  /// registro casa — e o plugin falha com DEVELOPER_ERROR antes de fazer
  /// qualquer chamada de rede.
  ///
  /// **Nenhuma mudança em Dart corrige isso.** `clientId`/`serverClientId`
  /// já estão certos. O que falta é assinatura **estável**: criar o
  /// keystore de produção (ver `android/app/build.gradle.kts`, que já lê
  /// `LEGENDARIOS_KEYSTORE_*`) e registrar o SHA-1 dele no Google Cloud.
  ///
  /// Enquanto isso não existir, número + senha é o caminho — e é o que
  /// funciona offline, que é o que o evento exige.
  static const googleIndisponivelNoApk =
      'Entrar com Google não está disponível nesta versão instalada por '
      'arquivo: ela é assinada com chave temporária, e o Google exige uma '
      'assinatura fixa registrada. Use seu número e a senha.';

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
    final perfil = Profile.fromMap(row);
    // Guarda o nome para o alarme poder dizer QUEM está chamando mesmo
    // disparado offline. `profiles` é fechada para quem recebe o alarme
    // (`id = auth.uid() or is_admin()`), então o nome tem de viajar DENTRO
    // do alarme — ver `AlarmeService.nomeDeQuemDispara` e
    // `supabase/alarme_para_todo_o_top.sql`.
    //
    // Grava no `CacheLocal` direto, e não via `AlarmeService`, para não
    // criar import circular: o serviço de alarme já importa este arquivo.
    //
    // Sem `await` e com o erro engolido: é escrita em disco a serviço de
    // uma função futura, e não pode atrasar nem derrubar o carregamento
    // do perfil, que é o que decide o que a tela mostra.
    unawaited(
      CacheLocal.instance
          .guardarEstado(ColunasEstado.meuNome, perfil.fullName.trim())
          .catchError((_) {}),
    );
    return perfil;
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
  /// Sobe uma posição que saiu da fila offline.
  ///
  /// `upsert onConflict: client_id` e não `insert`. Era insert puro, e isso
  /// **duplicava pontos da trilha**: o outbox reenvia quando o envio
  /// anterior falhou, e "falhou" inclui o caso em que o insert chegou e só
  /// a resposta se perdeu — o normal com sinal ruim.
  ///
  /// Duplicata aqui não é cosmética: `StatsService` soma a distância entre
  /// pontos consecutivos, então ponto repetido **infla a distância** e, com
  /// ela, a estimativa de calorias. E é a entidade de maior volume do
  /// sistema: um ponto a cada 15 m caminhados.
  Future<void> publishPosition({
    required String topId,
    required double latitude,
    required double longitude,
    String? recordedAt,
    String? clientId,
  }) {
    final uid = currentUserId;
    if (uid == null) {
      return Future.error(
        StateError('Sessão expirada — não é possível publicar posição'),
      );
    }
    return _client
        .from('hakuna_positions')
        .upsert(
          {
            'top_id': topId,
            'profile_id': uid,
            'latitude': latitude,
            'longitude': longitude,
            'recorded_at': ?recordedAt,
            'client_id': ?clientId,
          },
          onConflict: 'client_id',
          ignoreDuplicates: true,
        );
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

  /// Sobe uma mensagem de equipe que saiu da fila offline.
  ///
  /// `upsert onConflict: client_id` e não `insert`: o outbox reenvia quando
  /// o envio anterior falhou, e isso inclui o caso em que o insert chegou e
  /// só a resposta se perdeu. Com `insert`, a mesma mensagem apareceria
  /// duas vezes no chat — e duas vezes um alerta.
  ///
  /// [isAlert] só é aceito pela RLS se o remetente for admin da equipe. Um
  /// `is_alert = true` de quem não é tem a escrita **rejeitada**, e a
  /// entrada fica na fila com o erro em vez de gravar sem o destaque.
  ///
  /// Chamado pelo [SyncService], não pelas telas — quem envia é o
  /// `ChatRepositorio`.
  Future<void> enviarMensagemEquipe(Map<String, dynamic> payload) {
    return _envioDaFila('mensagem de equipe', () async {
      await _client
          .from('team_messages')
          .upsert(payload, onConflict: 'client_id', ignoreDuplicates: true);
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

  /// Cria o vinculo tag <-> participante.
  Future<ParticipantTag> criarTag({
    required String token,
    required String participantId,
    required String topId,
    String? tagUid,
  }) async {
    final uid = currentUser?.id;
    final linhas = await _client.from('participant_tags').insert({
      'token': token,
      'participant_id': participantId,
      'top_id': topId,
      'tag_uid': tagUid,
      'issued_by': uid,
    }).select();
    return ParticipantTag.fromMap(linhas.first);
  }

  Future<void> revogarTag({
    required String tagId,
    required String motivo,
  }) async {
    await _client
        .from('participant_tags')
        .update({
          'status': 'revogada',
          'revoked_by': currentUser?.id,
          'revoked_at': DateTime.now().toUtc().toIso8601String(),
          'revoked_reason': motivo,
        })
        .eq('id', tagId);
  }

  Future<void> revogarTagDoParticipante({
    required String participantId,
    required String motivo,
  }) async {
    await _client
        .from('participant_tags')
        .update({
          'status': 'revogada',
          'revoked_by': currentUser?.id,
          'revoked_at': DateTime.now().toUtc().toIso8601String(),
          'revoked_reason': motivo,
        })
        .eq('participant_id', participantId)
        .eq('status', 'ativa');
  }

  /// Historico de leituras de uma tag — a auditoria LGPD do item 4.
  Future<List<Map<String, dynamic>>> fetchLeiturasTag(String token) async {
    final linhas = await _client
        .from('tag_leituras')
        .select()
        .eq('token', token)
        .order('lida_em', ascending: false)
        .limit(100);
    return linhas.cast<Map<String, dynamic>>();
  }

  /// Registra a leitura para auditoria LGPD. Toda leitura entra, inclusive
  /// as que falham: tentativa com tag revogada e exatamente o que a
  /// auditoria precisa mostrar.
  /// Sobe uma leitura de tag que saiu da fila offline.
  ///
  /// `upsert` com `onConflict: client_id` e não `insert`: o outbox reenvia
  /// quando o envio anterior falhou, e "falhou" inclui o caso em que o
  /// insert foi aplicado e só a resposta se perdeu. Com `insert` isso
  /// gravaria a mesma leitura duas vezes, e auditoria duplicada deixa de
  /// servir para contar quantas vezes uma pulseira revogada foi apresentada.
  ///
  /// Chamado pelo [SyncService], não pelas telas — quem audita é o
  /// `AuditoriaService`, que enfileira.
  Future<void> enviarLeituraTag(Map<String, dynamic> payload) {
    return _envioDaFila('leitura de pulseira', () async {
      await _client
          .from('tag_leituras')
          .upsert(payload, onConflict: 'client_id', ignoreDuplicates: true);
    });
  }

  /// Sobe um evento de `audit_log` que saiu da fila offline.
  Future<void> enviarAuditoria(Map<String, dynamic> payload) {
    return _envioDaFila('registro de auditoria', () async {
      await _client
          .from('audit_log')
          .upsert(payload, onConflict: 'client_id', ignoreDuplicates: true);
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
  Future<void> enviarAtendimento(Map<String, dynamic> payload) {
    return _envioDaFila('atendimento', () async {
      await _client
          .from('atendimentos')
          .upsert(payload, onConflict: 'client_id', ignoreDuplicates: true);
    });
  }

  /// Aplica uma alteração num atendimento que já subiu (hoje: encerrar).
  ///
  /// Casa pelo `client_id`, não pelo `id`: offline o aparelho nunca viu o
  /// `id` que o servidor gerou.
  ///
  /// Lança quando não encontra a linha, de propósito. Significa que o
  /// atendimento ainda não subiu — a fila é FIFO, então o insert vem
  /// antes, mas ele pode estar atrasado ou em quarentena. Lançar devolve a
  /// entrada à fila; devolver sucesso em silêncio perderia o
  /// encerramento, e o atendimento ficaria aberto para sempre.
  Future<void> atualizarAtendimento(Map<String, dynamic> payload) {
    return _envioDaFila('encerramento de atendimento', () async {
      // `as String` explicito: o payload e `Map<String, dynamic>`, e com
      // `strict-casts` ligado passar `dynamic` para `.eq()` e erro. Era
      // exatamente esse tipo de passagem silenciosa que deixou um
      // `map['id'] as int` chegar perto de rodar em campo.
      final clientId = payload['client_id'] as String;
      final campos = {...payload}..remove('client_id');
      final linhas = await _client
          .from('atendimentos')
          .update(campos)
          .eq('client_id', clientId)
          .select('id');
      if (linhas.isEmpty) {
        throw StateError(
          'Atendimento $clientId ainda nao subiu; encerramento aguarda.',
        );
      }
    });
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

    // `client_id` da própria foto. Entradas antigas da fila (gravadas
    // antes da correção) não têm o campo; nesse caso cai no nome do
    // arquivo, que é como o id é gravado desde sempre — ver
    // `AtendimentoService.clientIdDaFoto`.
    final fotoClientId =
        payload['client_id'] as String? ??
        AtendimentoService.clientIdDaFoto(caminhoLocal);

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
            'client_id': fotoClientId,
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

  // `criarParticipante` e `atualizarParticipante` foram REMOVIDOS em
  // 11/10/2026. Escreviam direto no Supabase, e o formulario que os
  // chamava e aberto de duas telas de campo: salvar sem sinal falhava e a
  // ficha inteira — nome, comorbidade, alergia — era perdida.
  //
  // O caminho agora e `ParticipanteService.criar` / `.atualizar`, que grava
  // no aparelho e enfileira. Nao reintroduzir atalho daqui: o envio e
  // `enviarParticipante`, chamado pelo SyncService.

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
  ///
  /// `somenteAtivas = false` devolve também os vínculos **inativos** — não
  /// liberado e bloqueado. Eles parecem inúteis e são o oposto: sem eles a
  /// tela não distingue "você não está nesta equipe" de "você está e falta
  /// o admin te LIBERAR", que são problemas diferentes e têm soluções
  /// diferentes. `is_team_member` exige `released = true AND blocked =
  /// false` (ver `supabase/team_roles_and_triage_v2.sql:69`), então quem
  /// cai no segundo estado fica sem chat e sem bloco de anotações — e, se a
  /// tela não disser isso, sem nem saber o que pedir.
  Future<List<TeamMembership>> fetchMyTeams(
    String topId, {
    bool somenteAtivas = true,
  }) async {
    final uid = currentUser?.id;
    if (uid == null) return const [];
    final rows = await _client
        .from('top_team_members')
        .select()
        .eq('top_id', topId)
        .eq('profile_id', uid);
    final vinculos = rows.map((r) => TeamMembership.fromMap(r));
    return somenteAtivas
        ? vinculos.where((m) => m.isActive).toList()
        : vinculos.toList();
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

  /// Sobe uma mensagem do chat do Top que saiu da fila offline.
  /// Mesma razão do `upsert` em [enviarMensagemEquipe].
  Future<void> enviarMensagemTop(Map<String, dynamic> payload) {
    return _envioDaFila('mensagem do Top', () async {
      await _client
          .from('top_hakuna_messages')
          .upsert(payload, onConflict: 'client_id', ignoreDuplicates: true);
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

  /// Envio do bloco de anotações a partir da fila.
  ///
  /// `onConflict: 'bloco_id'` e **sem** `ignoreDuplicates`: o bloco é
  /// editável, então a segunda chegada do mesmo `bloco_id` tem de
  /// ATUALIZAR o texto, não ser ignorada. Com `ignoreDuplicates: true` —
  /// que é o certo para atendimento e alarme — toda edição depois da
  /// primeira seria descartada pelo servidor em silêncio.
  Future<void> enviarAnotacao(Map<String, dynamic> payload) {
    return _envioDaFila('anotação', () async {
      await _client.from('anotacoes').upsert(payload, onConflict: 'bloco_id');
    });
  }

  /// Um bloco específico, pela chave. Null quando ainda não existe.
  Future<Anotacao?> buscarBloco({required String blocoId}) async {
    final linhas = await _client
        .from('anotacoes')
        .select(
          'id, bloco_id, top_id, team, autor_id, participante_id, texto, '
          'criada_em, atualizado_em, '
          'autor:profiles!anotacoes_autor_id_fkey(full_name), '
          'participante:top_participants!anotacoes_participante_id_fkey'
          '(full_name)',
        )
        .eq('bloco_id', blocoId)
        .limit(1);
    if (linhas.isEmpty) return null;
    return Anotacao.fromMap(linhas.first);
  }

  /// Anotações de uma equipe num Top, da mais recente para a mais antiga.
  ///
  /// Traz o nome do autor e do participante por join: sem isso a lista
  /// faria uma busca por linha para mostrar quem escreveu. A RLS de
  /// `anotacoes` é que decide o que volta — membro de uma equipe não lê a
  /// de outra.
  Future<List<Anotacao>> buscarAnotacoes({
    required String topId,
    required String team,
    String? participanteId,
  }) async {
    var consulta = _client
        .from('anotacoes')
        .select(
          'id, bloco_id, top_id, team, autor_id, participante_id, texto, '
          'criada_em, atualizado_em, '
          'autor:profiles!anotacoes_autor_id_fkey(full_name), '
          'participante:top_participants!anotacoes_participante_id_fkey'
          '(full_name)',
        )
        .eq('top_id', topId)
        .eq('team', team);

    if (participanteId != null) {
      consulta = consulta.eq('participante_id', participanteId);
    }

    final linhas = await consulta
        // `atualizado_em`: o bloco e editavel, e quem coordena quer ver o
        // que mudou agora, nao o que foi criado primeiro.
        .order('atualizado_em', ascending: false)
        .limit(
      // Teto: o histórico de uma equipe num Top de 4 dias não precisa vir
      // inteiro para a tela de uma vez.
      300,
    );
    return linhas.map(Anotacao.fromMap).toList();
  }

  /// Envio de ficha de participante a partir da fila.
  ///
  /// CADASTRO e EDIÇÃO tomam caminhos diferentes, e isso não é escolha de
  /// estilo — é o que faz a edição funcionar:
  ///
  /// - **Cadastro**: `upsert(onConflict: 'id')` com o payload inteiro. Se
  ///   dois envios do mesmo cadastro chegarem (resposta perdida), o
  ///   segundo atualiza com os mesmos dados em vez de criar outra pessoa.
  ///
  /// - **Edição**: `update().eq('id', ...)`, nunca upsert. A autoria
  ///   (`registered_by`) é de quem cadastrou primeiro, não de quem editou
  ///   por último, então ela sai do corpo — e aí o upsert **não serve**:
  ///   `INSERT ... ON CONFLICT DO UPDATE` tenta o INSERT primeiro e bate
  ///   no `NOT NULL` de `registered_by`, com erro 23502, que
  ///   `_motivoPermanente` classifica como PERMANENTE. A edição iria para
  ///   quarentena e nunca subiria.
  ///
  ///   Não é hipótese: foi exatamente o que o teste no banco mostrou, e
  ///   por pouco não saiu assim. Quem editou fica registrado no
  ///   `audit_log` (ação `ficha_alterada`).
  Future<void> enviarParticipante(Map<String, dynamic> payload) {
    return _envioDaFila('ficha de participante', () async {
      // `as String` explicito: com `strict-casts` ligado, `dynamic` nao
      // passa para `.eq()`.
      final id = payload['id'] as String;
      final jaExiste = await _client
          .from('top_participants')
          .select('id')
          .eq('id', id)
          .limit(1);

      if (jaExiste.isEmpty) {
        await _client
            .from('top_participants')
            .upsert(payload, onConflict: 'id');
        return;
      }

      // Campos nulos continuam no corpo de propósito: é assim que limpar
      // um valor (apagar "alergias", por exemplo) chega ao servidor.
      final corpo = {...payload}
        ..remove('registered_by')
        // `id` e `top_id` não se alteram numa edição: mudar o Top de um
        // participante levaria o histórico clínico dele para o lugar
        // errado.
        ..remove('id')
        ..remove('top_id');

      final linhas = await _client
          .from('top_participants')
          .update(corpo)
          .eq('id', id)
          .select('id');

      if (linhas.isEmpty) {
        // Existia na consulta e não existe mais: alguém apagou o
        // participante entre as duas chamadas. Lançar devolve a entrada à
        // fila, e na próxima tentativa a consulta dirá que não existe e o
        // caminho de cadastro recria a ficha. Devolver sucesso em silêncio
        // perderia a edição.
        throw StateError(
          'Participante $id desapareceu durante a edicao; tenta de novo.',
        );
      }
    });
  }

  /// Fotos de um atendimento, como URLs assinadas e temporárias.
  ///
  /// O bucket `atendimentos` é **privado** — foto de ferida é dado
  /// clínico, e URL pública seria um prontuário aberto na internet para
  /// quem adivinhasse o caminho. Por isso cada foto vira um link assinado,
  /// válido por uma hora: tempo de sobra para olhar na tela e curto o
  /// bastante para um print do link não virar acesso permanente.
  ///
  /// Nada disto existia: as fotos subiam e **nenhuma tela as mostrava**.
  /// O Hakuna fotografava a ferida e não tinha como revê-la.
  Future<List<String>> fotosDoAtendimento(String atendimentoId) async {
    final linhas = await _client
        .from('atendimento_fotos')
        .select('storage_path, taken_at')
        .eq('atendimento_id', atendimentoId)
        .order('taken_at');

    final caminhos = linhas
        .map((r) => r['storage_path'] as String?)
        .whereType<String>()
        .toList();
    if (caminhos.isEmpty) return const [];

    // Uma chamada para todas, em vez de uma por foto: são 3 ou 4 fotos por
    // atendimento e a rede de trilha não sobra para round-trips.
    //
    // `createSignedUrlsResult` e não `createSignedUrls`: o segundo está
    // deprecado justamente porque engole caminho que não existe no bucket,
    // e aí a lista de URLs sai desalinhada da lista de fotos. Aqui a foto
    // que não está lá é simplesmente omitida — melhor faltar uma do que
    // mostrar a foto errada num prontuário.
    final resultado = await _client.storage
        .from('atendimentos')
        .createSignedUrlsResult(caminhos, 3600);
    return [
      for (final r in resultado)
        if (r case SignedUrlSuccess(:final signedUrl)) signedUrl,
    ];
  }

  /// Todos os alarmes que este usuário tem direito de ver, em tempo real.
  ///
  /// Sem `.eq('top_id', ...)` de propósito: a RLS de `top_alerts` já
  /// devolve só os Tops em que ele é Hakuna liberado. Filtrar por Top
  /// aqui é o que fazia o alarme chegar apenas a quem estivesse com
  /// AQUELE Top aberto na tela.
  Stream<List<TopAlert>> watchMeusAlarmes() {
    return _client
        .from('top_alerts')
        .stream(primaryKey: ['id'])
        .order('created_at')
        .map((rows) => rows.map((r) => TopAlert.fromMap(r)).toList());
  }

  /// Envio de alarme a partir da fila. Chamado por [AlarmeService].
  ///
  /// `upsert(onConflict: 'client_id', ignoreDuplicates: true)` e não
  /// `insert`: "falhou" inclui o caso em que o insert chegou e só a
  /// resposta se perdeu, e com `insert` o reenvio criaria um segundo
  /// alarme para o mesmo acidente.
  Future<void> enviarAlarme(Map<String, dynamic> payload) async {
    await _client
        .from('top_alerts')
        .upsert(payload, onConflict: 'client_id', ignoreDuplicates: true);
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

  /// Envio de sinais vitais a partir da fila. Chamado por
  /// [SinaisVitaisService] — nenhuma tela chama isto direto.
  Future<void> enviarSinaisVitais(Map<String, dynamic> payload) async {
    await _envioDaFila('sinais vitais', () async {
      await _client
          .from('vital_signs')
          .upsert(payload, onConflict: 'client_id', ignoreDuplicates: true);
    });
  }
}
