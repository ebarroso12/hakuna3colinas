import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legendario_connect/offline/falha_de_envio.dart';
import 'package:legendario_connect/offline/local_db.dart';
import 'package:legendario_connect/offline/outbox.dart';
import 'package:legendario_connect/offline/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// O bug que estes testes travam:
///
/// `SyncService.syncNow` para no primeiro erro — certo para queda de rede.
/// Mas se a entrada da frente for recusada em definitivo (RLS), parar
/// significa bloquear a fila inteira **para sempre**: a próxima rodada relê
/// a fila na mesma ordem e trava na mesma entrada. Atendimento, GPS, foto e
/// auditoria ficam presos atrás de uma mensagem de chat.
///
/// Não é hipótese: o Top 1782 está em `draft`, e a RLS de `team_messages`
/// recusa mensagem no chat geral enquanto o Top for draft.
void main() {
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

  Future<void> enfileirar(String entity, String corpo) =>
      Outbox.instance.enqueue(
        entity: entity,
        topId: 'top-1',
        payload: {'body': corpo},
      );

  group('entrada recusada em definitivo NÃO trava a fila', () {
    test('a mensagem recusada sai e o atendimento atrás dela sobe', () async {
      // Ordem é a da vida real: a mensagem foi escrita primeiro.
      await enfileirar('team_messages', 'chat com Top em draft');
      await enfileirar('atendimentos', 'cefaleia no km 8');
      await enfileirar('hakuna_positions', 'ponto');

      final subiram = <String>[];
      SyncService.instance.registerUploader('team_messages', (e) async {
        throw const FalhaPermanente(
          'mensagem de equipe: recusado pelas permissões do servidor (RLS)',
          'PostgrestException 42501',
        );
      });
      SyncService.instance.registerUploader('atendimentos', (e) async {
        subiram.add('atendimento');
      });
      SyncService.instance.registerUploader('hakuna_positions', (e) async {
        subiram.add('posicao');
      });

      final r = await SyncService.instance.syncNow();

      expect(
        subiram,
        ['atendimento', 'posicao'],
        reason: 'o que estava atrás da recusada TEM de subir',
      );
      expect(r.quarentenados, 1);
      expect(r.enviados, 2);
      expect(r.aindaPendentes, 0);
    });

    test('a recusada vai para quarentena com o motivo legível', () async {
      await enfileirar('team_messages', 'alerta sem ser coordenador');
      SyncService.instance.registerUploader('team_messages', (e) async {
        throw const FalhaPermanente(
          'mensagem de equipe: recusado pelas permissões do servidor (RLS)',
          'x',
        );
      });

      await SyncService.instance.syncNow();

      final recusadas = await Outbox.instance.quarantined();
      expect(recusadas.length, 1);
      expect(recusadas.single.quarantineReason, contains('RLS'));
      expect(recusadas.single.isQuarantined, isTrue);
      expect(recusadas.single.isPending, isFalse);
    });

    test('quarentena não é apagada — o dado continua no aparelho', () async {
      await enfileirar('atendimentos', 'registro clínico recusado');
      SyncService.instance.registerUploader('atendimentos', (e) async {
        throw const FalhaPermanente('atendimento: dado inválido (22007)', 'x');
      });
      await SyncService.instance.syncNow();

      final recusadas = await Outbox.instance.quarantined();
      // Atendimento é dado clínico: não desaparece por decisão do sistema.
      expect(recusadas.single.payload['body'], 'registro clínico recusado');
    });

    test('a rodada seguinte não tenta de novo a quarentenada', () async {
      await enfileirar('team_messages', 'recusada');
      var tentativas = 0;
      SyncService.instance.registerUploader('team_messages', (e) async {
        tentativas++;
        throw const FalhaPermanente('recusada', 'x');
      });

      await SyncService.instance.syncNow();
      await SyncService.instance.syncNow();
      await SyncService.instance.syncNow();

      expect(tentativas, 1, reason: 'insistir no definitivo é desperdício');
    });
  });

  group('erro transitório continua parando a fila (de propósito)', () {
    test('queda de rede para na primeira e não quarentena', () async {
      await enfileirar('atendimentos', 'um');
      await enfileirar('atendimentos', 'dois');

      var tentativas = 0;
      SyncService.instance.registerUploader('atendimentos', (e) async {
        tentativas++;
        throw const SocketException('sem rota para o host');
      });

      final r = await SyncService.instance.syncNow();

      expect(
        tentativas,
        1,
        reason: 'insistir nas outras 199 só queima bateria',
      );
      expect(r.falharam, 1);
      expect(r.quarentenados, 0);
      expect(r.aindaPendentes, 2, reason: 'nada foi perdido');
    });

    test('voltando o sinal, a fila esvazia na ordem', () async {
      await enfileirar('atendimentos', 'um');
      await enfileirar('atendimentos', 'dois');

      var falhar = true;
      final subiram = <String>[];
      SyncService.instance.registerUploader('atendimentos', (e) async {
        if (falhar) throw const SocketException('sem rede');
        subiram.add(e.payload['body'] as String);
      });

      await SyncService.instance.syncNow();
      falhar = false;
      final r = await SyncService.instance.syncNow();

      expect(subiram, ['um', 'dois']);
      expect(r.aindaPendentes, 0);
    });
  });

  group('teto de tentativas — rede de segurança da classificação', () {
    test('erro transitório eterno acaba em quarentena, não travando', () async {
      // `_envioDaFila` erra para o lado de "transitório" de propósito, e sem
      // este teto um erro definitivo não reconhecido travaria a fila para
      // sempre. Este teste é a garantia de que isso não acontece.
      await enfileirar('atendimentos', 'erro nunca reconhecido');
      await enfileirar('hakuna_positions', 'ponto atrás dela');

      SyncService.instance.registerUploader('atendimentos', (e) async {
        throw StateError('erro que a classificação não conhece');
      });
      final posicoes = <String>[];
      SyncService.instance.registerUploader('hakuna_positions', (e) async {
        posicoes.add('ok');
      });

      // Uma rodada por tentativa, como aconteceria a cada volta de sinal.
      for (var i = 0; i < SyncService.maxTentativas; i++) {
        await SyncService.instance.syncNow();
      }

      expect(await Outbox.instance.quarantinedCount(), 1);
      expect(
        posicoes,
        ['ok'],
        reason: 'destravou e a posição atrás dela subiu',
      );
      final recusada = (await Outbox.instance.quarantined()).single;
      expect(recusada.quarantineReason, contains('vezes seguidas'));
    });
  });

  group('devolver à fila depois de resolver a causa', () {
    test('requeue zera tentativas e a entrada volta a ser enviada', () async {
      await enfileirar('team_messages', 'mensagem do Top em draft');

      var recusar = true;
      final subiram = <String>[];
      SyncService.instance.registerUploader('team_messages', (e) async {
        if (recusar) throw const FalhaPermanente('Top em draft', 'x');
        subiram.add(e.payload['body'] as String);
      });

      await SyncService.instance.syncNow();
      expect(await Outbox.instance.quarantinedCount(), 1);

      // O admin ativa o Top.
      recusar = false;
      final quantas = await Outbox.instance.requeueAll();
      expect(quantas, 1);

      final r = await SyncService.instance.syncNow();
      expect(subiram, ['mensagem do Top em draft']);
      expect(r.enviados, 1);
      expect(await Outbox.instance.quarantinedCount(), 0);
    });

    test('requeue zera o contador de tentativas', () async {
      await enfileirar('atendimentos', 'x');
      SyncService.instance.registerUploader('atendimentos', (e) async {
        throw const SocketException('sem rede');
      });
      await SyncService.instance.syncNow();
      await SyncService.instance.syncNow();

      var entrada = (await Outbox.instance.pending()).single;
      expect(entrada.attempts, 2);

      await Outbox.instance.requeue(entrada.id);
      entrada = (await Outbox.instance.pending()).single;
      // Sem zerar, o teto mandaria para a quarentena no primeiro tropeço.
      expect(entrada.attempts, 0);
    });

    test('descartar apaga só quem está em quarentena', () async {
      await enfileirar('team_messages', 'descartável');
      SyncService.instance.registerUploader('team_messages', (e) async {
        throw const FalhaPermanente('recusada', 'x');
      });
      await SyncService.instance.syncNow();

      final recusada = (await Outbox.instance.quarantined()).single;
      await Outbox.instance.descartar(recusada.id);
      expect(await Outbox.instance.quarantinedCount(), 0);
    });

    test('descartar NÃO apaga entrada que só está pendente', () async {
      await enfileirar('atendimentos', 'ainda esperando sinal');
      final pendente = (await Outbox.instance.pending()).single;
      await Outbox.instance.descartar(pendente.id);
      expect(
        await Outbox.instance.pendingCount(),
        1,
        reason: 'descartar é só para quarentena, nunca para a fila ativa',
      );
    });
  });

  group('contagens não misturam quarentena com fila', () {
    test('pendingCount exclui quarentenada', () async {
      await enfileirar('team_messages', 'recusada');
      await enfileirar('atendimentos', 'pendente');
      SyncService.instance.registerUploader('team_messages', (e) async {
        throw const FalhaPermanente('recusada', 'x');
      });
      // Sem uploader: fica pendente em vez de sumir.

      await SyncService.instance.syncNow();

      expect(await Outbox.instance.pendingCount(), 1);
      expect(await Outbox.instance.quarantinedCount(), 1);
    });

    test('pending() não devolve quarentenada', () async {
      await enfileirar('team_messages', 'recusada');
      SyncService.instance.registerUploader('team_messages', (e) async {
        throw const FalhaPermanente('recusada', 'x');
      });
      await SyncService.instance.syncNow();
      expect(await Outbox.instance.pending(), isEmpty);
    });
  });

  group('limpeza do que já subiu', () {
    test('purga entradas antigas depois de a fila esvaziar', () async {
      // purgeSynced existia e nunca era chamado: a fila crescia sem fim, e
      // numa trilha de 4 h o GPS sozinho gera centenas de linhas.
      await enfileirar('hakuna_positions', 'ponto');
      SyncService.instance.registerUploader('hakuna_positions', (e) async {});
      await SyncService.instance.syncNow();

      final db = await LocalDb.instance.database;
      final total =
          (await db.rawQuery('SELECT COUNT(*) c FROM outbox')).first['c'];
      // Ainda está lá: a purga só apaga o que subiu há mais de 30 dias.
      expect(total, 1);

      // Com retenção zero, a linha sai.
      final apagadas = await Outbox.instance.purgeSynced(
        manterPor: Duration.zero,
      );
      expect(apagadas, 1);
    });
  });
}
