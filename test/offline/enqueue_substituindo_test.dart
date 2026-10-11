import 'package:flutter_test/flutter_test.dart';
import 'package:legendario_connect/offline/local_db.dart';
import 'package:legendario_connect/offline/outbox.dart';
import 'package:legendario_connect/offline/sync_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// `enqueueSubstituindo` é onde mora o risco de perder texto, e por isso
/// tem teste próprio.
///
/// `enqueue` usa `ConflictAlgorithm.ignore`: reenfileirar o mesmo
/// `client_id` DESCARTA o segundo pedido. Isso está certo para o que é
/// append-only — enfileirar duas vezes o mesmo atendimento não pode criar
/// dois registros. Para o que é EDITÁVEL (o bloco de anotações), é o
/// oposto do desejado: a edição seria jogada fora sem erro nenhum na tela.
///
/// E há um segundo buraco, que só apareceu quando um teste cobriu o caso:
/// `client_id` tem índice ÚNICO nesta tabela. Depois que a entrada
/// sincroniza, a linha CONTINUA ali — então um `enqueue` novo com o mesmo
/// id também é ignorado, e a edição seguinte se perde. Daí esta função
/// mexer na linha em qualquer estado.
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

  const bloco = 'top-1|seguranca|u1|-';

  Future<String> gravar(String texto) => Outbox.instance.enqueueSubstituindo(
    entity: 'anotacoes',
    clientId: bloco,
    topId: 'top-1',
    payload: {'bloco_id': bloco, 'texto': texto},
  );

  test('a primeira gravação cria a entrada', () async {
    await gravar('v1');
    final fila = await Outbox.instance.pending(entity: 'anotacoes');
    expect(fila.length, 1);
    expect(fila.single.payload['texto'], 'v1');
  });

  test('a segunda SUBSTITUI o texto, não é descartada', () async {
    // Com `enqueue` puro, este expect falharia: a fila ficaria com 'v1'.
    await gravar('v1');
    await gravar('v2');
    final fila = await Outbox.instance.pending(entity: 'anotacoes');
    expect(fila.length, 1, reason: 'um bloco = uma entrada');
    expect(fila.single.payload['texto'], 'v2');
  });

  test('dez edições seguidas deixam uma entrada com o texto final', () async {
    for (var i = 1; i <= 10; i++) {
      await gravar('v$i');
    }
    final fila = await Outbox.instance.pending(entity: 'anotacoes');
    expect(fila.length, 1);
    expect(fila.single.payload['texto'], 'v10');
  });

  test('depois de SINCRONIZAR, a edição volta para a fila', () async {
    // Era o buraco: a linha sincronizada continua na tabela e o índice
    // único de `client_id` fazia o `enqueue` seguinte ser ignorado. Toda
    // edição feita após o primeiro envio desaparecia.
    final enviados = <String?>[];
    SyncService.instance.registerUploader('anotacoes', (e) async {
      enviados.add(e.payload['texto'] as String?);
    });

    await gravar('v1');
    await SyncService.instance.syncNow();
    expect(enviados, ['v1']);
    expect(await Outbox.instance.pendingCount(), 0);

    await gravar('v2');
    expect(
      await Outbox.instance.pendingCount(),
      1,
      reason: 'a edicao depois de subir TEM de voltar para a fila',
    );

    await SyncService.instance.syncNow();
    expect(enviados, ['v1', 'v2']);
  });

  test('entrada em QUARENTENA volta à fila com o texto novo', () async {
    // O texto é outro: a recusa anterior era do texto antigo, e manter a
    // entrada em quarentena esconderia a correção que a pessoa acabou de
    // escrever exatamente para resolver o problema.
    await gravar('texto que o servidor recusou');
    final entrada = (await Outbox.instance.pending(entity: 'anotacoes')).single;
    await Outbox.instance.quarantine(entrada.id, 'recusado para teste');
    expect(await Outbox.instance.pendingCount(), 0);

    await gravar('texto corrigido');
    final fila = await Outbox.instance.pending(entity: 'anotacoes');
    expect(fila.length, 1);
    expect(fila.single.payload['texto'], 'texto corrigido');
    expect(fila.single.attempts, 0, reason: 'tentativas zeradas');
  });

  test('blocos diferentes não se misturam', () async {
    await gravar('do turno');
    await Outbox.instance.enqueueSubstituindo(
      entity: 'anotacoes',
      clientId: 'top-1|seguranca|u1|p-9',
      topId: 'top-1',
      payload: {'bloco_id': 'top-1|seguranca|u1|p-9', 'texto': 'sobre p-9'},
    );

    final fila = await Outbox.instance.pending(entity: 'anotacoes');
    expect(fila.length, 2);
    expect(
      fila.map((e) => e.payload['texto']).toSet(),
      {'do turno', 'sobre p-9'},
    );
  });

  test('não mexe em entrada de OUTRA entidade com o mesmo id', () async {
    // `where` filtra por entidade também. Sem isso, um `client_id` que por
    // acaso coincidisse entre entidades faria uma sobrescrever a outra —
    // e no caso de atendimento isso seria perda de dado clínico.
    await Outbox.instance.enqueue(
      entity: 'atendimentos',
      clientId: bloco,
      payload: {'texto': 'atendimento, nao mexer'},
    );
    await gravar('anotacao');

    final atend = await Outbox.instance.pending(entity: 'atendimentos');
    expect(atend.single.payload['texto'], 'atendimento, nao mexer');
    final anot = await Outbox.instance.pending(entity: 'anotacoes');
    expect(anot.single.payload['texto'], 'anotacao');
  });

  test('enqueue comum CONTINUA ignorando o repetido', () async {
    // Guarda de regressão na direção oposta: `enqueue` tem de manter o
    // `ignore`. Atendimento é append-only, e enfileirar duas vezes o mesmo
    // não pode criar dois registros nem sobrescrever o primeiro.
    await Outbox.instance.enqueue(
      entity: 'atendimentos',
      clientId: 'cid-fixo',
      payload: {'notes': 'primeiro'},
    );
    await Outbox.instance.enqueue(
      entity: 'atendimentos',
      clientId: 'cid-fixo',
      payload: {'notes': 'segundo'},
    );
    final fila = await Outbox.instance.pending(entity: 'atendimentos');
    expect(fila.length, 1);
    expect(
      fila.single.payload['notes'],
      'primeiro',
      reason: 'o primeiro registro e o que vale no append-only',
    );
  });
}
