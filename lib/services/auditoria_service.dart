import '../models/participant_tag.dart';
import '../offline/outbox.dart';
import '../offline/sync_service.dart';
import 'supabase_service.dart';

/// Ações auditáveis. Enum em vez de string livre para o que está gravado em
/// `audit_log.action` ser um conjunto fechado — auditoria com `action` que
/// ninguém sabe de onde veio não serve para auditar.
enum AcaoAuditada {
  /// Pulseira revogada foi apresentada. É o evento que mais importa aqui:
  /// pode ser pulseira perdida em uso por outra pessoa.
  tagRevogadaApresentada,

  /// Token legível que o aparelho não conhece. Pode ser tag de outro
  /// evento, tag falsificada, ou simplesmente emitida depois do último
  /// download — e é por isso que o metadata guarda se havia rede.
  tagDesconhecida,

  /// Emissão de pulseira nova para um participante.
  tagEmitida,

  /// Revogação de pulseira.
  tagRevogada,

  /// Ficha clínica criada ou alterada.
  fichaAlterada;

  String get valor => switch (this) {
    AcaoAuditada.tagRevogadaApresentada => 'tag_revogada_apresentada',
    AcaoAuditada.tagDesconhecida => 'tag_desconhecida',
    AcaoAuditada.tagEmitida => 'tag_emitida',
    AcaoAuditada.tagRevogada => 'tag_revogada',
    AcaoAuditada.fichaAlterada => 'ficha_alterada',
  };
}

/// Auditoria que funciona sem rede.
///
/// **O que estava errado até a v1.0.17:** a leitura de tag chamava o
/// Supabase direto, dentro de um `try/catch` vazio. Com sinal, gravava em
/// `tag_leituras`. Sem sinal, o `catch` engolia a falha e a leitura **não
/// deixava rastro nenhum** — justamente a leitura feita no mato, que é a
/// que mais interessa auditar. E `audit_log` nunca recebeu uma linha.
///
/// Agora toda auditoria entra na fila local primeiro, igual a atendimento e
/// posição, e sobe quando houver sinal.
///
/// **Duas tabelas, de propósito:**
///
/// - `tag_leituras` recebe **toda** leitura, inclusive as que falham. É a
///   tabela feita para isso: tem token, resultado, lat/long. Serve para
///   responder "quem foi identificado, quando e onde".
/// - `audit_log` recebe o **subconjunto relevante para segurança**: tag
///   revogada apresentada, tag desconhecida, emissão/revogação, alteração
///   de ficha. Serve para responder "o que alguém fez que merece olhar".
///
/// Mandar toda leitura para as duas dobraria a escrita sem responder nada
/// de novo — numa trilha com 215 pulseiras lidas várias vezes, isso é
/// volume real na fila de um celular.
class AuditoriaService {
  AuditoriaService._();

  static final AuditoriaService instance = AuditoriaService._();

  static const entityTagLeitura = 'tag_leituras';
  static const entityAuditLog = 'audit_log';

  /// Liga os envios à fila. Chamar uma vez, na subida do app.
  void registrarUploaders() {
    SyncService.instance.registerUploader(entityTagLeitura, (entrada) async {
      await SupabaseService.instance.enviarLeituraTag(entrada.payload);
    });
    SyncService.instance.registerUploader(entityAuditLog, (entrada) async {
      await SupabaseService.instance.enviarAuditoria(entrada.payload);
    });
  }

