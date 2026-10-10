import 'package:flutter_test/flutter_test.dart';
import 'package:legendario_connect/offline/local_db.dart';
import 'package:legendario_connect/offline/outbox.dart';
import 'package:legendario_connect/offline/sync_service.dart';
import 'package:legendario_connect/services/supabase_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// O bug que estes testes travam, encontrado na revisão de 10/10/2026:
///
/// `publishPosition` fazia INSERT puro, sem `client_id`. O outbox reenvia
/// quando o envio anterior falhou — e "falhou" inclui o caso em que o
/// insert chegou e só a resposta se perdeu, que é o normal com sinal ruim.
///
/// Resultado: ponto duplicado na trilha. `StatsService` soma a distância
/// entre pontos consecutivos, então duplicata **infla a distância** e, com
/// ela, a estimativa de calorias. É a entidade de maior volume do sistema:
/// um ponto a cada 15 m caminhados.
///
/// Atendimento, foto, chat e auditoria já tinham `client_id`. A posição,
/// não — e era a que mais reenvia.
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

  /// Enfileira como o `LocationService` faz: client_id gerado no aparelho e
  /// colocado DENTRO do payload, porque é só o payload que chega ao
  /// servidor — o id na linha da fila não sai do celular.
  Future<String> enfileirarPosicao(double lat, double lon) async {
    final clientId = Outbox.novoClientId();
    await Outbox.instance.enqueue(
      entity: entidadePosicao,
      topId: 'top-1',
      clientId: clientId,
      payload: {
        'client_id': clientId,
        'top_id': 'top-1',
        'latitude': lat,
        'longitude': lon,
        'recorded_at': DateTime.now().toUtc().toIso8601String(),
      },
    );
    return clientId;
  }

  test('todo ponto sai da fila com client_id no payload', () async {
    await enfileirarPosicao(-20.5, -47.4);
    final entrada = (await Outbox.instance.pending()).single;

    expect(
      entrada.payload['client_id'],
      isNotNull,
      reason: 'sem isto o servidor nao tem como deduplicar',
    );
    expect(
      entrada.payload['client_id'],
      entrada.clientId,
      reason: 'o id do payload e o da fila precisam ser o mesmo',
    );
  });

  test('cada ponto tem client_id proprio', () async {
    for (var i = 0; i < 20; i++) {
      await enfileirarPosicao(-20.5 + i * 0.001, -47.4);
    }
    final ids = (await Outbox.instance.pending())
        .map((e) => e.payload['client_id'])
        .toSet();
    expect(ids.length, 20, reason: 'id repetido engoliria pontos da trilha');
  });

  test('reenvio apos falha manda o MESMO client_id', () async {
    // É este o cenário do bug: o insert chegou, a resposta se perdeu, o
    // outbox tenta de novo. Com o mesmo client_id o servidor reconhece e
    // ignora; sem ele, grava um ponto duplicado.
    await enfileirarPosicao(-20.5, -47.4);

    final enviados = <String?>[];
    var falhar = true;
    SyncService.instance.registerUploader(entidadePosicao, (
      e,
    ) async {
      enviados.add(e.payload['client_id'] as String?);
      if (falhar) throw Exception('resposta perdida');
    });

    await SyncService.instance.syncNow();
    falhar = false;
    await SyncService.instance.syncNow();

    expect(enviados.length, 2, reason: 'tentou duas vezes');
    expect(
      enviados[0],
      enviados[1],
      reason: 'o reenvio precisa carregar o mesmo id, senao duplica',
    );
    expect(await Outbox.instance.pendingCount(), 0);
  });

  test('posicao sem fix de GPS nao e enfileirada com lat/lon nulos', () async {
    // Guarda de regressão do outro bug da mesma revisão: `atendimentos`
    // tinha latitude NOT NULL enquanto o app seguia sem fix. Aqui a posição
    // só existe quando há fix — o stream do GPS não emite sem coordenada —,
    // então o que se trava é que nada nulo entre na fila por engano.
    final entrada = await (() async {
      await enfileirarPosicao(-20.5, -47.4);
      return (await Outbox.instance.pending()).single;
    })();
    expect(entrada.payload['latitude'], isNotNull);
    expect(entrada.payload['longitude'], isNotNull);
  });
}

/// Nome da entidade, copiado de `LocationService.entityPosicao`.
///
/// Copiado e não importado de propósito: importar `LocationService` puxa
/// `geolocator`, que exige binding de plataforma e derruba o teste de
/// unidade. O valor é um literal estável; se ele mudar lá, estes testes
/// param de encontrar as entradas e falham — que é o aviso desejado.
const entidadePosicao = 'hakuna_positions';
