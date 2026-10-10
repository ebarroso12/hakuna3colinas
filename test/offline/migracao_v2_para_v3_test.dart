import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legendario_connect/offline/local_db.dart';
import 'package:legendario_connect/offline/outbox.dart';
import 'package:legendario_connect/offline/tabelas.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Migração v2 → v3 num banco de ARQUIVO, com dado dentro.
///
/// Isto importa: a **v1.0.17 foi publicada com esquema v2**, então existem
/// aparelhos com esse banco. A v3 adiciona colunas com `ALTER TABLE` e
/// refaz um índice — se der errado, o app não abre, e o que se perde é
/// atendimento registrado no mato que ainda não subiu.
///
/// Em memória este teste não provaria nada: o banco nasceria direto na v3.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  /// Recria o esquema como a v2 (publicada na v1.0.17) o deixava: fila +
  /// cache de leitura, **sem** `quarantined_at`/`quarantine_reason` e com o
  /// índice antigo de pendentes.
  ///
  /// As tabelas de cache são criadas a partir das constantes de
  /// `tabelas.dart`, que não mudaram da v2 para a v3. O alvo deste teste é
  /// o `ALTER TABLE` em `outbox`, e esse DDL está escrito à mão aqui de
  /// propósito — copiado da v2, para a migração ser exercitada contra o
  /// formato real e não contra o formato atual.
  Future<void> criarBancoV2(String caminho) async {
    final db = await databaseFactory.openDatabase(
      caminho,
      options: OpenDatabaseOptions(
        version: 2,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE outbox (
              id              INTEGER PRIMARY KEY AUTOINCREMENT,
              entity          TEXT    NOT NULL,
              operation       TEXT    NOT NULL,
              payload         TEXT    NOT NULL,
              client_id       TEXT    NOT NULL,
              top_id          TEXT,
              created_at      INTEGER NOT NULL,
              attempts        INTEGER NOT NULL DEFAULT 0,
              last_attempt_at INTEGER,
              last_error      TEXT,
              synced_at       INTEGER
            )
          ''');
          await db.execute(
            'CREATE INDEX idx_outbox_pendente ON outbox (synced_at, created_at)',
          );
          await db.execute(
            'CREATE UNIQUE INDEX idx_outbox_client_id ON outbox (client_id)',
          );
          await db.execute('''
            CREATE TABLE sync_state (
              entity          TEXT PRIMARY KEY,
              last_pulled_at  INTEGER,
              last_pushed_at  INTEGER
            )
          ''');

          // Cache de leitura, que a v2 já trazia.
          for (final ddl in [
            ColunasParticipante.criar,
            ColunasTag.criar,
            ColunasRegraTriagem.criar,
            ColunasAfericao.criar,
            ColunasEstado.criar,
          ]) {
            await db.execute(ddl);
          }
          for (final idx in [
            ...ColunasParticipante.indices,
            ...ColunasTag.indices,
            ...ColunasRegraTriagem.indices,
            ...ColunasAfericao.indices,
          ]) {
            await db.execute(idx);
          }
        },
      ),
    );

    // Um atendimento registrado no mato, ainda não enviado. É este dado
    // que a migração não pode perder.
    await db.insert('outbox', {
      'entity': 'atendimentos',
      'operation': 'insert',
      'payload': '{"notes":"cefaleia no km 8","client_id":"cid-1"}',
      'client_id': 'cid-1',
      'top_id': 'top-1',
      'created_at': DateTime(2026, 10, 9, 14).millisecondsSinceEpoch,
      'attempts': 3,
      'last_error': 'sem rede',
    });
    await db.close();
  }

  test('v2 com dado dentro sobe para v3 sem perder nada', () async {
    final dir = await Directory.systemTemp.createTemp('hakuna_mig_v3');
    final arquivo = p.join(dir.path, 'hakuna_offline.db');

    try {
      await criarBancoV2(arquivo);

      // Agora o app atualizado abre o mesmo arquivo.
      await LocalDb.instance.close();
      LocalDb.overridePathForTests = arquivo;
      final db = await LocalDb.instance.database;

      expect(await db.getVersion(), 3);

      // As colunas novas existem.
      final colunas = (await db.rawQuery('PRAGMA table_info(outbox)'))
          .map((l) => l['name'] as String)
          .toSet();
      expect(colunas, containsAll(['quarantined_at', 'quarantine_reason']));

      // O atendimento continua na fila, com os campos intactos.
      final pendentes = await Outbox.instance.pending();
      expect(pendentes.length, 1);
      final e = pendentes.single;
      expect(e.entity, 'atendimentos');
      expect(e.clientId, 'cid-1');
      expect(e.attempts, 3, reason: 'contagem de tentativas preservada');
      expect(e.payload['notes'], 'cefaleia no km 8');
      expect(e.isQuarantined, isFalse);
      expect(e.quarantinedAt, isNull);

      // As tabelas da v2 (cache de leitura) também ficam disponíveis.
      final tabelas =
          (await db.rawQuery(
                "SELECT name FROM sqlite_master WHERE type='table'",
              ))
              .map((l) => l['name'] as String)
              .toSet();
      expect(
        tabelas,
        containsAll([
          'outbox',
          'sync_state',
          'cache_participantes',
          'cache_tags',
          'cache_regras_triagem',
          'cache_ultima_afericao',
          'estado_local',
        ]),
      );

      // E a quarentena funciona no banco migrado.
      await Outbox.instance.quarantine(e.id, 'teste');
      expect(await Outbox.instance.pendingCount(), 0);
      expect(await Outbox.instance.quarantinedCount(), 1);
    } finally {
      await LocalDb.instance.close();
      LocalDb.overridePathForTests = inMemoryDatabasePath;
      await dir.delete(recursive: true);
    }
  });

  test('v1 (só a fila) sobe direto para v3', () async {
    // Caminho de quem nunca instalou a v1.0.17: pula a v2 inteira.
    final dir = await Directory.systemTemp.createTemp('hakuna_mig_v1');
    final arquivo = p.join(dir.path, 'hakuna_offline.db');

    try {
      final antigo = await databaseFactory.openDatabase(
        arquivo,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute('''
              CREATE TABLE outbox (
                id              INTEGER PRIMARY KEY AUTOINCREMENT,
                entity          TEXT    NOT NULL,
                operation       TEXT    NOT NULL,
                payload         TEXT    NOT NULL,
                client_id       TEXT    NOT NULL,
                top_id          TEXT,
                created_at      INTEGER NOT NULL,
                attempts        INTEGER NOT NULL DEFAULT 0,
                last_attempt_at INTEGER,
                last_error      TEXT,
                synced_at       INTEGER
              )
            ''');
            await db.execute(
              'CREATE INDEX idx_outbox_pendente ON outbox (synced_at, created_at)',
            );
            await db.execute(
              'CREATE UNIQUE INDEX idx_outbox_client_id ON outbox (client_id)',
            );
            await db.execute('''
              CREATE TABLE sync_state (
                entity          TEXT PRIMARY KEY,
                last_pulled_at  INTEGER,
                last_pushed_at  INTEGER
              )
            ''');
          },
        ),
      );
      await antigo.close();

      await LocalDb.instance.close();
      LocalDb.overridePathForTests = arquivo;
      final db = await LocalDb.instance.database;

      expect(await db.getVersion(), 3);
      final colunas = (await db.rawQuery('PRAGMA table_info(outbox)'))
          .map((l) => l['name'] as String)
          .toSet();
      expect(colunas, contains('quarantined_at'));
      // E o cache de leitura da v2 também foi criado no caminho 1 → 3.
      final tabelas =
          (await db.rawQuery(
                "SELECT name FROM sqlite_master WHERE type='table'",
              ))
              .map((l) => l['name'] as String)
              .toSet();
      expect(tabelas, contains('cache_tags'));
    } finally {
      await LocalDb.instance.close();
      LocalDb.overridePathForTests = inMemoryDatabasePath;
      await dir.delete(recursive: true);
    }
  });
}