  /// Registra uma leitura de pulseira. **Nunca lança.**
  ///
  /// Auditoria não pode derrubar o atendimento: o Hakuna está com a
  /// pulseira na mão e uma pessoa na frente. Se falhar até a gravação na
  /// fila local, a identificação segue valendo e o que se perde é o
  /// rastro — nessa ordem de prioridade, e não na inversa.
  Future<void> registrarLeituraTag({
    required String token,
    required String topId,
    required ResultadoLeitura resultado,
    required bool tinhaRede,
    String? participantId,
    double? latitude,
    double? longitude,
    DateTime? quando,
  }) async {
    final actorId = SupabaseService.instance.currentUserId;
    // Sem sessão não há o que auditar: `lida_por` é quem leu, e a RLS exige
    // que seja o próprio usuário. Uma linha sem autor seria rejeitada no
    // sync e ficaria travando a fila para sempre.
    if (actorId == null) return;

    final momento = quando ?? DateTime.now();
    // Gerado aqui e colocado DENTRO do payload: é ele que o `upsert`
    // usa como `onConflict`. O outbox também guarda o id na própria linha,
    // mas o servidor só vê o que está no payload.
    final clientId = Outbox.novoClientId();

    try {
      await Outbox.instance.enqueue(
        entity: entityTagLeitura,
        topId: topId,
        clientId: clientId,
        payload: {
          'client_id': clientId,
          'token': token,
          'top_id': topId,
          'participant_id': participantId,
          'lida_por': actorId,
          'resultado': resultado.paraAuditoria,
          'latitude': latitude,
          'longitude': longitude,
          // Hora do APARELHO, não do servidor. Offline a leitura acontece
          // horas antes do upload, e `now()` no Postgres registraria o
          // instante do sync — auditoria com hora errada é pior que sem
          // hora, porque passa uma precisão que não tem.
          'lida_em': momento.toUtc().toIso8601String(),
        },
      );
    } catch (_) {
      return;
    }

    // Só o que merece olhar vai para o audit_log.
    final acao = switch (resultado) {
      ResultadoLeitura.revogada => AcaoAuditada.tagRevogadaApresentada,
      ResultadoLeitura.desconhecida => AcaoAuditada.tagDesconhecida,
      // `semDados` não entra: significa "este aparelho não sabe", que é
      // estado do aparelho e não ação de ninguém. Fica em `tag_leituras`.
      _ => null,
    };
    if (acao == null) return;

    await registrar(
      acao: acao,
      entityType: 'participant_tag',
      entityId: token,
      topId: topId,
      quando: momento,
      metadata: {
        'resultado': resultado.paraAuditoria,
        'participant_id': participantId,
        // Distingue "tag inexistente" de "tag que este aparelho ainda não
        // baixou". Sem isso, toda tag emitida depois do último download
        // viraria suspeita de falsificação na leitura do log.
        'tinha_rede': tinhaRede,
        // Null explícito em vez de chave ausente: `latitude: null` diz
        // "leu sem fix de GPS", que é diferente de "o app não registra
        // posição". Na leitura do log isso distingue aparelho sem sinal de
        // GPS de versão antiga do app.
        'latitude': latitude,
        'longitude': longitude,
      },
    );
  }

  /// Registra um evento em `audit_log`. **Nunca lança**, pelo mesmo motivo.
  Future<void> registrar({
    required AcaoAuditada acao,
    required String entityType,
    String? entityId,
    String? topId,
    Map<String, dynamic> metadata = const {},
    DateTime? quando,
  }) async {
    final actorId = SupabaseService.instance.currentUserId;
    if (actorId == null) return;

    final clientId = Outbox.novoClientId();
    try {
      await Outbox.instance.enqueue(
        entity: entityAuditLog,
        topId: topId,
        clientId: clientId,
        payload: {
          'client_id': clientId,
          'actor_id': actorId,
          'action': acao.valor,
          'entity_type': entityType,
          'entity_id': entityId,
          'top_id': topId,
          'metadata': metadata,
          'occurred_at': (quando ?? DateTime.now()).toUtc().toIso8601String(),
        },
      );
    } catch (_) {
      // Engolido de propósito e só aqui: ver a doc da classe.
    }
  }

  /// Quantos registros de auditoria ainda não subiram. A tela de admin
  /// mostra isso — auditoria pendente há dias é sinal de aparelho que não
  /// voltou a ter sinal, não de auditoria vazia.
  Future<int> pendentesDeEnvio() async {
    final leituras = await Outbox.instance.pendingCount(
      entity: entityTagLeitura,
    );
    final eventos = await Outbox.instance.pendingCount(entity: entityAuditLog);
    return leituras + eventos;
  }
}
