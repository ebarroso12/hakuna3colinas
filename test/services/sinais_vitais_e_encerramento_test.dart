import 'package:flutter_test/flutter_test.dart';
import 'package:legendario_connect/models/vital_signs.dart';
import 'package:legendario_connect/offline/local_db.dart';
import 'package:legendario_connect/offline/outbox.dart';
import 'package:legendario_connect/offline/sync_service.dart';
import 'package:legendario_connect/services/atendimento_service.dart';
import 'package:legendario_connect/services/sinais_vitais_service.dart';
import 'package:legendario_connect/services/supabase_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Dois defeitos diferentes, travados no mesmo arquivo porque os dois
/// nasceram da mesma causa: campo que o banco tem e o app não usava.
///
/// **Sinais vitais** iam direto ao Supabase, sem fila. Offline a medição
/// era perdida — o Hakuna media a pressão, via "registrado" e o dado não
/// existia em lugar nenhum. E não alimentavam `cache_ultima_afericao`,
/// então não reclassificavam a triagem: SpO₂ 85 medido no formulário de
/// atendimento pintava de vermelho, o mesmo 85 nesta tela não pintava
/// nada.
///
/// **Atendimento nunca fechava.** `status` só vinha do default da coluna e
/// `closed_at`/`closed_by` nunca eram escritos. Todo atendimento ficava
/// `aberto` para sempre, e numa lista de 30 não se distinguia quem ainda
/// precisava de atenção.
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

  group('sinais vitais pela fila', () {
    test('sem rede, a aferição FICA guardada', () async {
      await SinaisVitaisService.instance.registrar(
        topId: 'top-1',
        profileId: 'perfil-9',
        systolicBp: 190,
        diastolicBp: 115,
        spo2: 88,
      );

      final fila = await Outbox.instance.pending(
        entity: SinaisVitaisService.entidade,
      );
      expect(fila.length, 1);
      expect(fila.single.payload['systolic_bp'], 190);
      expect(fila.single.payload['spo2'], 88);
      expect(fila.single.payload['profile_id'], 'perfil-9');
    });

    test('leva client_id no payload, igual ao da linha da fila', () async {
      await SinaisVitaisService.instance.registrar(
        topId: 'top-1',
        profileId: 'perfil-9',
        spo2: 97,
      );
      final e = (await Outbox.instance.pending(
        entity: SinaisVitaisService.entidade,
      )).single;
      expect(e.payload['client_id'], isNotNull);
      expect(e.payload['client_id'], e.clientId);
    });

    test('a hora é do aparelho e vai no payload', () async {
      await SinaisVitaisService.instance.registrar(
        topId: 'top-1',
        profileId: 'perfil-9',
        spo2: 97,
      );
      final e = (await Outbox.instance.pending(
        entity: SinaisVitaisService.entidade,
      )).single;
      expect(e.payload['recorded_at'], isNotNull);
      // Sem o campo, o default `now()` do Postgres gravaria a hora do
      // upload — horas depois da medição, na trilha.
      final quando = DateTime.parse(e.payload['recorded_at'] as String);
      expect(
        DateTime.now().toUtc().difference(quando).inMinutes.abs(),
        lessThan(2),
      );
    });

    test('pendentesDe devolve só as deste perfil neste Top', () async {
      await SinaisVitaisService.instance.registrar(
        topId: 'top-1',
        profileId: 'perfil-9',
        spo2: 90,
      );
      await SinaisVitaisService.instance.registrar(
        topId: 'top-1',
        profileId: 'outro',
        spo2: 95,
      );
      await SinaisVitaisService.instance.registrar(
        topId: 'top-2',
        profileId: 'perfil-9',
        spo2: 99,
      );

      final minhas = await SinaisVitaisService.instance.pendentesDe(
        topId: 'top-1',
        profileId: 'perfil-9',
      );
      expect(minhas.length, 1);
      expect(minhas.single['spo2'], 90);
    });

    test('sem sessão, lança em vez de gravar sem autor', () async {
      SupabaseService.idDeUsuarioParaTestes = null;
      await expectLater(
        SinaisVitaisService.instance.registrar(
          topId: 'top-1',
          profileId: 'perfil-9',
          spo2: 90,
        ),
        throwsA(isA<StateError>()),
      );
      expect(await Outbox.instance.pendingCount(), 0);
    });
  });

  group('resumo a partir do payload da fila', () {
    test('não exige id — era o que estourava', () {
      // `VitalSigns.fromMap` faz `map['id'] as int`, e o payload da fila
      // não tem `id`: usá-lo na tela estourava em tempo de execução, sem
      // o analisador reclamar.
      final payload = {
        'top_id': 'top-1',
        'profile_id': 'perfil-9',
        'systolic_bp': 190,
        'diastolic_bp': 115,
        'spo2': 88,
      };
      expect(
        VitalSigns.resumoDoPayload(payload),
        'PA 190/115 · SpO2 88%',
      );
    });

    test('payload vazio não vira string vazia', () {
      expect(VitalSigns.resumoDoPayload({}), 'Sem valores registrados');
    });

    test('o resumo do model e o do payload são o mesmo texto', () {
      // Se divergirem, a mesma aferição aparece escrita de dois jeitos
      // conforme esteja na fila ou no servidor.
      final v = VitalSigns(
        id: 1,
        topId: 't',
        profileId: 'p',
        recordedBy: 'h',
        systolicBp: 120,
        diastolicBp: 80,
        heartRate: 78,
        spo2: 97,
        temperatureC: 36.8,
        respiratoryRate: 16,
        recordedAt: DateTime.now(),
      );
      expect(
        v.summary,
        VitalSigns.resumoDoPayload({
          'systolic_bp': 120,
          'diastolic_bp': 80,
          'heart_rate': 78,
          'spo2': 97,
          'temperature_c': 36.8,
          'respiratory_rate': 16,
        }),
      );
    });
  });

  group('encerrar atendimento', () {
    test('entra na fila como UPDATE, não como insert', () async {
      await AtendimentoService.instance.encerrar(
        clientIdDoAtendimento: 'abc',
        topId: 'top-1',
      );
      final e = (await Outbox.instance.pending(
        entity: AtendimentoService.entityAtendimento,
      )).single;

      // É o que distingue encerramento de registro novo. O uploader
      // escolhe o caminho por este campo: `upsert(ignoreDuplicates)` para
      // insert e `update` para este. Tratar os dois como insert faria o
      // encerramento ser IGNORADO — a linha já existe.
      expect(e.operation, OutboxOperation.update);
      expect(e.payload['status'], 'encerrado');
      expect(e.payload['client_id'], 'abc');
      expect(e.payload['closed_by'], 'hakuna-1');
      expect(e.payload['closed_at'], isNotNull);
    });

    test('a chave é o client_id, não o id do servidor', () async {
      // Offline o atendimento pode não ter subido ainda: não existe `id`
      // do servidor para apontar.
      await AtendimentoService.instance.encerrar(
        clientIdDoAtendimento: 'abc',
        topId: 'top-1',
      );
      final e = (await Outbox.instance.pending(
        entity: AtendimentoService.entityAtendimento,
      )).single;
      expect(e.payload.containsKey('id'), isFalse);
    });

    test('sem sessão, não encerra em nome de ninguém', () async {
      SupabaseService.idDeUsuarioParaTestes = null;
      await expectLater(
        AtendimentoService.instance.encerrar(
          clientIdDoAtendimento: 'abc',
          topId: 'top-1',
        ),
        throwsA(isA<StateError>()),
      );
      expect(await Outbox.instance.pendingCount(), 0);
    });
  });
}
