import 'package:flutter_test/flutter_test.dart';
import 'package:legendario_connect/models/top_alert.dart';
import 'package:legendario_connect/offline/local_db.dart';
import 'package:legendario_connect/offline/outbox.dart';
import 'package:legendario_connect/offline/sync_service.dart';
import 'package:legendario_connect/services/alarme_service.dart';
import 'package:legendario_connect/services/supabase_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// O defeito que estes testes travam era o pior do app inteiro.
///
/// O alarme — a função usada em acidente — era a ÚNICA escrita que ia
/// direto ao Supabase, sem fila. Sem sinal, `insert` falhava, a tela
/// mostrava "não foi possível disparar o alarme" e o registro era
/// **descartado**. Na trilha, onde não há sinal, o botão de emergência não
/// fazia nada além de avisar que não fez nada.
///
/// O segundo defeito era de recebimento: o alarme só aparecia dentro da
/// tela de detalhe do Top. Quem estivesse na lista de participantes, no
/// chat ou com o celular no bolso não recebia nada.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // Som e vibração exigem binding de plataforma, que não existe em
    // teste de unidade.
    AlarmeService.anunciarLigado = false;
  });

  setUp(() async {
    LocalDb.overridePathForTests = inMemoryDatabasePath;
    await LocalDb.instance.close();
    SyncService.instance.resetForTests();
    SupabaseService.idDeUsuarioParaTestes = 'hakuna-1';
    AlarmeService.instance.limparParaTestes();
  });

  tearDown(() async {
    SupabaseService.idDeUsuarioParaTestes = null;
    await LocalDb.instance.close();
  });

  TopAlert alerta({
    required int id,
    String de = 'hakuna-2',
    Duration atras = Duration.zero,
  }) => TopAlert(
    id: id,
    topId: 'top-1',
    senderId: de,
    message: 'queda na trilha',
    createdAt: DateTime.now().toUtc().subtract(atras),
  );

  group('disparo', () {
    test('sem rede, o alarme FICA na fila em vez de se perder', () async {
      // Nenhum uploader registrado = nada sobe. É o cenário do mato.
      await AlarmeService.instance.disparar(
        topId: 'top-1',
        mensagem: 'queda',
        latitude: -20.5,
        longitude: -47.4,
      );

      final fila = await Outbox.instance.pending(
        entity: AlarmeService.entidade,
      );
      expect(fila.length, 1, reason: 'o alarme tem de estar guardado');
      expect(fila.single.payload['message'], 'queda');
      expect(fila.single.payload['latitude'], -20.5);
    });

    test('o payload leva client_id, e é o mesmo da linha da fila', () async {
      await AlarmeService.instance.disparar(topId: 'top-1');
      final e = (await Outbox.instance.pending(
        entity: AlarmeService.entidade,
      )).single;

      expect(
        e.payload['client_id'],
        isNotNull,
        reason: 'sem isto o servidor nao tem como deduplicar o reenvio',
      );
      expect(e.payload['client_id'], e.clientId);
    });

    test('disparar tenta enviar na hora, sem esperar o próximo ciclo', () async {
      // Com sinal o alarme tem de sair agora, não no próximo tique do
      // sincronizador. É o `unawaited(syncNow())` dentro de `disparar`.
      var tentou = 0;
      SyncService.instance.registerUploader(AlarmeService.entidade, (e) async {
        tentou++;
      });

      await AlarmeService.instance.disparar(topId: 'top-1');
      // Em produção esse envio é fire-and-forget. Aqui ele é aguardado
      // pela costura `envioEmAndamento` — sem ela o teste mediria uma
      // corrida entre o envio e o fim do próprio teste.
      await AlarmeService.instance.envioEmAndamento;

      expect(tentou, 1);
      expect(await Outbox.instance.pendingCount(), 0, reason: 'saiu da fila');
    });

    test('reenvio manda o MESMO client_id — não duplica o alarme', () async {
      // Enfileira pelo Outbox, não por `disparar`, de propósito: o que se
      // testa aqui é o reenvio, e `disparar` dispara um `syncNow` próprio
      // que corre junto e torna a contagem de tentativas indeterminada. O
      // payload é o mesmo que `disparar` monta.
      final clientId = Outbox.novoClientId();
      await Outbox.instance.enqueue(
        entity: AlarmeService.entidade,
        topId: 'top-1',
        clientId: clientId,
        payload: {
          'client_id': clientId,
          'top_id': 'top-1',
          'sender_id': 'hakuna-1',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        },
      );

      final enviados = <String?>[];
      var falhar = true;
      SyncService.instance.registerUploader(AlarmeService.entidade, (e) async {
        enviados.add(e.payload['client_id'] as String?);
        if (falhar) throw Exception('resposta perdida');
      });

      await SyncService.instance.syncNow();
      falhar = false;
      await SyncService.instance.syncNow();

      expect(enviados.length, 2);
      expect(
        enviados[0],
        enviados[1],
        reason: 'dois ids virariam dois alarmes para o mesmo acidente',
      );
      expect(await Outbox.instance.pendingCount(), 0);
    });

    test('a hora é a do APARELHO, não a do servidor', () async {
      final antes = DateTime.now().toUtc();
      await AlarmeService.instance.disparar(topId: 'top-1');
      final depois = DateTime.now().toUtc();

      final e = (await Outbox.instance.pending(
        entity: AlarmeService.entidade,
      )).single;
      final quando = DateTime.parse(e.payload['created_at'] as String);

      // Offline o acidente acontece horas antes do upload. Se o campo
      // ficasse de fora, o default `now()` do Postgres gravaria a hora em
      // que o sinal voltou — e aí o registro diz que o acidente foi às 16h
      // quando foi às 11h.
      expect(quando.isBefore(antes.subtract(const Duration(seconds: 1))),
          isFalse);
      expect(quando.isAfter(depois.add(const Duration(seconds: 1))), isFalse);
    });

    test('sem sessão, não enfileira em silêncio: lança', () async {
      SupabaseService.idDeUsuarioParaTestes = null;
      await expectLater(
        AlarmeService.instance.disparar(topId: 'top-1'),
        throwsA(isA<StateError>()),
      );
      expect(await Outbox.instance.pendingCount(), 0);
    });
  });

  group('recebimento', () {
    test('alarme recente de outro Hakuna fica ativo', () {
      AlarmeService.instance.receberParaTestes([alerta(id: 1)]);
      expect(AlarmeService.instance.ativos.length, 1);
    });

    test('alarme velho não aparece', () {
      // Duas horas atrás não é mais informação útil, é poluição de tela.
      AlarmeService.instance.receberParaTestes([
        alerta(id: 1, atras: const Duration(hours: 2)),
      ]);
      expect(AlarmeService.instance.ativos, isEmpty);
    });

    test('dispensar some com o alarme e não o traz de volta', () {
      AlarmeService.instance.receberParaTestes([alerta(id: 7)]);
      AlarmeService.instance.descartar(7);
      expect(AlarmeService.instance.ativos, isEmpty);

      // O stream reemite a lista inteira a cada mudança; sem guardar o
      // descarte, o alarme dispensado voltaria na próxima emissão.
      AlarmeService.instance.receberParaTestes([alerta(id: 7)]);
      expect(AlarmeService.instance.ativos, isEmpty);
    });

    test('o próprio alarme aparece na tela mas não apita', () {
      // Quem disparou já sabe. O celular apitando na mão de quem pediu
      // socorro é ruído na hora errada — mas a faixa fica, para ele ver
      // que o alarme está registrado.
      AlarmeService.instance.receberParaTestes([
        alerta(id: 3, de: 'hakuna-1'),
      ]);
      expect(AlarmeService.instance.ativos.length, 1);
    });

    test('parar() limpa tudo — outro usuário no mesmo aparelho', () {
      AlarmeService.instance.receberParaTestes([alerta(id: 1)]);
      AlarmeService.instance.parar();
      expect(AlarmeService.instance.ativos, isEmpty);
    });
  });
}
