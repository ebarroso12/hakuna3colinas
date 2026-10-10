import 'package:flutter_test/flutter_test.dart';
import 'package:hakuna_connect/models/participant_tag.dart';
import 'package:hakuna_connect/offline/local_db.dart';
import 'package:hakuna_connect/offline/outbox.dart';
import 'package:hakuna_connect/offline/sync_service.dart';
import 'package:hakuna_connect/services/auditoria_service.dart';
import 'package:hakuna_connect/services/supabase_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Até a v1.0.17 a leitura de tag chamava o Supabase direto dentro de um
/// `try/catch` vazio: sem sinal, o catch engolia a falha e a leitura feita
/// no mato **não deixava rastro nenhum**. E `audit_log` nunca recebeu uma
/// linha. Estes testes travam as duas coisas.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    LocalDb.overridePathForTests = inMemoryDatabasePath;
    await LocalDb.instance.close();
    SyncService.instance.resetForTests();
    SupabaseService.idDeUsuarioParaTestes = 'hakuna-1';
  });

  tearDown(() async {
    SupabaseService.idDeUsuarioParaTestes = null;
    await LocalDb.instance.close();
  });

  final auditoria = AuditoriaService.instance;
  const token = 'abcdef0123456789abcdef0123456789';

  Future<List<Map<String, dynamic>>> fila(String entity) async {
    final entradas = await Outbox.instance.pending(entity: entity);
    return entradas.map((e) => e.payload).toList();
  }

  group('leitura de tag vai para a fila — online e offline', () {
    test('leitura OK gera linha em tag_leituras', () async {
      await auditoria.registrarLeituraTag(
        token: token,
        topId: 'top-1',
        resultado: ResultadoLeitura.ok,
        tinhaRede: true,
        participantId: 'p1',
        latitude: -22.9,
        longitude: -43.2,
        quando: DateTime.utc(2026, 10, 10, 12, 30),
      );

      final leituras = await fila(AuditoriaService.entityTagLeitura);
      expect(leituras.length, 1);
      final l = leituras.single;
      expect(l['token'], token);
      expect(l['lida_por'], 'hakuna-1');
      expect(l['resultado'], 'ok');
      expect(l['participant_id'], 'p1');
      expect(l['latitude'], -22.9);
      // Hora do APARELHO, não do servidor: offline a leitura acontece
      // horas antes do upload.
      expect(l['lida_em'], '2026-10-10T12:30:00.000Z');
      expect(l['client_id'], isNotNull);
    });

    test('leitura OFFLINE (semDados) também é registrada', () async {
      // Este é o caso que antes se perdia por completo.
      await auditoria.registrarLeituraTag(
        token: token,
        topId: 'top-1',
        resultado: ResultadoLeitura.semDados,
        tinhaRede: false,
      );
      final leituras = await fila(AuditoriaService.entityTagLeitura);
      expect(leituras.single['resultado'], 'semDados');
    });

    test('leitura sem fix de GPS registra latitude null, não omite', () async {
      await auditoria.registrarLeituraTag(
        token: token,
        topId: 'top-1',
        resultado: ResultadoLeitura.ok,
        tinhaRede: false,
      );
      final l = (await fila(AuditoriaService.entityTagLeitura)).single;
      expect(l.containsKey('latitude'), isTrue);
      expect(l['latitude'], isNull);
    });

    test('cada leitura tem client_id próprio', () async {
      for (var i = 0; i < 3; i++) {
        await auditoria.registrarLeituraTag(
          token: token,
          topId: 'top-1',
          resultado: ResultadoLeitura.ok,
          tinhaRede: true,
        );
      }
      final ids = (await fila(AuditoriaService.entityTagLeitura))
          .map((l) => l['client_id'])
          .toSet();
      expect(ids.length, 3, reason: 'id repetido viraria leitura engolida');
    });
  });

  group('audit_log recebe só o que merece olhar', () {
    test('tag REVOGADA apresentada gera evento de segurança', () async {
      await auditoria.registrarLeituraTag(
        token: token,
        topId: 'top-1',
        resultado: ResultadoLeitura.revogada,
        tinhaRede: true,
      );

      final eventos = await fila(AuditoriaService.entityAuditLog);
      expect(eventos.length, 1);
      final e = eventos.single;
      expect(e['action'], 'tag_revogada_apresentada');
      expect(e['entity_type'], 'participant_tag');
      expect(e['entity_id'], token);
      expect(e['actor_id'], 'hakuna-1');
      expect(e['top_id'], 'top-1');
      expect((e['metadata'] as Map)['tinha_rede'], isTrue);
    });

    test('tag desconhecida gera evento, com tinha_rede no metadata', () async {
      // `tinha_rede: false` distingue "tag inexistente" de "tag emitida
      // depois do último download deste aparelho". Sem isso, toda tag nova
      // pareceria falsificada na leitura do log.
      await auditoria.registrarLeituraTag(
        token: token,
        topId: 'top-1',
        resultado: ResultadoLeitura.desconhecida,
        tinhaRede: false,
      );
      final e = (await fila(AuditoriaService.entityAuditLog)).single;
      expect(e['action'], 'tag_desconhecida');
      expect((e['metadata'] as Map)['tinha_rede'], isFalse);
    });

    test('leitura OK NÃO vira evento de audit_log', () async {
      await auditoria.registrarLeituraTag(
        token: token,
        topId: 'top-1',
        resultado: ResultadoLeitura.ok,
        tinhaRede: true,
      );
      // Numa trilha com 215 pulseiras lidas várias vezes, duplicar toda
      // leitura nas duas tabelas é volume real na fila de um celular.
      expect(await fila(AuditoriaService.entityAuditLog), isEmpty);
      expect(await fila(AuditoriaService.entityTagLeitura), hasLength(1));
    });

    test('semDados NÃO vira evento: é estado do aparelho, não ação', () async {
      await auditoria.registrarLeituraTag(
        token: token,
        topId: 'top-1',
        resultado: ResultadoLeitura.semDados,
        tinhaRede: false,
      );
      expect(await fila(AuditoriaService.entityAuditLog), isEmpty);
      expect(await fila(AuditoriaService.entityTagLeitura), hasLength(1));
    });

    test('evento solto registra occurred_at do aparelho', () async {
      await auditoria.registrar(
        acao: AcaoAuditada.fichaAlterada,
        entityType: 'participant',
        entityId: 'p1',
        topId: 'top-1',
        metadata: {'campo': 'comorbidades'},
        quando: DateTime.utc(2026, 10, 10, 8),
      );
      final e = (await fila(AuditoriaService.entityAuditLog)).single;
      expect(e['action'], 'ficha_alterada');
      expect(e['occurred_at'], '2026-10-10T08:00:00.000Z');
    });
  });

  group('nomes de ação são um conjunto fechado', () {
    test('todo valor é snake_case e único', () {
      final valores = AcaoAuditada.values.map((a) => a.valor).toList();
      expect(valores.toSet().length, valores.length, reason: 'sem repetidos');
      for (final v in valores) {
        expect(
          v,
          matches(r'^[a-z]+(_[a-z]+)*$'),
          reason: '"$v" tem de ser snake_case: é o que vai gravado no banco',
        );
      }
    });
  });

  group('sem sessão não enfileira', () {
    test('leitura sem usuário logado não entra na fila', () async {
      // Linha sem autor seria recusada pela RLS no sync e ficaria travando
      // a fila para sempre — pior que não auditar.
      SupabaseService.idDeUsuarioParaTestes = null;
      await auditoria.registrarLeituraTag(
        token: token,
        topId: 'top-1',
        resultado: ResultadoLeitura.revogada,
        tinhaRede: true,
      );
      expect(await Outbox.instance.pendingCount(), 0);
    });

    test('registrar() sem usuário não lança', () async {
      SupabaseService.idDeUsuarioParaTestes = null;
      await expectLater(
        auditoria.registrar(
          acao: AcaoAuditada.tagEmitida,
          entityType: 'participant_tag',
        ),
        completes,
      );
    });
  });

  group('contagem de pendentes', () {
    test('soma tag_leituras e audit_log', () async {
      await auditoria.registrarLeituraTag(
        token: token,
        topId: 'top-1',
        resultado: ResultadoLeitura.revogada,
        tinhaRede: true,
      );
      // Uma leitura revogada gera DUAS entradas: a leitura e o evento.
      expect(await auditoria.pendentesDeEnvio(), 2);
    });
  });
}
