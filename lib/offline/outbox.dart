import 'dart:convert';
import 'dart:math';

import 'package:sqflite/sqflite.dart';

import 'local_db.dart';

/// Tipo de escrita pendente. Hoje só `insert` é usado: atendimento e
/// posição são append-only por decisão de produto — todo atendimento novo
/// gera um registro novo, nada é editado nem sobrescrito. Isso elimina
/// conflito de sincronização entre dois Hakunas atendendo a mesma pessoa.
enum OutboxOperation { insert, update, delete }

/// Uma escrita feita em campo, esperando o sinal voltar.
class OutboxEntry {
  final int id;
  final String entity;
  final OutboxOperation operation;
  final Map<String, dynamic> payload;

  /// Gerado no aparelho e enviado como id ao servidor. É o que torna o
  /// envio idempotente: reenviar a mesma entrada não cria duplicata.
  final String clientId;

  final String? topId;
  final DateTime createdAt;
  final int attempts;
  final DateTime? lastAttemptAt;
  final String? lastError;
  final DateTime? syncedAt;

  /// Quando o servidor recusou isto em definitivo. Null = nunca.
  final DateTime? quarantinedAt;

  /// Por que foi recusado, em português. Vai para a tela de quem resolve.
  final String? quarantineReason;

  OutboxEntry({
    required this.id,
    required this.entity,
    required this.operation,
    required this.payload,
    required this.clientId,
    required this.createdAt,
    required this.attempts,
    this.topId,
    this.lastAttemptAt,
    this.lastError,
    this.syncedAt,
    this.quarantinedAt,
    this.quarantineReason,
  });

  bool get isQuarantined => quarantinedAt != null;

  /// Esperando envio: nem subiu, nem foi recusada em definitivo.
  bool get isPending => syncedAt == null && quarantinedAt == null;

  factory OutboxEntry.fromMap(Map<String, dynamic> map) {
    return OutboxEntry(
      id: map['id'] as int,
      entity: map['entity'] as String,
      operation: OutboxOperation.values.firstWhere(
        (o) => o.name == map['operation'],
        orElse: () => OutboxOperation.insert,
      ),
      payload: jsonDecode(map['payload'] as String) as Map<String, dynamic>,
      clientId: map['client_id'] as String,
      topId: map['top_id'] as String?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      attempts: map['attempts'] as int? ?? 0,
      lastAttemptAt: map['last_attempt_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_attempt_at'] as int)
          : null,
      lastError: map['last_error'] as String?,
      syncedAt: map['synced_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['synced_at'] as int)
          : null,
      quarantinedAt: map['quarantined_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['quarantined_at'] as int)
          : null,
      quarantineReason: map['quarantine_reason'] as String?,
    );
  }
}

/// Fila de escritas offline.
///
/// Regra do app: nenhuma tela escreve direto no Supabase. Tudo passa por
/// aqui primeiro, e o [SyncService] esvazia a fila quando há sinal. É o que
/// faz um atendimento registrado no meio da trilha chegar à nuvem horas
/// depois, sem o Hakuna precisar fazer nada.
class Outbox {
  Outbox._();

  static final Outbox instance = Outbox._();

  static final _rand = Random.secure();

