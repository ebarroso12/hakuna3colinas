import 'package:flutter_test/flutter_test.dart';
import 'package:legendario_connect/models/anotacao.dart';
import 'package:legendario_connect/models/team.dart';
import 'package:legendario_connect/offline/local_db.dart';
import 'package:legendario_connect/offline/outbox.dart';
import 'package:legendario_connect/offline/sync_service.dart';
import 'package:legendario_connect/services/anotacao_service.dart';
import 'package:legendario_connect/services/supabase_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// O bloco de anotações é **um por membro e editável**.
///
/// A primeira versão era append-only, por medo de perda de texto. O dono
/// do projeto apontou que o medo não se aplica: cada membro tem login
/// próprio e o bloco é dele, então não há duas pessoas editando o mesmo.
///
/// Mas trocar para editável abriu um buraco de verdade, e é o que o grupo
/// 'editar sem sinal' trava: `Outbox.enqueue` usa
/// `ConflictAlgorithm.ignore`, então reenfileirar o mesmo `client_id`
/// **descarta** o segundo pedido. Isso é certo para atendimento
/// (append-only) e catastrófico aqui — a segunda edição offline seria
/// ignorada em silêncio e o texto antigo subiria. Daí
/// `enqueueSubstituindo`.
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
    // `salvar` dispara `unawaited(syncNow())`; sem esperar, a rodada
    // esbarraria no banco já fechado.
    await SyncService.instance.rodadaEmAndamento;
    SupabaseService.idDeUsuarioParaTestes = null;
    await LocalDb.instance.close();
  });

  Future<Anotacao> salvar(
    String texto, {
    String topId = 'top-1',
    TeamKey team = TeamKey.seguranca,
    String? participanteId,
    Anotacao? anterior,
  }) => AnotacaoService.instance.salvar(
    topId: topId,
    team: team,
    texto: texto,
    participanteId: participanteId,
    anterior: anterior,
  );

  group('escrever sem rede', () {
    test('o bloco FICA guardado no aparelho', () async {
      final a = await salvar('Portão 2 sem cobertura das 14h às 15h');

      expect(a.texto, 'Portão 2 sem cobertura das 14h às 15h');
      expect(a.team, TeamKey.seguranca);
      expect(a.autorId, 'membro-seguranca');

      final fila = await Outbox.instance.pending(
        entity: AnotacaoService.entidade,
      );
      expect(fila.length, 1);
      expect(fila.single.payload['team'], 'seguranca');
    });

    test('reabrir a tela sem rede mostra o que foi escrito', () async {
      await salvar('Faltou água no posto 3');

      final local = await AnotacaoService.instance.meuBlocoNaFila(
        topId: 'top-1',
        team: TeamKey.seguranca,
      );
      expect(local, isNotNull);
      expect(local!.texto, 'Faltou água no posto 3');
    });

    test('o texto é aparado e vazio é recusado', () async {
      await expectLater(salvar('   '), throwsA(isA<ArgumentError>()));
      expect(await Outbox.instance.pendingCount(), 0);

      final a = await salvar('  com espaço em volta  ');
      expect(a.texto, 'com espaço em volta');
    });

    test('a hora é a do APARELHO', () async {
      final antes = DateTime.now().toUtc();
      final a = await salvar('Largada atrasou 20 min');
      expect(a.criadaEm.difference(antes).inSeconds.abs(), lessThan(5));
      expect(a.atualizadoEm.difference(antes).inSeconds.abs(), lessThan(5));
    });

    test('sem sessão, não grava bloco sem autor', () async {
      SupabaseService.idDeUsuarioParaTestes = null;
      await expectLater(salvar('qualquer coisa'), throwsA(isA<StateError>()));
      expect(await Outbox.instance.pendingCount(), 0);
    });
  });

  group('editar sem sinal — onde o texto se perdia', () {
    test('a SEGUNDA edição offline não é descartada', () async {
      // É o teste mais importante deste arquivo. Com `enqueue` puro
      // (`ConflictAlgorithm.ignore`), o segundo salvamento era ignorado e
      // o texto da PRIMEIRA versão subia — perda silenciosa.
      final v1 = await salvar('primeira versão');
      final v2 = await salvar('segunda versão', anterior: v1);
      final v3 = await salvar('terceira versão', anterior: v2);

      final fila = await Outbox.instance.pending(
        entity: AnotacaoService.entidade,
      );
      expect(fila.length, 1, reason: 'um bloco = uma entrada na fila');
      expect(
        fila.single.payload['texto'],
        'terceira versão',
        reason: 'a fila tem de carregar o texto ATUAL, nao o primeiro',
      );
      expect(v3.texto, 'terceira versão');
    });

    test('editar preserva criada_em e avança atualizado_em', () async {
      final v1 = await salvar('primeira');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final v2 = await salvar('segunda', anterior: v1);

      expect(v2.criadaEm, v1.criadaEm, reason: 'quando o bloco nasceu');
      expect(
        v2.atualizadoEm.isAfter(v1.atualizadoEm),
        isTrue,
        reason: 'quando foi editado — e o que a coordenacao ordena por',
      );
    });

    test('a chave do bloco não muda entre edições', () async {
      final v1 = await salvar('a');
      final v2 = await salvar('b', anterior: v1);
      expect(v2.blocoId, v1.blocoId);

      final fila = await Outbox.instance.pending(
        entity: AnotacaoService.entidade,
      );
      expect(fila.single.clientId, v1.blocoId);
    });

    test('depois de subir, uma edição nova entra na fila de novo', () async {
      SyncService.instance.registerUploader(
        AnotacaoService.entidade,
        (_) async {},
      );
      final v1 = await salvar('antes de subir');
      await SyncService.instance.syncNow();
      expect(await Outbox.instance.pendingCount(), 0);

      // `enqueueSubstituindo` só mexe em entrada PENDENTE; a que já subiu
      // não é tocada, e a edição entra como envio novo. O servidor resolve
      // pelo `onConflict: 'bloco_id'`.
      await salvar('depois de subir', anterior: v1);
      final fila = await Outbox.instance.pending(
        entity: AnotacaoService.entidade,
      );
      expect(fila.length, 1);
      expect(fila.single.payload['texto'], 'depois de subir');
    });
  });

  group('um bloco por membro, equipe, Top e participante', () {
    test('a chave separa os quatro', () {
      String chave({
        String top = 't',
        TeamKey team = TeamKey.seguranca,
        String autor = 'u',
        String? part,
      }) => Anotacao.chaveDe(
        topId: top,
        team: team,
        autorId: autor,
        participanteId: part,
      );

      final todas = {
        chave(),
        chave(top: 't2'),
        chave(team: TeamKey.midia),
        chave(autor: 'u2'),
        chave(part: 'p1'),
      };
      expect(todas.length, 5, reason: 'nenhuma combinacao colide');
    });

    test('o bloco do turno usa "-" no lugar do participante', () {
      // Não é detalhe: em Postgres NULL não conflita com NULL num índice
      // único, então dois blocos de turno da mesma pessoa não colidiriam e
      // virariam duplicata. O '-' resolve sem índice parcial — que
      // quebraria o upsert.
      expect(
        Anotacao.chaveDe(
          topId: 't',
          team: TeamKey.adm,
          autorId: 'u',
        ),
        't|adm|u|-',
      );
      expect(
        Anotacao.chaveDe(
          topId: 't',
          team: TeamKey.adm,
          autorId: 'u',
          participanteId: 'p1',
        ),
        't|adm|u|p1',
      );
    });

    test('bloco do turno e bloco sobre pessoa são independentes', () async {
      final turno = await salvar('do turno');
      final pessoa = await salvar('sobre a pessoa', participanteId: 'p-9');

      expect(turno.blocoId, isNot(pessoa.blocoId));
      expect(turno.sobrePessoa, isFalse);
      expect(pessoa.sobrePessoa, isTrue);

      final fila = await Outbox.instance.pending(
        entity: AnotacaoService.entidade,
      );
      expect(fila.length, 2, reason: 'dois blocos, duas entradas');
    });

    test('meuBlocoNaFila acha o bloco certo entre vários', () async {
      await salvar('do turno');
      await salvar('sobre p-9', participanteId: 'p-9');
      await salvar('da midia', team: TeamKey.midia);
      await salvar('de outro Top', topId: 'top-2');

      final daPessoa = await AnotacaoService.instance.meuBlocoNaFila(
        topId: 'top-1',
        team: TeamKey.seguranca,
        participanteId: 'p-9',
      );
      expect(daPessoa!.texto, 'sobre p-9');

      final doTurno = await AnotacaoService.instance.meuBlocoNaFila(
        topId: 'top-1',
        team: TeamKey.seguranca,
      );
      expect(doTurno!.texto, 'do turno');

      final daMidia = await AnotacaoService.instance.meuBlocoNaFila(
        topId: 'top-1',
        team: TeamKey.midia,
      );
      expect(daMidia!.texto, 'da midia');
    });

    test('bloco inexistente devolve null, não estoura', () async {
      final nada = await AnotacaoService.instance.meuBlocoNaFila(
        topId: 'top-nunca-usado',
        team: TeamKey.voz,
      );
      expect(nada, isNull);
    });
  });

  group('a equipe HAKUNAS existe no enum', () {
    test('é equipe, com rótulo próprio', () {
      // Faltava no banco e no app: a equipe de salvamento não tinha chat
      // nem anotação como as outras. `hakuna` continua sendo também um
      // PAPEL (`user_role`) — são coisas diferentes.
      expect(TeamKey.values.contains(TeamKey.hakunas), isTrue);
      expect(TeamKey.hakunas.label, 'Hakunas');
      expect(teamKeyFromString('hakunas'), TeamKey.hakunas);
    });

    test('são 9 equipes, e geral não é uma delas', () {
      expect(TeamKeyUi.equipes.length, 9);
      expect(TeamKeyUi.equipes.contains(TeamKey.geral), isFalse);
      expect(TeamKeyUi.equipes.contains(TeamKey.hakunas), isTrue);
    });

    test('dá para anotar na equipe hakunas', () async {
      final a = await salvar('Posto médico 2 sem soro', team: TeamKey.hakunas);
      expect(a.team, TeamKey.hakunas);
      final fila = await Outbox.instance.pending(
        entity: AnotacaoService.entidade,
      );
      expect(fila.single.payload['team'], 'hakunas');
    });
  });

  group('fromMap e toMap', () {
    test('lê o join do Postgrest como objeto e como lista', () {
      final comObjeto = Anotacao.fromMap({
        'bloco_id': 't|seguranca|u|-',
        'id': 'a1',
        'top_id': 't',
        'team': 'seguranca',
        'autor_id': 'u',
        'texto': 'x',
        'criada_em': '2026-10-11T12:00:00Z',
        'atualizado_em': '2026-10-11T13:00:00Z',
        'autor': {'full_name': 'JOAO'},
      });
      expect(comObjeto.autorNome, 'JOAO');

      // O Postgrest devolve relação como objeto OU como lista de um,
      // conforme a cardinalidade que infere.
      final comLista = Anotacao.fromMap({
        'bloco_id': 't|midia|u|-',
        'top_id': 't',
        'team': 'midia',
        'autor_id': 'u',
        'texto': 'x',
        'criada_em': '2026-10-11T12:00:00Z',
        'autor': [
          {'full_name': 'PEDRO'},
        ],
      });
      expect(comLista.autorNome, 'PEDRO');
    });

    test('sem atualizado_em, cai em criada_em', () {
      final a = Anotacao.fromMap({
        'bloco_id': 'b',
        'top_id': 't',
        'team': 'adm',
        'autor_id': 'u',
        'texto': 'x',
        'criada_em': '2026-10-11T12:00:00Z',
      });
      expect(a.atualizadoEm, a.criadaEm);
    });

    test('equipe desconhecida não derruba a tela', () {
      // Enum novo no banco com app antigo instalado. Pior que cair em
      // `geral` seria a lista inteira não abrir.
      final a = Anotacao.fromMap({
        'bloco_id': 'b',
        'top_id': 't',
        'team': 'equipe_que_nao_existe_ainda',
        'autor_id': 'u',
        'texto': 'x',
        'criada_em': '2026-10-11T12:00:00Z',
      });
      expect(a.team, TeamKey.geral);
    });

    test('toMap não leva id nem os nomes dos joins', () {
      final a = Anotacao(
        blocoId: 'b',
        id: 'id-do-servidor',
        topId: 't',
        team: TeamKey.voz,
        autorId: 'u',
        texto: 'x',
        criadaEm: DateTime.utc(2026, 10, 11, 12),
        atualizadoEm: DateTime.utc(2026, 10, 11, 13),
        autorNome: 'JOAO',
      );
      final m = a.toMap();

      // `id` nulo num upsert faria o Postgres recusar a chave primária; e
      // nome de join não é coluna desta tabela — mandá-lo daria erro de
      // coluna inexistente, classificado como PERMANENTE e quarentenado.
      expect(m.containsKey('id'), isFalse);
      expect(m.containsKey('autor'), isFalse);
      expect(m['bloco_id'], 'b');
      expect(m['team'], 'voz');
    });
  });
}
