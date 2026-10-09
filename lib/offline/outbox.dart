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
  });

  bool get isPending => syncedAt == null;

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

  /// Escritas ainda não sincronizadas, na ordem em que foram feitas.
  ///
  /// A ordem importa: a posição registrada às 9h tem que chegar antes da
  /// registrada às 10h, senão a trilha sobe embaralhada.
  Future<List<OutboxEntry>> pending({int limit = 200, String? entity}) async {
    final db = await LocalDb.instance.database;
    final rows = await db.query(
      'outbox',
      where: entity == null
          ? 'synced_at IS NULL'
          : 'synced_at IS NULL AND entity = ?',
      whereArgs: entity == null ? null : [entity],
      orderBy: 'created_at ASC, id ASC',
      limit: limit,
    );
    return rows.map(OutboxEntry.fromMap).toList();
  }

  Future<int> pendingCount({String? entity}) async {
    final db = await LocalDb.instance.database;
    final rows = await db.rawQuery(
      entity == null ? 'SELECT COUNT(*) c FROM outbox WHERE synced_at IS NULL' : 'SELECT COUNT(*) c FROM outbox WHERE synced_at IS NULL AND entity = ?',
      entity == null ? null : [entity],
    );
    return (rows.first['c'] as int?) ?? 0;
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