  /// Id único gerado no aparelho, sem depender do servidor nem de rede.
  /// Formato UUID v4.
  static String novoClientId() {
    final bytes = List<int>.generate(16, (_) => _rand.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // versão 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // variante
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  /// Enfileira uma escrita. Devolve o `client_id`, que a tela pode guardar
  /// para mostrar o registro localmente antes de ele existir no servidor.
  Future<String> enqueue({
    required String entity,
    required Map<String, dynamic> payload,
    OutboxOperation operation = OutboxOperation.insert,
    String? topId,
    String? clientId,
  }) async {
    final db = await LocalDb.instance.database;
    final id = clientId ?? novoClientId();
    await db.insert('outbox', {
      'entity': entity,
      'operation': operation.name,
      'payload': jsonEncode(payload),
      'client_id': id,
      'top_id': topId,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'attempts': 0,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    return id;
  }

  /// Enfileira **substituindo** o payload se já houver entrada pendente
  /// com o mesmo `clientId`.
  ///
  /// Existe para o que é EDITÁVEL, e só para isso. `enqueue` usa
  /// `ConflictAlgorithm.ignore` de propósito: enfileirar duas vezes o mesmo
  /// atendimento não pode criar dois registros, e o segundo pedido é
  /// descartado. Para um bloco de anotações isso é exatamente o contrário
  /// do desejado — a segunda edição seria **ignorada em silêncio** e o
  /// texto antigo subiria. Era o que o código fazia antes desta função, e
  /// o pior tipo de bug: perda de texto sem erro nenhum na tela.
  ///
  /// Só mexe em entrada PENDENTE. Se a anterior já subiu (ou está em
  /// quarentena), entra uma nova — o servidor resolve pelo `onConflict` da
  /// entidade, e a ordem FIFO garante que a última edição é a que fica.
  ///
  /// Devolve o `clientId`.
  Future<String> enqueueSubstituindo({
    required String entity,
    required Map<String, dynamic> payload,
    required String clientId,
    OutboxOperation operation = OutboxOperation.insert,
    String? topId,
  }) async {
    final db = await LocalDb.instance.database;

    // Atualiza a linha deste `client_id` em QUALQUER estado — pendente,
    // já sincronizada ou em quarentena — e a devolve para a fila.
    //
    // Pegar só as pendentes era o que o código fazia antes, e um teste
    // mostrou o buraco: `client_id` tem índice **único** nesta tabela
    // (`idx_outbox_client_id`), então, depois que o bloco subia, a linha
    // continuava ali com `synced_at` preenchido e o `enqueue` seguinte
    // caía no `ConflictAlgorithm.ignore`. Resultado: **toda edição feita
    // depois do primeiro envio era descartada em silêncio.** O mesmo tipo
    // de perda que esta função existia para evitar, uma camada adiante.
    //
    // Zerar `synced_at` é o que recoloca na fila. Zerar `quarantined_at`
    // também: o texto é outro, e a recusa anterior era do texto antigo.
    final atualizadas = await db.update(
      'outbox',
      {
        'payload': jsonEncode(payload),
        'operation': operation.name,
        'synced_at': null,
        'quarantined_at': null,
        'quarantine_reason': null,
        // Zera as tentativas: o conteúdo é outro, e o motivo da falha
        // anterior pode não valer mais para este texto.
        'attempts': 0,
        'last_error': null,
        // `created_at` novo para a entrada ir ao FIM da fila. Ela acabou
        // de ser escrita; manter a data antiga a colocaria na frente de
        // coisas registradas antes dela.
        'created_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'entity = ? AND client_id = ?',
      whereArgs: [entity, clientId],
    );
    if (atualizadas > 0) return clientId;

    return enqueue(
      entity: entity,
      payload: payload,
      operation: operation,
      topId: topId,
      clientId: clientId,
    );
  }

  /// Escritas ainda não sincronizadas, na ordem em que foram feitas.
  ///
  /// A ordem importa: a posição registrada às 9h tem que chegar antes da
  /// registrada às 10h, senão a trilha sobe embaralhada.
  /// Entradas em quarentena NÃO entram aqui: é o que impede uma recusa
  /// definitiva de travar tudo que está atrás dela na fila.
  Future<List<OutboxEntry>> pending({int limit = 200, String? entity}) async {
    final db = await LocalDb.instance.database;
    final base = 'synced_at IS NULL AND quarantined_at IS NULL';
    final rows = await db.query(
      'outbox',
      where: entity == null ? base : '$base AND entity = ?',
      whereArgs: entity == null ? null : [entity],
      orderBy: 'created_at ASC, id ASC',
      limit: limit,
    );
    return rows.map(OutboxEntry.fromMap).toList();
  }

  Future<int> pendingCount({String? entity}) async {
    final db = await LocalDb.instance.database;
    const base =
        'SELECT COUNT(*) c FROM outbox '
        'WHERE synced_at IS NULL AND quarantined_at IS NULL';
    final rows = await db.rawQuery(
      entity == null ? base : '$base AND entity = ?',
      entity == null ? null : [entity],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  /// Quantas entradas ainda NÃO chegaram ao servidor, contando as em
  /// quarentena. Diferente de [pendingCount], que ignora a quarentena —
  /// certo para "o que falta enviar", errado para "o que só existe aqui".
  Future<int> naoEnviadas({required String entity, String? topId}) async {
    final db = await LocalDb.instance.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) c FROM outbox '
      'WHERE synced_at IS NULL AND entity = ?'
      '${topId == null ? '' : ' AND top_id = ?'}',
      [entity, ?topId],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  // =====================================================================
  // QUARENTENA
  // =====================================================================

  /// Tira a entrada da fila de envio, sem apagar.
  ///
  /// Chamada quando o servidor recusa em definitivo — RLS, dado inválido,
  /// esquema incompatível. Antes disto o [SyncService] parava na entrada
  /// recusada e **relia a fila na mesma ordem**, travando atendimento, GPS,
  /// foto e auditoria atrás dela para sempre.
  ///
  /// Não apaga porque é dado que alguém escreveu: atendimento clínico ou
  /// mensagem de equipe. Quem escreveu precisa saber que não chegou.
  Future<void> quarantine(int id, String motivo) async {
    final db = await LocalDb.instance.database;
    await db.update(
      'outbox',
      {
        'quarantined_at': DateTime.now().millisecondsSinceEpoch,
        'quarantine_reason': motivo,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Entradas recusadas, mais recentes primeiro. Para a tela de diagnóstico.
  Future<List<OutboxEntry>> quarantined({int limit = 200}) async {
    final db = await LocalDb.instance.database;
    final rows = await db.query(
      'outbox',
      where: 'quarantined_at IS NOT NULL AND synced_at IS NULL',
      orderBy: 'quarantined_at DESC',
      limit: limit,
    );
    return rows.map(OutboxEntry.fromMap).toList();
  }

  Future<int> quarantinedCount() async {
    final db = await LocalDb.instance.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) c FROM outbox '
      'WHERE quarantined_at IS NOT NULL AND synced_at IS NULL',
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  /// Devolve à fila. Usado depois de a causa ser resolvida — o admin ativou
  /// o Top, liberou o Hakuna, devolveu a coordenação da equipe.
  ///
  /// Zera `attempts`: a contagem antiga não diz nada sobre a tentativa nova,
  /// e manter o número alto faria o teto do [SyncService] mandar para a
  /// quarentena de novo no primeiro tropeço de rede.
  Future<void> requeue(int id) async {
    final db = await LocalDb.instance.database;
    await db.update(
      'outbox',
      {
        'quarantined_at': null,
        'quarantine_reason': null,
        'attempts': 0,
        'last_error': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Devolve tudo à fila de uma vez. Devolve quantas voltaram.
  Future<int> requeueAll() async {
    final db = await LocalDb.instance.database;
    return db.update('outbox', {
      'quarantined_at': null,
      'quarantine_reason': null,
      'attempts': 0,
      'last_error': null,
    }, where: 'quarantined_at IS NOT NULL AND synced_at IS NULL');
  }

  /// Apaga uma entrada em quarentena. **Perde o dado.**
  ///
  /// Só por ação explícita de quem está olhando o registro: a mensagem
  /// pode ser descartável, mas um atendimento não. Por isso não existe
  /// "limpar quarentena" automático.
  Future<void> descartar(int id) async {
    final db = await LocalDb.instance.database;
    await db.delete(
      'outbox',
      where: 'id = ? AND quarantined_at IS NOT NULL',
      whereArgs: [id],
    );
  }

  /// Marca como enviada. Não apaga a linha: o histórico permite auditar o
  /// que subiu e quando, e é barato.
  Future<void> markSynced(int id) async {
    final db = await LocalDb.instance.database;
    await db.update(
      'outbox',
      {'synced_at': DateTime.now().millisecondsSinceEpoch, 'last_error': null},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Registra uma falha de envio sem perder a entrada — ela continua
  /// pendente e será tentada de novo na próxima sincronização.
  Future<void> markFailed(int id, Object error) async {
    final db = await LocalDb.instance.database;
    await db.rawUpdate(
      'UPDATE outbox SET attempts = attempts + 1, last_attempt_at = ?, '
      'last_error = ? WHERE id = ?',
      [DateTime.now().millisecondsSinceEpoch, error.toString(), id],
    );
  }

  /// Limpa entradas já sincronizadas mais antigas que [manterPor].
  /// Chamar de vez em quando para o banco do aparelho não crescer sem fim.
  Future<int> purgeSynced({
    Duration manterPor = const Duration(days: 30),
  }) async {
    final db = await LocalDb.instance.database;
    final limite = DateTime.now().subtract(manterPor).millisecondsSinceEpoch;
    // `<=` e nao `<`: com manterPor zero o limite cai no mesmo milissegundo
    // em que a entrada foi marcada como sincronizada, e `<` deixaria ela
    // para tras para sempre.
    return db.delete(
      'outbox',
      where: 'synced_at IS NOT NULL AND synced_at <= ?',
      whereArgs: [limite],
    );
  }
}
