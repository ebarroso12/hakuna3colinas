import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'tabelas.dart';

/// Banco SQLite local do aparelho.
///
/// Em campo o app roda sem cobertura: este banco é a fonte da verdade
/// enquanto não há sinal, e o Supabase vira o destino da sincronização em
/// vez da origem dos dados.
///
/// Escrito com `sqflite` e SQL na mão de propósito — o projeto não usa
/// geração de código em lugar nenhum (ver CLAUDE.md), e manter assim evita
/// `build_runner` no CI.
class LocalDb {
  LocalDb._();

  static final LocalDb instance = LocalDb._();

  static const _fileName = 'hakuna_offline.db';

  /// Subir este número roda as migrações em [_upgrade]. Nunca editar uma
  /// migração já publicada: adicionar a próxima.
  static const _schemaVersion = 3;

  Database? _db;

  /// Aponta para um banco em memória nos testes, sem depender de diretório
  /// do aparelho. Em produção fica null.
  static String? overridePathForTests;

  Future<Database> get database async {
    final existente = _db;
    if (existente != null) return existente;
    final aberto = await _open();
    _db = aberto;
    return aberto;
  }

  Future<Database> _open() async {
    final caminho =
        overridePathForTests ??
        p.join((await getApplicationDocumentsDirectory()).path, _fileName);
    return openDatabase(
      caminho,
      version: _schemaVersion,
      onConfigure: (db) async {
        // Sem isto o SQLite ignora as foreign keys silenciosamente.
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, version) async => _criarEsquema(db),
      onUpgrade: (db, from, to) async => _upgrade(db, from, to),
    );
  }

  Future<void> _criarEsquema(Database db) async {
    // ------------------------------------------------------------------
    // OUTBOX: fila de escritas feitas offline.
    //
    // Toda alteração que o app faz em campo entra aqui primeiro e só
    // depois vai para o Supabase. É o que garante que nada se perde
    // quando o Hakuna registra um atendimento no mato.
    // ------------------------------------------------------------------
    await db.execute('''
      CREATE TABLE outbox (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        entity          TEXT    NOT NULL,
        operation       TEXT    NOT NULL,
        payload         TEXT    NOT NULL,
        -- id gerado no aparelho; vira a chave no servidor tambem, para a
        -- mesma escrita enviada duas vezes nao virar dois registros.
        client_id       TEXT    NOT NULL,
        top_id          TEXT,
        created_at      INTEGER NOT NULL,
        attempts        INTEGER NOT NULL DEFAULT 0,
        last_attempt_at INTEGER,
        last_error      TEXT,
        synced_at       INTEGER,
        -- QUARENTENA: entrada recusada de forma definitiva pelo servidor.
        --
        -- Sai da fila de envio mas NAO e apagada: e dado clinico ou
        -- mensagem de equipe que alguem escreveu e precisa saber que nao
        -- chegou. Sem isto, uma entrada recusada pela RLS travava a fila
        -- inteira para sempre, porque o sync para no primeiro erro e rele
        -- a fila na mesma ordem.
        quarantined_at     INTEGER,
        quarantine_reason  TEXT
      )
    ''');

    // Busca a fila pendente na ordem em que foi criada. `quarantined_at`
    // entra no indice porque a consulta de pendentes exclui quarentena.
    await db.execute(
      'CREATE INDEX idx_outbox_pendente '
      'ON outbox (synced_at, quarantined_at, created_at)',
    );
    // Barra duplicata da mesma escrita, mesmo se a tela chamar duas vezes.
    await db.execute(
      'CREATE UNIQUE INDEX idx_outbox_client_id ON outbox (client_id)',
    );

    // ------------------------------------------------------------------
    // SYNC_STATE: até onde cada tabela já foi baixada do servidor.
    // Permite sincronizar só o que mudou em vez de baixar tudo sempre.
    // ------------------------------------------------------------------
    await db.execute('''
      CREATE TABLE sync_state (
        entity          TEXT PRIMARY KEY,
        last_pulled_at  INTEGER,
        last_pushed_at  INTEGER
      )
    ''');

    await _criarCacheDeLeitura(db);
  }

  /// Cache de leitura: o que o app precisa enxergar SEM rede.
  ///
  /// A v1 cobria só escrita (a fila). Faltava leitura, e por isso, em cold
  /// start no mato, a lista de participantes vinha vazia e a tag NFC não
  /// resolvia — justamente onde as duas coisas servem.
  Future<void> _criarCacheDeLeitura(Database db) async {
    await db.execute(ColunasParticipante.criar);
    for (final idx in ColunasParticipante.indices) {
      await db.execute(idx);
    }

    await db.execute(ColunasTag.criar);
    for (final idx in ColunasTag.indices) {
      await db.execute(idx);
    }

    await db.execute(ColunasRegraTriagem.criar);
    for (final idx in ColunasRegraTriagem.indices) {
      await db.execute(idx);
    }

    await db.execute(ColunasAfericao.criar);
    for (final idx in ColunasAfericao.indices) {
      await db.execute(idx);
    }

    await db.execute(ColunasEstado.criar);
  }

  /// Migrações, uma por versão. Nunca editar uma já publicada — aparelho
  /// que já rodou a versão antiga não roda de novo.
  Future<void> _upgrade(Database db, int from, int to) async {
    if (from < 2) await _criarCacheDeLeitura(db);
    if (from < 3) await _criarQuarentena(db);
  }

  /// v3: quarentena de entradas recusadas em definitivo pelo servidor.
  ///
  /// Ver o comentario em `outbox` no [_criarEsquema]. Em aparelho que ja
  /// rodou a v2 as colunas sao adicionadas e o indice de pendentes e
  /// refeito para incluir `quarantined_at`.
  Future<void> _criarQuarentena(Database db) async {
    await db.execute('ALTER TABLE outbox ADD COLUMN quarantined_at INTEGER');
    await db.execute('ALTER TABLE outbox ADD COLUMN quarantine_reason TEXT');
    await db.execute('DROP INDEX IF EXISTS idx_outbox_pendente');
    await db.execute(
      'CREATE INDEX idx_outbox_pendente '
      'ON outbox (synced_at, quarantined_at, created_at)',
    );
  }

  /// Fecha o banco. Usado nos testes entre casos.
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }
}
