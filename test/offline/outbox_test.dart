import 'package:flutter_test/flutter_test.dart';
import 'package:legendario_connect/offline/local_db.dart';
import 'package:legendario_connect/offline/outbox.dart';
import 'package:legendario_connect/offline/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  // Roda o SQLite de verdade no desktop, em memória. Não é mock: o que
  // passa aqui é o mesmo motor que roda no celular.
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    LocalDb.overridePathForTests = inMemoryDatabasePath;
    await LocalDb.instance.close();
    SyncService.instance.resetForTests();
  });

  tearDown(() async {
    await LocalDb.instance.close();
  });

  group('Outbox — enfileirar', () {
    test('escrita entra na fila como pendente', () async {
      await Outbox.instance.enqueue(
        entity: 'atendimentos',
        payload: {'notes': 'cefaleia', 'participant_id': 'p1'},
        topId: 'top-1',
      );

      final pendentes = await Outbox.instance.pending();
      expect(pendentes, hasLength(1));
      expect(pendentes.first.entity, 'atendimentos');
      expect(pendentes.first.payload['notes'], 'cefaleia');
      expect(pendentes.first.topId, 'top-1');
      expect(pendentes.first.isPending, isTrue);
      expect(pendentes.first.attempts, 0);
    });

    test('devolve um client_id usável antes de existir no servidor', () async {
      final id = await Outbox.instance.enqueue(
        entity: 'atendimentos',
        payload: {'notes': 'x'},
      );
      expect(id, isNotEmpty);
      expect(id, matches(RegExp(r'^[0-9a-f-]{36}$')));
    });

    test('client_id gerado é único em 1000 chamadas', () {
      final ids = List.generate(1000, (_) => Outbox.novoClientId()).toSet();
      expect(ids.length, 1000);
    });

    test('client_id tem o formato UUID v4', () {
      final id = Outbox.novoClientId();
      expect(id[14], '4', reason: 'versão 4');
      expect('89ab'.contains(id[19]), isTrue, reason: 'variante');
    });

    test('reenviar o MESMO client_id não cria duplicata — é o que impede dois '
        'atendimentos iguais quando a tela chama duas vezes', () async {
      const mesmoId = 'fixo-1111-2222-3333-444444444444';
      await Outbox.instance.enqueue(
        entity: 'atendimentos',
        payload: {'notes': 'primeira'},
        clientId: mesmoId,
      );
      await Outbox.instance.enqueue(
        entity: 'atendimentos',
        payload: {'notes': 'segunda'},
        clientId: mesmoId,
      );

      expect(await Outbox.instance.pendingCount(), 1);
      final pendentes = await Outbox.instance.pending();
      expect(pendentes.first.payload['notes'], 'primeira');
    });
  });

  group('Outbox — ordem', () {
    test('devolve na ordem em que foi registrado, não ao contrário', () async {
      for (final nota in ['primeiro', 'segundo', 'terceiro']) {
        await Outbox.instance.enqueue(
          entity: 'hakuna_positions',
          payload: {'nota': nota},
        );
      }

      final pendentes = await Outbox.instance.pending();
      expect(
        pendentes.map((e) => e.payload['nota']).toList(),
        ['primeiro', 'segundo', 'terceiro'],
        reason:
            'posição das 9h tem que subir antes da das 10h, '
            'senão a trilha chega embaralhada',
      );
    });

    test('filtra por entidade', () async {
      await Outbox.instance.enqueue(entity: 'atendimentos', payload: {'a': 1});
      await Outbox.instance.enqueue(
        entity: 'hakuna_positions',
        payload: {'b': 2},
      );
      await Outbox.instance.enqueue(
        entity: 'hakuna_positions',
        payload: {'c': 3},
      );

      expect(await Outbox.instance.pendingCount(entity: 'atendimentos'), 1);
      expect(await Outbox.instance.pendingCount(entity: 'hakuna_positions'), 2);
      expect(await Outbox.instance.pendingCount(), 3);
    });
  });

  group('Outbox — sincronizado e falhas', () {
    test('marcar como sincronizado tira da fila de pendentes', () async {
      await Outbox.instance.enqueue(entity: 'atendimentos', payload: {'a': 1});
      final entrada = (await Outbox.instance.pending()).first;

      await Outbox.instance.markSynced(entrada.id);

      expect(await Outbox.instance.pendingCount(), 0);
    });

    test('falha NÃO perde a entrada — ela continua pendente', () async {
      await Outbox.instance.enqueue(entity: 'atendimentos', payload: {'a': 1});
      final entrada = (await Outbox.instance.pending()).first;

      await Outbox.instance.markFailed(entrada.id, 'sem internet');

      final depois = (await Outbox.instance.pending()).first;
      expect(depois.isPending, isTrue);
      expect(depois.attempts, 1);
      expect(depois.lastError, contains('sem internet'));
      expect(depois.lastAttemptAt, isNotNull);
    });

    test('tentativas acumulam a cada falha', () async {
      await Outbox.instance.enqueue(entity: 'atendimentos', payload: {'a': 1});
      final id = (await Outbox.instance.pending()).first.id;

      for (var i = 0; i < 3; i++) {
        await Outbox.instance.markFailed(id, 'erro $i');
      }

      expect((await Outbox.instance.pending()).first.attempts, 3);
    });

    test('purge só apaga sincronizados antigos, nunca pendentes', () async {
      await Outbox.instance.enqueue(entity: 'atendimentos', payload: {'a': 1});
      await Outbox.instance.enqueue(entity: 'atendimentos', payload: {'b': 2});
      final todos = await Outbox.instance.pending();
      await Outbox.instance.markSynced(todos.first.id);

      final apagados = await Outbox.instance.purgeSynced(
        manterPor: Duration.zero,
      );

      expect(apagados, 1);
      expect(await Outbox.instance.pendingCount(), 1);
    });
  });

  group('SyncService', () {
    test('envia os pendentes e marca como sincronizados', () async {
      final enviados = <String>[];
      SyncService.instance.registerUploader('atendimentos', (entrada) async {
        enviados.add(entrada.payload['nota'] as String);
      });

      for (final nota in ['a', 'b', 'c']) {
        await Outbox.instance.enqueue(
          entity: 'atendimentos',
          payload: {'nota': nota},
        );
      }

      final relatorio = await SyncService.instance.syncNow();

      expect(enviados, ['a', 'b', 'c']);
      expect(relatorio.enviados, 3);
      expect(relatorio.aindaPendentes, 0);
      expect(relatorio.tudoCerto, isTrue);
      expect(SyncService.instance.status, SyncStatus.emDia);
    });

    test('queda de rede no meio: o que subiu fica marcado, o resto continua '
        'na fila para a próxima vez', () async {
      var chamadas = 0;
      SyncService.instance.registerUploader('atendimentos', (entrada) async {
        chamadas++;
        if (chamadas == 2) throw Exception('conexão perdida');
      });

      for (var i = 0; i < 5; i++) {
        await Outbox.instance.enqueue(
          entity: 'atendimentos',
          payload: {'i': i},
        );
      }

      final relatorio = await SyncService.instance.syncNow();

      expect(relatorio.enviados, 1);
      expect(relatorio.falharam, 1);
      expect(
        relatorio.aindaPendentes,
        4,
        reason: 'nada pode ser descartado por causa de queda de rede',
      );
      expect(SyncService.instance.status, SyncStatus.comErro);
    });

    test('entidade sem uploader fica na fila em vez de sumir', () async {
      await Outbox.instance.enqueue(
        entity: 'entidade_que_ninguem_registrou',
        payload: {'a': 1},
      );

      final relatorio = await SyncService.instance.syncNow();

      expect(relatorio.enviados, 0);
      expect(relatorio.aindaPendentes, 1);
    });

    test('a segunda chamada simultânea não reenvia tudo de novo', () async {
      var enviosFeitos = 0;
      SyncService.instance.registerUploader('atendimentos', (entrada) async {
        enviosFeitos++;
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      for (var i = 0; i < 3; i++) {
        await Outbox.instance.enqueue(
          entity: 'atendimentos',
          payload: {'i': i},
        );
      }

      final resultados = await Future.wait([
        SyncService.instance.syncNow(),
        SyncService.instance.syncNow(),
      ]);

      expect(enviosFeitos, 3, reason: 'cada entrada sobe uma vez só');
      expect(resultados.map((r) => r.enviados).reduce((a, b) => a + b), 3);
    });

    test('sincronizar com a fila vazia é inofensivo', () async {
      final relatorio = await SyncService.instance.syncNow();
      expect(relatorio.enviados, 0);
      expect(relatorio.tudoCerto, isTrue);
    });
  });

  group('cenário real: trilha de 2 horas sem sinal', () {
    test('240 posições e 3 atendimentos registrados offline sobem inteiros e '
        'na ordem quando o sinal volta', () async {
      // No mato: nada de rede, tudo vai para a fila.
      for (var minuto = 0; minuto < 120; minuto++) {
        await Outbox.instance.enqueue(
          entity: 'hakuna_positions',
          payload: {'minuto': minuto, 'lat': -20.55, 'lng': -47.41},
        );
        await Outbox.instance.enqueue(
          entity: 'hakuna_positions',
          payload: {'minuto': minuto, 'lat': -20.56, 'lng': -47.42},
        );
      }
      for (final queixa in ['cefaleia', 'torção tornozelo', 'desidratação']) {
        await Outbox.instance.enqueue(
          entity: 'atendimentos',
          payload: {'queixa': queixa},
        );
      }

      expect(await Outbox.instance.pendingCount(), 243);

      // Chegou no alojamento com wifi.
      final posicoes = <int>[];
      final atendimentos = <String>[];
      SyncService.instance.registerUploader('hakuna_positions', (e) async {
        posicoes.add(e.payload['minuto'] as int);
      });
      SyncService.instance.registerUploader('atendimentos', (e) async {
        atendimentos.add(e.payload['queixa'] as String);
      });

      final relatorio = await SyncService.instance.syncNow(lote: 500);

      expect(relatorio.enviados, 243);
      expect(relatorio.aindaPendentes, 0);
      expect(posicoes, hasLength(240));
      expect(
        posicoes,
        orderedEquals([
          for (var m = 0; m < 120; m++) ...[m, m],
        ]),
        reason: 'a trilha tem que subir na ordem cronológica',
      );
      expect(atendimentos, ['cefaleia', 'torção tornozelo', 'desidratação']);
    });
  });
}
