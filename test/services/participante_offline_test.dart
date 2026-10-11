import 'package:flutter_test/flutter_test.dart';
import 'package:legendario_connect/offline/dados_do_top.dart';
import 'package:legendario_connect/offline/local_db.dart';
import 'package:legendario_connect/offline/outbox.dart';
import 'package:legendario_connect/offline/sync_service.dart';
import 'package:legendario_connect/services/participante_service.dart';
import 'package:legendario_connect/services/supabase_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// O defeito: **cadastrar ou editar ficha sem sinal perdia tudo.**
///
/// O formulário de participante gravava direto no Supabase, e ele é aberto
/// de duas telas de campo — "Novo" na lista de participantes e "Editar"
/// dentro da ficha. O Hakuna digitava a ficha inteira de alguém no mato,
/// com comorbidade e alergia, tocava em salvar e recebia uma mensagem
/// técnica. O dado não ia para lugar nenhum.
///
/// Era a mesma falha do alarme e dos sinais vitais: escrita de dado
/// clínico fora da fila.
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
    // `ParticipanteService` dispara `unawaited(syncNow())` ao salvar — em
    // produção é o que faz a ficha subir na hora quando há sinal. Aqui
    // essa rodada continuaria viva depois do teste e esbarraria no banco
    // já fechado. Esperar por ela é o que torna o teste determinístico.
    await SyncService.instance.rodadaEmAndamento;
    SupabaseService.idDeUsuarioParaTestes = null;
    await LocalDb.instance.close();
  });

  Map<String, dynamic> ficha({String nome = 'JOAO DA SILVA'}) => {
    'full_name': nome,
    'participant_code': '203460',
    'familia': 'ÁGUIA',
    'comorbidades': ['Hipertensão'],
    'alergias': 'dipirona',
    'blood_type': 'O+',
    'active': true,
  };

  group('cadastro sem rede', () {
    test('o participante aparece NA LISTA na hora, sem rede', () async {
      // É a parte que não pode faltar: salvar e não achar a pessoa que se
      // acabou de cadastrar faria o Hakuna cadastrar de novo.
      final p = await ParticipanteService.instance.criar(
        topId: 'top-1',
        dados: ficha(),
      );

      final lista = await DadosDoTop.instance.participantes('top-1');
      expect(lista.map((e) => e.id), contains(p.id));
      expect(lista.single.fullName, 'JOAO DA SILVA');
      expect(lista.single.comorbidades, ['Hipertensão']);
    });

    test('e TAMBÉM entra na fila para subir depois', () async {
      await ParticipanteService.instance.criar(
        topId: 'top-1',
        dados: ficha(),
      );
      final fila = await Outbox.instance.pending(
        entity: ParticipanteService.entidade,
      );
      expect(fila.length, 1);
      expect(fila.single.payload['full_name'], 'JOAO DA SILVA');
      expect(fila.single.payload['alergias'], 'dipirona');
    });

    test('o id vem do APARELHO e é um uuid', () async {
      // Sem id local o cadastro offline não teria identidade: não daria
      // para abrir a ficha nem registrar atendimento antes de ter rede.
      final p = await ParticipanteService.instance.criar(
        topId: 'top-1',
        dados: ficha(),
      );
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-'
          r'[0-9a-f]{12}$',
        ).hasMatch(p.id),
        isTrue,
        reason: 'top_participants.id e uuid no Postgres',
      );
    });

    test('o id da fila é o MESMO do participante — reenvio não duplica',
        () async {
      final p = await ParticipanteService.instance.criar(
        topId: 'top-1',
        dados: ficha(),
      );
      final e = (await Outbox.instance.pending(
        entity: ParticipanteService.entidade,
      )).single;
      expect(e.clientId, p.id);
      expect(e.payload['id'], p.id);
    });

    test('registered_by é quem está logado', () async {
      await ParticipanteService.instance.criar(
        topId: 'top-1',
        dados: ficha(),
      );
      final e = (await Outbox.instance.pending(
        entity: ParticipanteService.entidade,
      )).single;
      // `registered_by` e NOT NULL na tabela, e e o que permite saber
      // depois quem colocou cada pessoa no Top.
      expect(e.payload['registered_by'], 'hakuna-1');
    });

    test('sem sessão, não grava meia ficha: lança', () async {
      SupabaseService.idDeUsuarioParaTestes = null;
      await expectLater(
        ParticipanteService.instance.criar(topId: 'top-1', dados: ficha()),
        throwsA(isA<StateError>()),
      );
      expect(await Outbox.instance.pendingCount(), 0);
      expect(await DadosDoTop.instance.participantes('top-1'), isEmpty);
    });
  });

  group('edição sem rede', () {
    test('altera o que está no aparelho e enfileira a mudança', () async {
      final p = await ParticipanteService.instance.criar(
        topId: 'top-1',
        dados: ficha(),
      );

      await ParticipanteService.instance.atualizar(
        id: p.id,
        topId: 'top-1',
        dados: {...ficha(nome: 'JOAO DA SILVA JUNIOR'), 'alergias': null},
      );

      final lista = await DadosDoTop.instance.participantes('top-1');
      expect(lista.length, 1, reason: 'edicao nao cria um segundo');
      expect(lista.single.fullName, 'JOAO DA SILVA JUNIOR');
      expect(
        lista.single.alergias,
        isNull,
        reason: 'limpar um campo tem de limpar de verdade',
      );
    });

    test('a edição reaproveita o mesmo id na fila', () async {
      final p = await ParticipanteService.instance.criar(
        topId: 'top-1',
        dados: ficha(),
      );
      await ParticipanteService.instance.atualizar(
        id: p.id,
        topId: 'top-1',
        dados: ficha(nome: 'OUTRO NOME'),
      );
      final ids = (await Outbox.instance.pending(
        entity: ParticipanteService.entidade,
      )).map((e) => e.clientId).toSet();
      expect(ids, {p.id});
    });
  });

  group('o que está esperando sinal', () {
    test('idsNaFila lista só os do Top pedido', () async {
      final a = await ParticipanteService.instance.criar(
        topId: 'top-1',
        dados: ficha(),
      );
      await ParticipanteService.instance.criar(
        topId: 'top-2',
        dados: ficha(nome: 'DE OUTRO TOP'),
      );

      final naFila = await ParticipanteService.instance.idsNaFila('top-1');
      expect(naFila, {a.id});
    });

    test('depois de subir, não está mais na fila', () async {
      SyncService.instance.registerUploader(
        ParticipanteService.entidade,
        (_) async {},
      );
      final p = await ParticipanteService.instance.criar(
        topId: 'top-1',
        dados: ficha(),
      );
      await SyncService.instance.syncNow();

      expect(await ParticipanteService.instance.idsNaFila('top-1'), isEmpty);
      // E continua no aparelho: sincronizar não apaga o cache.
      final lista = await DadosDoTop.instance.participantes('top-1');
      expect(lista.map((e) => e.id), contains(p.id));
    });
  });
}
