import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../models/afericao.dart';
import '../models/participant.dart';
import '../models/participant_tag.dart';
import '../models/triage_rule.dart';
import 'local_db.dart';
import 'tabelas.dart';
import 'texto_busca.dart';

/// Acesso ao cache local — o que o app enxerga sem rede.
///
/// Camada de acesso separada da definição de esquema (`tabelas.dart`),
/// padrão emprestado do OpenTracks. Quem mexe em query não mexe em
/// migração, e vice-versa.
///
/// **Por que isto existe:** até a v1.0.16 a camada offline cobria só
/// escrita. Toda leitura ia direto ao Supabase, então em cold start no
/// mato a lista de participantes vinha vazia e a tag NFC não resolvia —
/// exatamente onde as duas coisas precisam funcionar.
class CacheLocal {
  CacheLocal._();

  static final CacheLocal instance = CacheLocal._();

  Future<Database> get _db => LocalDb.instance.database;

  // =====================================================================
  // PARTICIPANTES
  // =====================================================================

  /// Grava a lista inteira de um Top numa transação.
  ///
  /// Transação e não insert solto: se cair no meio, o aparelho fica com a
  /// lista antiga e completa em vez de meia lista nova. Meia lista é pior
  /// que lista velha — o Hakuna não sabe que está faltando gente.
  Future<int> salvarParticipantes(
    String topId,
    List<Participant> participantes,
  ) async {
    final db = await _db;
    final agora = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      // Apaga só os deste Top: outro Top cacheado continua valendo.
      await txn.delete(
        Tabelas.participantes,
        where: '${ColunasParticipante.topId} = ?',
        whereArgs: [topId],
      );

      final lote = txn.batch();
      for (final p in participantes) {
        lote.insert(Tabelas.participantes, {
          ColunasParticipante.id: p.id,
          ColunasParticipante.topId: p.topId,
          ColunasParticipante.fullName: p.fullName,
          ColunasParticipante.nickname: p.nickname,
          ColunasParticipante.familia: p.familia,
          ColunasParticipante.familiaNormalizada: TextoBusca.normalizar(
            p.familia,
          ),
          ColunasParticipante.participantCode: p.participantCode,
          ColunasParticipante.phone: p.phone,
          ColunasParticipante.birthDate: p.birthDate
              ?.toIso8601String()
              .split('T')
              .first,
          ColunasParticipante.cidade: p.cidade,
          ColunasParticipante.estado: p.estado,
          ColunasParticipante.emergencyContact: p.emergencyContact,
          ColunasParticipante.heightCm: p.heightCm,
          ColunasParticipante.weightKg: p.weightKg,
          ColunasParticipante.bloodType: p.bloodType,
          ColunasParticipante.biotipo: p.biotipo,
          ColunasParticipante.cirurgias: p.cirurgias,
          ColunasParticipante.observacaoHakuna: p.observacaoHakuna,
          ColunasParticipante.atividadeFisica: p.atividadeFisicaSemanal,
          // SQLite não tem array: o text[] do Postgres vira JSON.
          ColunasParticipante.comorbidades: jsonEncode(p.comorbidades),
          ColunasParticipante.alergias: p.alergias,
          ColunasParticipante.planoSaude: p.planoSaude,
          ColunasParticipante.medicamentos: p.medicamentosContinuos,
          ColunasParticipante.restricoes: p.restricoesFisicas,
          ColunasParticipante.tagUid: p.tagUid,
          ColunasParticipante.notes: p.notes,
          ColunasParticipante.active: p.active ? 1 : 0,
          ColunasParticipante.baixadoEm: agora,
          // Normalizado UMA vez, aqui. A busca compara contra esta coluna
          // em vez de remover acento de 215 nomes a cada tecla digitada.
          ColunasParticipante.buscaNormalizada: TextoBusca.chaveDe(
            nome: p.fullName,
            apelido: p.nickname,
            familia: p.familia,
            codigo: p.participantCode,
          ),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await lote.commit(noResult: true);
    });

    return participantes.length;
  }

  /// Participantes do Top, do cache.
  ///
  /// [termo] e [familia] filtram **no SQL**, usando os índices — não
  /// carrega tudo para depois descartar em Dart.
  Future<List<Participant>> participantes(
    String topId, {
    String? termo,
    String? familia,
  }) async {
    final db = await _db;

    final where = <String>['${ColunasParticipante.topId} = ?'];
    final args = <Object>[topId];

    final termoNorm = TextoBusca.normalizar(termo);
    if (termoNorm.isNotEmpty) {
      where.add('${ColunasParticipante.buscaNormalizada} LIKE ?');
      args.add('%$termoNorm%');
    }
    final familiaNorm = TextoBusca.normalizar(familia);
    if (familiaNorm.isNotEmpty) {
      // Contra a coluna normalizada, não contra `familia`: "aguia" tem de
      // achar "ÁGUIA".
      where.add('${ColunasParticipante.familiaNormalizada} LIKE ?');
      args.add('%$familiaNorm%');
    }

    final linhas = await db.query(
      Tabelas.participantes,
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: ColunasParticipante.fullName,
    );
    return linhas.map(_participanteDe).toList();
  }

  Future<Participant?> participante(String id) async {
    final db = await _db;
    final linhas = await db.query(
      Tabelas.participantes,
      where: '${ColunasParticipante.id} = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (linhas.isEmpty) return null;
    return _participanteDe(linhas.first);
  }

  /// Quando o cache deste Top foi baixado. Null = nunca.
  ///
  /// A tela usa para avisar "dados de 3 h atrás" em vez de fingir que
  /// estão a zero — no mato, a idade do dado é informação clínica.
  Future<DateTime?> baixadoEm(String topId) async {
    final db = await _db;
    final linhas = await db.query(
      Tabelas.participantes,
      columns: ['MAX(${ColunasParticipante.baixadoEm}) AS quando'],
      where: '${ColunasParticipante.topId} = ?',
      whereArgs: [topId],
    );
    final valor = linhas.first['quando'] as int?;
    return valor == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(valor);
  }

  Participant _participanteDe(Map<String, Object?> l) {
    return Participant.fromMap({
      'id': l[ColunasParticipante.id],
      'top_id': l[ColunasParticipante.topId],
      'full_name': l[ColunasParticipante.fullName],
      'nickname': l[ColunasParticipante.nickname],
      'familia': l[ColunasParticipante.familia],
      'participant_code': l[ColunasParticipante.participantCode],
      'phone': l[ColunasParticipante.phone],
      'birth_date': l[ColunasParticipante.birthDate],
      'cidade': l[ColunasParticipante.cidade],
      'estado': l[ColunasParticipante.estado],
      'emergency_contact': l[ColunasParticipante.emergencyContact],
      'height_cm': l[ColunasParticipante.heightCm],
      'weight_kg': l[ColunasParticipante.weightKg],
      'blood_type': l[ColunasParticipante.bloodType],
      'biotipo': l[ColunasParticipante.biotipo],
      'cirurgias': l[ColunasParticipante.cirurgias],
      'observacao_hakuna': l[ColunasParticipante.observacaoHakuna],
      'atividade_fisica_semanal': l[ColunasParticipante.atividadeFisica],
      'comorbidades': jsonDecode(
        (l[ColunasParticipante.comorbidades] as String?) ?? '[]',
      ),
      'alergias': l[ColunasParticipante.alergias],
      'plano_saude': l[ColunasParticipante.planoSaude],
      'medicamentos_continuos': l[ColunasParticipante.medicamentos],
      'restricoes_fisicas': l[ColunasParticipante.restricoes],
      'tag_uid': l[ColunasParticipante.tagUid],
      'notes': l[ColunasParticipante.notes],
      'active': (l[ColunasParticipante.active] as int? ?? 1) == 1,
    });
  }

  // =====================================================================
  // TAGS — o caminho que precisa funcionar sem rede nenhuma
  // =====================================================================

  Future<int> salvarTags(String topId, List<ParticipantTag> tags) async {
    final db = await _db;
    final agora = DateTime.now().millisecondsSinceEpoch;

    await db.transaction((txn) async {
      await txn.delete(
        Tabelas.tags,
        where: '${ColunasTag.topId} = ?',
        whereArgs: [topId],
      );
      final lote = txn.batch();
      for (final t in tags) {
        lote.insert(Tabelas.tags, {
          ColunasTag.token: t.token,
          ColunasTag.id: t.id,
          ColunasTag.participantId: t.participantId,
          ColunasTag.topId: t.topId,
          ColunasTag.status: t.status.name,
          ColunasTag.issuedAt: t.issuedAt.toIso8601String(),
          ColunasTag.baixadoEm: agora,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await lote.commit(noResult: true);
    });

    return tags.length;
  }

  /// Resolve um token lido da pulseira, **do disco**.
  ///
  /// Sem rede, sem RAM: lookup por chave primária no SQLite. É esta função
  /// que faz a leitura NFC funcionar em cold start no meio da trilha.
  ///
  /// Tag revogada é devolvida também, com o status — para a tela poder
  /// dizer "REVOGADA" em vez de "não encontrada". São coisas diferentes:
  /// uma manda conferir pelo nome, a outra manda desconfiar da pulseira.
  Future<ParticipantTag?> tagPorToken(String token) async {
    final db = await _db;
    final linhas = await db.query(
      Tabelas.tags,
      where: '${ColunasTag.token} = ?',
      whereArgs: [token],
      limit: 1,
    );
    if (linhas.isEmpty) return null;
    final l = linhas.first;
    return ParticipantTag.fromMap({
      'id': l[ColunasTag.id],
      'token': l[ColunasTag.token],
      'participant_id': l[ColunasTag.participantId],
      'top_id': l[ColunasTag.topId],
      'status': l[ColunasTag.status],
      'issued_at': l[ColunasTag.issuedAt],
    });
  }

  Future<int> totalTags(String topId) async {
    final db = await _db;
    final linhas = await db.rawQuery(
      'SELECT COUNT(*) c FROM ${Tabelas.tags} WHERE ${ColunasTag.topId} = ?',
      [topId],
    );
    return (linhas.first['c'] as int?) ?? 0;
  }

  // =====================================================================
  // REGRAS DE TRIAGEM
  // =====================================================================

  Future<void> salvarRegras(List<TriageRule> regras) async {
    final db = await _db;
    final agora = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((txn) async {
      await txn.delete(Tabelas.regrasTriagem);
      final lote = txn.batch();
      for (final r in regras) {
        lote.insert(Tabelas.regrasTriagem, {
          ColunasRegraTriagem.id: r.id,
          ColunasRegraTriagem.color: r.color.name,
          ColunasRegraTriagem.label: r.label,
          ColunasRegraTriagem.minAge: r.minAge,
          ColunasRegraTriagem.maxAge: r.maxAge,
          ColunasRegraTriagem.minComorbidities: r.minComorbidities,
          ColunasRegraTriagem.maxComorbidities: r.maxComorbidities,
          ColunasRegraTriagem.priority: r.priority,
          ColunasRegraTriagem.active: r.active ? 1 : 0,
          ColunasRegraTriagem.baixadoEm: agora,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await lote.commit(noResult: true);
    });
  }

  /// Regras ativas, já ordenadas por prioridade.
  ///
  /// A ordenação vem do índice, mas `TriageService` reordena de qualquer
  /// forma — cor de triagem não pode depender de quem consultou ter
  /// lembrado do ORDER BY.
  Future<List<TriageRule>> regras() async {
    final db = await _db;
    final linhas = await db.query(
      Tabelas.regrasTriagem,
      where: '${ColunasRegraTriagem.active} = 1',
      orderBy: ColunasRegraTriagem.priority,
    );
    return linhas
        .map(
          (l) => TriageRule.fromMap({
            'id': l[ColunasRegraTriagem.id],
            'color': l[ColunasRegraTriagem.color],
            'label': l[ColunasRegraTriagem.label],
            'min_age': l[ColunasRegraTriagem.minAge],
            'max_age': l[ColunasRegraTriagem.maxAge],
            'min_comorbidities': l[ColunasRegraTriagem.minComorbidities],
            'max_comorbidities': l[ColunasRegraTriagem.maxComorbidities],
            'priority': l[ColunasRegraTriagem.priority],
            'active': (l[ColunasRegraTriagem.active] as int? ?? 1) == 1,
          }),
        )
        .toList();
  }

  // =====================================================================
  // ÚLTIMA AFERIÇÃO — o que faz a cor de triagem reagir ao campo
  // =====================================================================

  /// Registra a aferição de um atendimento, **se for mais nova** que a que
  /// já está guardada.
  ///
  /// A comparação é por `medidoEm` e não por ordem de chegada: offline, um
  /// atendimento das 9h pode sincronizar depois do das 11h, e nesse caso a
  /// medida das 9h não pode sobrescrever a mais recente.
  ///
  /// Aferição vazia (atendimento só de observação) não apaga a anterior.
  Future<void> registrarAfericao(
    String participantId,
    String topId,
    Afericao afericao,
  ) async {
    if (afericao.vazia) return;
    final db = await _db;
    final quando = afericao.medidoEm.millisecondsSinceEpoch;

    await db.rawInsert(
      '''
      INSERT INTO ${Tabelas.ultimaAfericao} (
        ${ColunasAfericao.participantId}, ${ColunasAfericao.topId},
        ${ColunasAfericao.systolicBp}, ${ColunasAfericao.diastolicBp},
        ${ColunasAfericao.spo2}, ${ColunasAfericao.medidoEm}
      ) VALUES (?, ?, ?, ?, ?, ?)
      ON CONFLICT(${ColunasAfericao.participantId}) DO UPDATE SET
        ${ColunasAfericao.topId}       = excluded.${ColunasAfericao.topId},
        ${ColunasAfericao.systolicBp}  = excluded.${ColunasAfericao.systolicBp},
        ${ColunasAfericao.diastolicBp} = excluded.${ColunasAfericao.diastolicBp},
        ${ColunasAfericao.spo2}        = excluded.${ColunasAfericao.spo2},
        ${ColunasAfericao.medidoEm}    = excluded.${ColunasAfericao.medidoEm}
      WHERE excluded.${ColunasAfericao.medidoEm}
            > ${Tabelas.ultimaAfericao}.${ColunasAfericao.medidoEm}
      ''',
      [
        participantId,
        topId,
        afericao.systolicBp,
        afericao.diastolicBp,
        afericao.spo2,
        quando,
      ],
    );
  }

  /// Últimas aferições do Top, indexadas por participante.
  ///
  /// Um mapa e não uma consulta por pessoa: a lista precisa da cor atual de
  /// 215 participantes de uma vez, e 215 queries para pintar uma lista é o
  /// tipo de coisa que trava a rolagem num celular de campo.
  Future<Map<String, Afericao>> afericoesDoTop(String topId) async {
    final db = await _db;
    final linhas = await db.query(
      Tabelas.ultimaAfericao,
      where: '${ColunasAfericao.topId} = ?',
      whereArgs: [topId],
    );
    return {
      for (final l in linhas)
        l[ColunasAfericao.participantId] as String: _afericaoDe(l),
    };
  }

  Future<Afericao?> afericaoDe(String participantId) async {
    final db = await _db;
    final linhas = await db.query(
      Tabelas.ultimaAfericao,
      where: '${ColunasAfericao.participantId} = ?',
      whereArgs: [participantId],
      limit: 1,
    );
    if (linhas.isEmpty) return null;
    return _afericaoDe(linhas.first);
  }

  Afericao _afericaoDe(Map<String, Object?> l) => Afericao(
    systolicBp: l[ColunasAfericao.systolicBp] as int?,
    diastolicBp: l[ColunasAfericao.diastolicBp] as int?,
    spo2: l[ColunasAfericao.spo2] as int?,
    medidoEm: DateTime.fromMillisecondsSinceEpoch(
      l[ColunasAfericao.medidoEm] as int,
    ),
  );

  // =====================================================================
  // ESTADO LOCAL — intenção que sobrevive ao processo
  // =====================================================================

  /// Grava um valor. Null apaga a chave.
  Future<void> guardarEstado(String chave, String? valor) async {
    final db = await _db;
    if (valor == null) {
      await db.delete(
        Tabelas.estado,
        where: '${ColunasEstado.chave} = ?',
        whereArgs: [chave],
      );
      return;
    }
    await db.insert(Tabelas.estado, {
      ColunasEstado.chave: chave,
      ColunasEstado.valor: valor,
      ColunasEstado.gravadoEm: DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> lerEstado(String chave) async {
    final db = await _db;
    final linhas = await db.query(
      Tabelas.estado,
      columns: [ColunasEstado.valor],
      where: '${ColunasEstado.chave} = ?',
      whereArgs: [chave],
      limit: 1,
    );
    if (linhas.isEmpty) return null;
    return linhas.first[ColunasEstado.valor] as String?;
  }

  /// Apaga o cache de um Top. Usado ao sair do app em aparelho
  /// compartilhado — dado clínico não fica em celular de terceiro.
  Future<void> limparTop(String topId) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(
        Tabelas.participantes,
        where: '${ColunasParticipante.topId} = ?',
        whereArgs: [topId],
      );
      await txn.delete(
        Tabelas.tags,
        where: '${ColunasTag.topId} = ?',
        whereArgs: [topId],
      );
      await txn.delete(
        Tabelas.ultimaAfericao,
        where: '${ColunasAfericao.topId} = ?',
        whereArgs: [topId],
      );
    });
  }
}
