import 'package:flutter_test/flutter_test.dart';
import 'package:hakuna_connect/offline/local_db.dart';
import 'package:hakuna_connect/offline/outbox.dart';
import 'package:hakuna_connect/offline/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Cenário completo de um Top: o Hakuna caminha a trilha sem sinal,
/// registra atendimentos, tira fotos, e só horas depois encontra wifi.
///
/// Este teste existe porque o custo de errar aqui é perder registro
/// clínico de campo — e isso não se recupera.
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

  tearDown(() async => LocalDb.instance.close());

  group('trilha de um Top inteiro, sem sinal', () {
    test('GPS, atendimentos e fotos sobem completos e na ordem quando o sinal '
        'volta no alojamento', () async {
      const topId = 'top-1782';
      final inicio = DateTime.utc(2026, 8, 28, 6);

      // --- 4 horas de trilha, um ponto a cada 2 minutos ---
      for (var minuto = 0; minuto < 240; minuto += 2) {
        await Outbox.instance.enqueue(
          entity: 'hakuna_positions',
          topId: topId,
          payload: {
            'top_id': topId,
            'latitude': -20.55 + minuto * 0.0001,
            'longitude': -47.41,
            // O instante da MEDIÇÃO, não o do envio.
            'recorded_at': inicio
                .add(Duration(minutes: minuto))
                .toIso8601String(),
          },
        );
      }

      // --- 3 atendimentos ao longo do caminho, com foto ---
      for (final (i, queixa) in [
        'cefaleia e náuseas',
        'torção de tornozelo',
        'desidratação',
      ].indexed) {
        final clientId = await Outbox.instance.enqueue(
          entity: 'atendimentos',
          topId: topId,
          payload: {
            'top_id': topId,
            'notes': queixa,
            'numero_registro': i + 1,
            'opened_at': inicio
                .add(Duration(minutes: 40 * (i + 1)))
                .toIso8601String(),
          },
        );
        await Outbox.instance.enqueue(
          entity: 'atendimento_fotos',
          topId: topId,
          payload: {
            'atendimento_client_id': clientId,
            'top_id': topId,
            'local_path': '/fotos/$clientId.jpg',
          },
        );
      }

      expect(
        await Outbox.instance.pendingCount(),
        126,
        reason: '120 posições + 3 atendimentos + 3 fotos',
      );

      // --- Chegou no alojamento: wifi ---
      final posicoes = <String>[];
      final atendimentos = <String>[];
      final fotos = <String>[];
      SyncService.instance.registerUploader(
        'hakuna_positions',
        (e) async => posicoes.add(e.payload['recorded_at'] as String),
      );
      SyncService.instance.registerUploader(
        'atendimentos',
        (e) async => atendimentos.add(e.payload['notes'] as String),
      );
      SyncService.instance.registerUploader(
        'atendimento_fotos',
        (e) async => fotos.add(e.payload['local_path'] as String),
      );

      final relatorio = await SyncService.instance.syncNow(lote: 500);

      expect(relatorio.enviados, 126);
      expect(relatorio.aindaPendentes, 0);
      expect(relatorio.tudoCerto, isTrue);

      expect(posicoes, hasLength(120));
      expect(atendimentos, [
        'cefaleia e náuseas',
        'torção de tornozelo',
        'desidratação',
      ]);
      expect(fotos, hasLength(3));

      // A ordem cronológica tem que sobreviver à fila: senão a trilha
      // chega embaralhada e a distância percorrida sai errada.
      final ordenadas = [...posicoes]..sort();
      expect(posicoes, ordenadas);
    });

    test(
      'cada posição carrega a hora em que o GPS mediu, não a do envio — '
      'senão 4 horas de trilha chegariam carimbadas no mesmo minuto',
      () async {
        final inicio = DateTime.utc(2026, 8, 28, 6);
        for (var i = 0; i < 3; i++) {
          await Outbox.instance.enqueue(
            entity: 'hakuna_positions',
            payload: {
              'recorded_at': inicio.add(Duration(hours: i)).toIso8601String(),
            },
          );
        }

        final recebidas = <DateTime>[];
        SyncService.instance.registerUploader(
          'hakuna_positions',
          (e) async =>
              recebidas.add(DateTime.parse(e.payload['recorded_at'] as String)),
        );
        await SyncService.instance.syncNow();

        expect(recebidas, hasLength(3));
        expect(
          recebidas.last.difference(recebidas.first),
          const Duration(hours: 2),
          reason:
              'as 2 horas entre o primeiro e o último ponto têm que '
              'sobreviver à fila',
        );
      },
    );

    test('sinal cai no meio da sincronização: o que subiu fica, o resto espera '
        'a próxima — nada se perde', () async {
      for (var i = 0; i < 50; i++) {
        await Outbox.instance.enqueue(
          entity: 'hakuna_positions',
          payload: {'i': i},
        );
      }

      var enviados = 0;
      SyncService.instance.registerUploader('hakuna_positions', (e) async {
        enviados++;
        if (enviados > 20) throw Exception('conexão caiu');
      });

      final primeira = await SyncService.instance.syncNow();
      expect(primeira.enviados, 20);
      expect(primeira.aindaPendentes, 30);

      // Sinal volta: termina o resto, sem reenviar o que já subiu.
      SyncService.instance.resetForTests();
      final reenviados = <int>[];
      SyncService.instance.registerUploader(
        'hakuna_positions',
        (e) async => reenviados.add(e.payload['i'] as int),
      );
      final segunda = await SyncService.instance.syncNow();

      expect(segunda.enviados, 30);
      expect(segunda.aindaPendentes, 0);
      expect(reenviados, [
        for (var i = 20; i < 50; i++) i,
      ], reason: 'só o que faltava — nenhum ponto sobe duas vezes');
    });
  });
}
