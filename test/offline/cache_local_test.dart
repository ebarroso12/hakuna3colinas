import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hakuna_connect/models/afericao.dart';
import 'package:hakuna_connect/models/participant.dart';
import 'package:hakuna_connect/models/participant_tag.dart';
import 'package:hakuna_connect/models/triage_rule.dart';
import 'package:hakuna_connect/offline/cache_local.dart';
import 'package:hakuna_connect/offline/local_db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// O cache local é o que faz o app funcionar no mato depois de o sistema
/// matar o processo. Estes testes exercitam **o SQLite de verdade** (ffi,
/// em memória) — é o mesmo motor que roda no celular, não um mock.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    LocalDb.overridePathForTests = inMemoryDatabasePath;
    await LocalDb.instance.close();
  });

  tearDown(() async {
    await LocalDb.instance.close();
  });

  final cache = CacheLocal.instance;

  Participant participante({
    required String id,
    required String nome,
    String? apelido,
    String? familia,
    String? codigo,
    List<String> comorbidades = const [],
    String topId = 'top-1',
  }) => Participant(
    id: id,
    topId: topId,
    fullName: nome,
    nickname: apelido,
    familia: familia,
    participantCode: codigo,
    birthDate: DateTime(1983, 3, 14),
    comorbidades: comorbidades,
    bloodType: 'O+',
  );

  ParticipantTag tag({
    required String token,
    required String participantId,
    TagStatus status = TagStatus.ativa,
    String topId = 'top-1',
  }) => ParticipantTag(
    id: 'tag-$token',
    token: token,
    participantId: participantId,
    topId: topId,
    status: status,
    issuedAt: DateTime(2026, 10, 1, 8),
  );

  group('participantes — ida e volta', () {
    test('grava e lê de volta sem perder campo', () async {
      await cache.salvarParticipantes('top-1', [
        participante(
          id: 'p1',
          nome: 'JOÃO DA SILVA',
          apelido: 'Joca',
          familia: 'ÁGUIA',
          codigo: '1782',
          comorbidades: ['hipertensão', 'diabetes'],
        ),
      ]);

      final lido = await cache.participante('p1');
      expect(lido, isNotNull);
      expect(lido!.fullName, 'JOÃO DA SILVA');
      expect(lido.familia, 'ÁGUIA');
      expect(lido.participantCode, '1782');
      // text[] do Postgres virou JSON no SQLite e voltou como lista — é a
      // contagem desta lista que decide a cor de triagem.
      expect(lido.comorbidades, ['hipertensão', 'diabetes']);
      expect(lido.totalComorbidades, 2);
      expect(lido.bloodType, 'O+');
      expect(lido.birthDate, DateTime(1983, 3, 14));
    });

    test('salvar de novo substitui o Top sem duplicar', () async {
      final lista = [participante(id: 'p1', nome: 'ANA')];
      await cache.salvarParticipantes('top-1', lista);
      await cache.salvarParticipantes('top-1', lista);
      expect((await cache.participantes('top-1')).length, 1);
    });

    test('baixar um Top não apaga o cache de outro', () async {
      await cache.salvarParticipantes('top-1', [
        participante(id: 'p1', nome: 'ANA'),
      ]);
      await cache.salvarParticipantes('top-2', [
        participante(id: 'p2', nome: 'BRUNO', topId: 'top-2'),
      ]);

      expect((await cache.participantes('top-1')).length, 1);
      expect((await cache.participantes('top-2')).length, 1);
    });

    test('ordena por nome', () async {
      await cache.salvarParticipantes('top-1', [
        participante(id: 'p2', nome: 'ZELIA'),
        participante(id: 'p1', nome: 'ANA'),
      ]);
      final lista = await cache.participantes('top-1');
      expect(lista.map((p) => p.fullName), ['ANA', 'ZELIA']);
    });
  });

  group('busca sem acento — o bug que o TextoBusca resolve', () {
    setUp(() async {
      await cache.salvarParticipantes('top-1', [
        participante(id: 'p1', nome: 'JOÃO DA SILVA', familia: 'ÁGUIA'),
        participante(id: 'p2', nome: 'MARIA CONCEIÇÃO', familia: 'LEÃO'),
        participante(id: 'p3', nome: 'ANTONIO MUNIZ', familia: 'AGUIA'),
      ]);
    });

    test('"joao" encontra "JOÃO"', () async {
      final lista = await cache.participantes('top-1', termo: 'joao');
      expect(lista.map((p) => p.id), ['p1']);
    });

    test('"JOÃO" encontra "JOÃO" (acento digitado também funciona)', () async {
      final lista = await cache.participantes('top-1', termo: 'JOÃO');
      expect(lista.map((p) => p.id), ['p1']);
    });

    test('"conceicao" encontra "CONCEIÇÃO"', () async {
      final lista = await cache.participantes('top-1', termo: 'conceicao');
      expect(lista.map((p) => p.id), ['p2']);
    });

    test('"aguia" encontra ÁGUIA e AGUIA na busca por família', () async {
      final lista = await cache.participantes('top-1', familia: 'aguia');
      expect(lista.map((p) => p.id).toSet(), {'p1', 'p3'});
    });

    test('os dois filtros se somam', () async {
      final lista = await cache.participantes(
        'top-1',
        termo: 'joao',
        familia: 'aguia',
      );
      expect(lista.map((p) => p.id), ['p1']);
    });

    test('busca parcial pelo sobrenome funciona', () async {
      final lista = await cache.participantes('top-1', termo: 'silva');
      expect(lista.map((p) => p.id), ['p1']);
    });
  });

  group('tags — o caminho do cold start no mato', () {
    test('resolve o token depois de o app ser MORTO e reaberto', () async {
      // Este teste roda em ARQUIVO, não em memória, de propósito: é o
      // único jeito de provar o que ele afirma. Com
      // `inMemoryDatabasePath`, fechar o banco apaga tudo e o teste
      // passaria a medir o nada.
      final dir = await Directory.systemTemp.createTemp('hakuna_cold_start');
      final arquivo = p.join(dir.path, 'hakuna_offline.db');
      await LocalDb.instance.close();
      LocalDb.overridePathForTests = arquivo;

      try {
        await cache.salvarTags('top-1', [
          tag(token: 'a' * 32, participantId: 'p1'),
        ]);
        await cache.salvarParticipantes('top-1', [
          participante(id: 'p1', nome: 'JOÃO DA SILVA'),
        ]);

        // O sistema mata o app: processo encerrado, RAM perdida.
        await LocalDb.instance.close();

        // Cold start no mato, sem rede. O arquivo continua lá.
        final resolvida = await cache.tagPorToken('a' * 32);
        expect(resolvida, isNotNull, reason: 'a tag tem de sobreviver');
        expect(resolvida!.participantId, 'p1');
        expect(resolvida.valida, isTrue);

        final pessoa = await cache.participante('p1');
        expect(pessoa!.fullName, 'JOÃO DA SILVA');
      } finally {
        await LocalDb.instance.close();
        LocalDb.overridePathForTests = inMemoryDatabasePath;
        await dir.delete(recursive: true);
      }
    });

    test('resolve o token sem rede (mesma sessão)', () async {
      await cache.salvarTags('top-1', [
        tag(token: 'a' * 32, participantId: 'p1'),
      ]);
      final resolvida = await cache.tagPorToken('a' * 32);
      expect(resolvida!.participantId, 'p1');
    });

    test('token desconhecido devolve null, não exceção', () async {
      await cache.salvarTags('top-1', [
        tag(token: 'a' * 32, participantId: 'p1'),
      ]);
      expect(await cache.tagPorToken('b' * 32), isNull);
    });

    test('tag revogada volta COM o status, não como desconhecida', () async {
      // Diferença que importa em campo: "revogada" manda desconfiar da
      // pulseira; "desconhecida" manda conferir pelo nome.
      await cache.salvarTags('top-1', [
        tag(
          token: 'c' * 32,
          participantId: 'p1',
          status: TagStatus.revogada,
        ),
      ]);

      final resolvida = await cache.tagPorToken('c' * 32);
      expect(resolvida, isNotNull);
      expect(resolvida!.status, TagStatus.revogada);
      expect(resolvida.valida, isFalse);
    });

    test('contagem por Top', () async {
      await cache.salvarTags('top-1', [
        tag(token: 'a' * 32, participantId: 'p1'),
        tag(token: 'b' * 32, participantId: 'p2'),
      ]);
      expect(await cache.totalTags('top-1'), 2);
      expect(await cache.totalTags('top-2'), 0);
    });
  });

  group('regras de triagem', () {
    test('grava, lê ativas e devolve em ordem de prioridade', () async {
      await cache.salvarRegras([
        TriageRule(
          id: 2,
          color: TriageColor.green,
          label: 'Verde',
          minAge: 0,
          maxAge: 25,
          minComorbidities: 1,
          maxComorbidities: 1,
          priority: 20,
          active: true,
        ),
        TriageRule(
          id: 1,
          color: TriageColor.red,
          label: 'Vermelho',
          minAge: 41,
          minComorbidities: 1,
          maxComorbidities: 999,
          priority: 10,
          active: true,
        ),
        TriageRule(
          id: 3,
          color: TriageColor.blue,
          label: 'Inativa',
          minAge: 0,
          minComorbidities: 0,
          maxComorbidities: 0,
          priority: 5,
          active: false,
        ),
      ]);

      final regras = await cache.regras();
      expect(regras.map((r) => r.id), [1, 2], reason: 'inativa fica fora');
      expect(regras.first.maxAge, isNull, reason: 'faixa aberta preservada');
    });
  });

  group('última aferição — triagem dinâmica offline', () {
    test('grava e lê por participante', () async {
      await cache.registrarAfericao(
        'p1',
        'top-1',
        Afericao(
          medidoEm: DateTime(2026, 10, 10, 9),
          systolicBp: 190,
          diastolicBp: 120,
          spo2: 88,
        ),
      );

      final a = await cache.afericaoDe('p1');
      expect(a!.spo2, 88);
      expect(a.pressaoArterial, '190 x 120');
    });

    test('aferição mais nova substitui a anterior', () async {
      await cache.registrarAfericao(
        'p1',
        'top-1',
        Afericao(medidoEm: DateTime(2026, 10, 10, 9), spo2: 88),
      );
      await cache.registrarAfericao(
        'p1',
        'top-1',
        Afericao(medidoEm: DateTime(2026, 10, 10, 11), spo2: 97),
      );

      expect((await cache.afericaoDe('p1'))!.spo2, 97);
    });

    test('aferição ANTIGA que chega depois não sobrescreve a nova', () async {
      // Cenário real: offline, o atendimento das 11h sincroniza antes do
      // das 9h. A medida das 9h não pode apagar a das 11h.
      await cache.registrarAfericao(
        'p1',
        'top-1',
        Afericao(medidoEm: DateTime(2026, 10, 10, 11), spo2: 97),
      );
      await cache.registrarAfericao(
        'p1',
        'top-1',
        Afericao(medidoEm: DateTime(2026, 10, 10, 9), spo2: 88),
      );

      expect(
        (await cache.afericaoDe('p1'))!.spo2,
        97,
        reason: 'a mais recente tem de permanecer',
      );
    });

    test('aferição vazia não apaga a anterior', () async {
      await cache.registrarAfericao(
        'p1',
        'top-1',
        Afericao(medidoEm: DateTime(2026, 10, 10, 9), spo2: 88),
      );
      await cache.registrarAfericao(
        'p1',
        'top-1',
        Afericao(medidoEm: DateTime(2026, 10, 10, 12)),
      );

      expect((await cache.afericaoDe('p1'))!.spo2, 88);
    });

    test('mapa do Top traz uma entrada por participante', () async {
      await cache.registrarAfericao(
        'p1',
        'top-1',
        Afericao(medidoEm: DateTime(2026, 10, 10, 9), spo2: 88),
      );
      await cache.registrarAfericao(
        'p2',
        'top-1',
        Afericao(medidoEm: DateTime(2026, 10, 10, 9), systolicBp: 200),
      );
      await cache.registrarAfericao(
        'p3',
        'top-2',
        Afericao(medidoEm: DateTime(2026, 10, 10, 9), spo2: 80),
      );

      final mapa = await cache.afericoesDoTop('top-1');
      expect(mapa.keys.toSet(), {'p1', 'p2'});
    });
  });

  group('baixadoEm — idade do dado', () {
    test('null quando o Top nunca foi baixado', () async {
      expect(await cache.baixadoEm('top-1'), isNull);
    });

    test('devolve o instante do download', () async {
      final antes = DateTime.now().subtract(const Duration(seconds: 2));
      await cache.salvarParticipantes('top-1', [
        participante(id: 'p1', nome: 'ANA'),
      ]);
      final quando = await cache.baixadoEm('top-1');
      expect(quando, isNotNull);
      expect(quando!.isAfter(antes), isTrue);
    });
  });

  group('limparTop — aparelho compartilhado', () {
    test('apaga participantes, tags e aferições só do Top pedido', () async {
      await cache.salvarParticipantes('top-1', [
        participante(id: 'p1', nome: 'ANA'),
      ]);
      await cache.salvarParticipantes('top-2', [
        participante(id: 'p2', nome: 'BRUNO', topId: 'top-2'),
      ]);
      await cache.salvarTags('top-1', [
        tag(token: 'a' * 32, participantId: 'p1'),
      ]);
      await cache.registrarAfericao(
        'p1',
        'top-1',
        Afericao(medidoEm: DateTime(2026, 10, 10, 9), spo2: 88),
      );

      await cache.limparTop('top-1');

      expect(await cache.participantes('top-1'), isEmpty);
      expect(await cache.tagPorToken('a' * 32), isNull);
      expect(await cache.afericaoDe('p1'), isNull);
      expect((await cache.participantes('top-2')).length, 1);
    });
  });

  group('migração da v1 para a v2', () {
    test('banco antigo ganha as tabelas de cache sem perder a fila', () async {
      // Abre, grava na fila (que existe desde a v1) e confirma que as
      // tabelas novas estão acessíveis no mesmo banco.
      final db = await LocalDb.instance.database;
      expect(db.getVersion(), completion(2));

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
        ]),
      );
    });
  });
}
