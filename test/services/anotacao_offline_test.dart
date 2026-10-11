import 'package:flutter_test/flutter_test.dart';
import 'package:legendario_connect/models/anotacao.dart';
import 'package:legendario_connect/models/team.dart';
import 'package:legendario_connect/offline/local_db.dart';
import 'package:legendario_connect/offline/outbox.dart';
import 'package:legendario_connect/offline/sync_service.dart';
import 'package:legendario_connect/services/anotacao_service.dart';
import 'package:legendario_connect/services/supabase_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// O app é dos Legendários, não só dos Hakunas. A diferença é que o Hakuna
/// tem prontuário — dado clínico, com cerca própria — e as outras 8
/// equipes precisam do equivalente não-médico: um lugar para registrar o
/// que aconteceu no turno.
///
/// Estes testes travam o que a anotação promete: funciona sem rede, não
/// duplica no reenvio, e carrega a hora do aparelho.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    LocalDb.overridePathForTests = inMemoryDatabasePath;
    await LocalDb.instance.close();
    SyncService.instance.resetForTests();
    SupabaseService.idDeUsuarioParaTestes = 'membro-seguranca';
  });

  tearDown(() async {
    // `registrar` dispara `unawaited(syncNow())`; sem esperar, a rodada
    // esbarraria no banco já fechado.
    await SyncService.instance.rodadaEmAndamento;
    SupabaseService.idDeUsuarioParaTestes = null;
    await LocalDb.instance.close();
  });

  group('escrever sem rede', () {
    test('a anotação FICA guardada no aparelho', () async {
      final a = await AnotacaoService.instance.registrar(
        topId: 'top-1',
        team: TeamKey.seguranca,
        texto: 'Portão 2 sem cobertura das 14h às 15h',
      );

      expect(a.texto, 'Portão 2 sem cobertura das 14h às 15h');
      expect(a.team, TeamKey.seguranca);
      expect(a.autorId, 'membro-seguranca');

      final fila = await Outbox.instance.pending(
        entity: AnotacaoService.entidade,
      );
      expect(fila.length, 1);
      expect(fila.single.payload['team'], 'seguranca');
    });

    test('aparece na lista do aparelho na hora', () async {
      // Sem isto quem escreveu não veria a própria anotação e escreveria
      // de novo, achando que não salvou.
      await AnotacaoService.instance.registrar(
        topId: 'top-1',
        team: TeamKey.logistica,
        texto: 'Faltou água no posto 3',
      );

      final naFila = await AnotacaoService.instance.naFila(
        topId: 'top-1',
        team: TeamKey.logistica,
      );
      expect(naFila.length, 1);
      expect(naFila.single.texto, 'Faltou água no posto 3');
      // Nome do autor não vem da fila — a tela mostra "Você".
      expect(naFila.single.autorNome, isNull);
    });

    test('o texto é aparado e vazio é recusado', () async {
      await expectLater(
        AnotacaoService.instance.registrar(
          topId: 'top-1',
          team: TeamKey.voz,
          texto: '   ',
        ),
        throwsA(isA<ArgumentError>()),
      );
      // Nem na fila: o banco também recusaria (`check length(trim) > 0`),
      // mas a entrada iria para quarentena em vez de simplesmente não
      // existir.
      expect(await Outbox.instance.pendingCount(), 0);

      final a = await AnotacaoService.instance.registrar(
        topId: 'top-1',
        team: TeamKey.voz,
        texto: '  com espaço em volta  ',
      );
      expect(a.texto, 'com espaço em volta');
    });

    test('client_id no payload, igual ao id da anotação', () async {
      final a = await AnotacaoService.instance.registrar(
        topId: 'top-1',
        team: TeamKey.midia,
        texto: 'Bateria da câmera 2 acabou',
      );
      final e = (await Outbox.instance.pending(
        entity: AnotacaoService.entidade,
      )).single;
      // Sem isto o reenvio depois de uma resposta perdida criaria a mesma
      // anotação duas vezes no histórico da equipe.
      expect(e.payload['client_id'], a.id);
      expect(e.clientId, a.id);
    });

    test('a hora é a do APARELHO', () async {
      final antes = DateTime.now().toUtc();
      final a = await AnotacaoService.instance.registrar(
        topId: 'top-1',
        team: TeamKey.eventos,
        texto: 'Largada atrasou 20 min',
      );
      // Offline a anotação é escrita horas antes do upload; `now()` no
      // Postgres marcaria a hora em que o sinal voltou.
      expect(
        a.criadaEm.difference(antes).inSeconds.abs(),
        lessThan(5),
      );
    });

    test('sem sessão, não grava anotação sem autor', () async {
      SupabaseService.idDeUsuarioParaTestes = null;
      await expectLater(
        AnotacaoService.instance.registrar(
          topId: 'top-1',
          team: TeamKey.adm,
          texto: 'qualquer coisa',
        ),
        throwsA(isA<StateError>()),
      );
      expect(await Outbox.instance.pendingCount(), 0);
    });
  });

  group('sobre uma pessoa ou sobre o turno', () {
    test('com participante, a anotação é sobre a pessoa', () async {
      final a = await AnotacaoService.instance.registrar(
        topId: 'top-1',
        team: TeamKey.seguranca,
        texto: 'Saiu da trilha no km 8',
        participanteId: 'part-9',
      );
      expect(a.sobrePessoa, isTrue);
      expect(a.participanteId, 'part-9');
    });

    test('sem participante, é do turno', () async {
      final a = await AnotacaoService.instance.registrar(
        topId: 'top-1',
        team: TeamKey.seguranca,
        texto: 'Rendição do portão 1 às 16h',
      );
      expect(a.sobrePessoa, isFalse);
    });

    test('naFila filtra por participante quando pedido', () async {
      await AnotacaoService.instance.registrar(
        topId: 'top-1',
        team: TeamKey.seguranca,
        texto: 'sobre a pessoa',
        participanteId: 'part-9',
      );
      await AnotacaoService.instance.registrar(
        topId: 'top-1',
        team: TeamKey.seguranca,
        texto: 'sobre o turno',
      );

      final daPessoa = await AnotacaoService.instance.naFila(
        topId: 'top-1',
        team: TeamKey.seguranca,
        participanteId: 'part-9',
      );
      expect(daPessoa.length, 1);
      expect(daPessoa.single.texto, 'sobre a pessoa');

      final tudo = await AnotacaoService.instance.naFila(
        topId: 'top-1',
        team: TeamKey.seguranca,
      );
      expect(tudo.length, 2);
    });

    test('naFila separa por equipe e por Top', () async {
      await AnotacaoService.instance.registrar(
        topId: 'top-1',
        team: TeamKey.seguranca,
        texto: 'da seguranca',
      );
      await AnotacaoService.instance.registrar(
        topId: 'top-1',
        team: TeamKey.midia,
        texto: 'da midia',
      );
      await AnotacaoService.instance.registrar(
        topId: 'top-2',
        team: TeamKey.seguranca,
        texto: 'de outro Top',
      );

      final seg = await AnotacaoService.instance.naFila(
        topId: 'top-1',
        team: TeamKey.seguranca,
      );
      expect(seg.length, 1);
      expect(seg.single.texto, 'da seguranca');
    });

    test('mais recente primeiro', () async {
      await AnotacaoService.instance.registrar(
        topId: 'top-1',
        team: TeamKey.adm,
        texto: 'primeira',
      );
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await AnotacaoService.instance.registrar(
        topId: 'top-1',
        team: TeamKey.adm,
        texto: 'segunda',
      );

      final lista = await AnotacaoService.instance.naFila(
        topId: 'top-1',
        team: TeamKey.adm,
      );
      expect(lista.first.texto, 'segunda');
    });
  });

  group('fromMap', () {
    test('lê o join do Postgrest como objeto', () {
      final a = Anotacao.fromMap({
        'id': 'a1',
        'top_id': 't1',
        'team': 'seguranca',
        'autor_id': 'u1',
        'texto': 'ocorrência',
        'criada_em': '2026-10-11T12:00:00Z',
        'autor': {'full_name': 'JOAO'},
        'participante': {'full_name': 'MARIA'},
      });
      expect(a.autorNome, 'JOAO');
      expect(a.participanteNome, 'MARIA');
      expect(a.team, TeamKey.seguranca);
    });

    test('lê o join como lista de um item', () {
      // O Postgrest devolve relação como objeto OU como lista de um,
      // conforme a cardinalidade que ele infere. Tratar só um dos dois
      // daria um cast que estoura em campo por causa do formato da
      // resposta.
      final a = Anotacao.fromMap({
        'id': 'a1',
        'top_id': 't1',
        'team': 'midia',
        'autor_id': 'u1',
        'texto': 'x',
        'criada_em': '2026-10-11T12:00:00Z',
        'autor': [
          {'full_name': 'PEDRO'},
        ],
      });
      expect(a.autorNome, 'PEDRO');
      expect(a.participanteNome, isNull);
    });

    test('equipe desconhecida não derruba a tela', () {
      // Enum novo no banco com app antigo instalado. Cair em `geral` é
      // pior que nada? Não: pior seria a lista inteira não abrir.
      final a = Anotacao.fromMap({
        'id': 'a1',
        'top_id': 't1',
        'team': 'equipe_que_nao_existe_ainda',
        'autor_id': 'u1',
        'texto': 'x',
        'criada_em': '2026-10-11T12:00:00Z',
      });
      expect(a.team, TeamKey.geral);
    });

    test('toMap não leva os nomes dos joins', () {
      final a = Anotacao(
        id: 'a1',
        topId: 't1',
        team: TeamKey.voz,
        autorId: 'u1',
        texto: 'x',
        criadaEm: DateTime.utc(2026, 10, 11, 12),
        autorNome: 'JOAO',
      );
      final m = a.toMap();
      // Nome é leitura, não dado desta linha — mandá-lo ao servidor daria
      // erro de coluna inexistente, classificado como PERMANENTE.
      expect(m.containsKey('autor'), isFalse);
      expect(m.containsKey('autorNome'), isFalse);
      expect(m['team'], 'voz');
    });
  });
}
