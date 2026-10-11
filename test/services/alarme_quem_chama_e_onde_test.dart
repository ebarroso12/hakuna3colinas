import 'package:flutter_test/flutter_test.dart';
import 'package:legendario_connect/models/top_alert.dart';
import 'package:legendario_connect/offline/cache_local.dart';
import 'package:legendario_connect/offline/local_db.dart';
import 'package:legendario_connect/offline/outbox.dart';
import 'package:legendario_connect/offline/sync_service.dart';
import 'package:legendario_connect/offline/tabelas.dart';
import 'package:legendario_connect/services/alarme_service.dart';
import 'package:legendario_connect/services/supabase_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// As duas perguntas que uma emergência tem de responder: **onde é** e
/// **quem está chamando**.
///
/// Decisão do dono em 11/10/2026: "se alguma pessoa apertar emergência
/// todos devem ver o lugar via GPS e quem está chamando". A faixa de
/// alarme recebia `latitude`/`longitude` desde sempre e mostrava apenas
/// hora e mensagem — numa trilha com 200 pessoas, "ALARME — 14:32" não
/// diz a quem correr nem para onde.
///
/// O nome viaja DENTRO do alarme porque `profiles` é fechada para quem
/// recebe (`profiles_select_own_or_admin` = `id = auth.uid() or
/// is_admin()`): o destinatário não tem como resolver o uuid. E vem do
/// cache local porque o disparo não pode depender de rede.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AlarmeService.anunciarLigado = false;
  });

  setUp(() async {
    LocalDb.overridePathForTests = inMemoryDatabasePath;
    await LocalDb.instance.close();
    SyncService.instance.resetForTests();
    SupabaseService.idDeUsuarioParaTestes = 'perfil-1';
    AlarmeService.instance.limparParaTestes();
  });

  tearDown(() async {
    SupabaseService.idDeUsuarioParaTestes = null;
    await LocalDb.instance.close();
  });

  TopAlert alerta({
    String? senderName,
    double? latitude,
    double? longitude,
    String? message,
  }) => TopAlert.fromMap({
    'id': 1,
    'top_id': 'top-1',
    'sender_id': 'perfil-2',
    'sender_name': senderName,
    'message': message,
    'latitude': latitude,
    'longitude': longitude,
    'created_at': DateTime.now().toUtc().toIso8601String(),
  });

  group('quem está chamando', () {
    test('o nome vem no alarme e é o que a tela mostra', () {
      expect(alerta(senderName: 'Edson Barroso').quemChama, 'Edson Barroso');
      expect(alerta(senderName: 'Edson Barroso').temNome, isTrue);
    });

    test('sem nome NUNCA mostra uuid — diz o que é verdade', () {
      // Um uuid na faixa de emergência é pior que nada: ocupa a linha que
      // devia dizer um nome e não ajuda ninguém a achar a pessoa.
      final sem = alerta();
      expect(sem.quemChama, 'Alguém do Top');
      expect(sem.temNome, isFalse);
      expect(sem.quemChama, isNot(contains(sem.senderId)));
    });

    test('nome em branco ou só espaço conta como ausente', () {
      for (final vazio in ['', '   ', '\n']) {
        expect(alerta(senderName: vazio).temNome, isFalse, reason: '"$vazio"');
        expect(alerta(senderName: vazio).quemChama, 'Alguém do Top');
      }
    });

    test('alarme antigo, sem a coluna no payload, não estoura', () {
      // `sender_name` foi acrescentada em 11/10/2026. Linha gravada antes
      // disso chega sem a chave, e ler alarme antigo não pode quebrar a
      // faixa — ela é o caminho de uma emergência.
      final antigo = TopAlert.fromMap({
        'id': 9,
        'top_id': 'top-1',
        'sender_id': 'perfil-2',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      expect(antigo.senderName, isNull);
      expect(antigo.quemChama, 'Alguém do Top');
      expect(antigo.temPosicao, isFalse);
    });
  });

  group('onde é', () {
    test('temPosicao exige as DUAS coordenadas', () {
      expect(alerta(latitude: -19.9, longitude: -43.9).temPosicao, isTrue);
      // Meia coordenada não localiza nada, e oferecer "ver o lugar" com
      // ela levaria a um ponto no meio do oceano.
      expect(alerta(latitude: -19.9).temPosicao, isFalse);
      expect(alerta(longitude: -43.9).temPosicao, isFalse);
      expect(alerta().temPosicao, isFalse);
    });

    test('coordenada zero é posição válida, não ausência', () {
      // Clássico de `if (lat != 0)`. 0,0 é um ponto no Golfo da Guiné —
      // improvável num Top, mas tratá-lo como "sem posição" é o tipo de
      // atalho que esconde defeito de GPS em vez de mostrá-lo.
      expect(alerta(latitude: 0, longitude: 0).temPosicao, isTrue);
    });
  });

  group('o nome sai junto no disparo, inclusive offline', () {
    test('o disparo põe sender_name no payload da fila', () async {
      await CacheLocal.instance.guardarEstado(
        ColunasEstado.meuNome,
        'Edson Barroso',
      );

      await AlarmeService.instance.disparar(
        topId: 'top-1',
        mensagem: 'queda na trilha',
        latitude: -19.912998,
        longitude: -43.940933,
      );

      final fila = await Outbox.instance.pending(
        entity: AlarmeService.entidade,
      );
      expect(fila, hasLength(1));
      final alarme = fila.first;
      expect(alarme.payload['sender_name'], 'Edson Barroso');
      expect(alarme.payload['latitude'], -19.912998);
      expect(alarme.payload['longitude'], -43.940933);
      // E o `sender_id` continua sendo quem está logado: a RLS exige
      // `sender_id = auth.uid()`, e alarme falso atribuído a um colega
      // é acusação.
      expect(alarme.payload['sender_id'], 'perfil-1');
    });

    test('sem nome no cache o alarme SAI — sem nome, mas sai', () async {
      // Primeiro login sem sinal: o perfil nunca carregou, então não há
      // nome gravado. O alarme é a função mais crítica do app e não pode
      // ser bloqueada por um dado cosmético.
      await AlarmeService.instance.disparar(topId: 'top-1');

      final fila = await Outbox.instance.pending(
        entity: AlarmeService.entidade,
      );
      expect(fila, hasLength(1));
      final alarme = fila.first;
      expect(alarme.payload['sender_name'], isNull);
      expect(alarme.payload['sender_id'], 'perfil-1');
    });

    test('nomeDeQuemDispara normaliza espaço e trata vazio', () async {
      await CacheLocal.instance.guardarEstado(
        ColunasEstado.meuNome,
        '  Edson  ',
      );
      expect(await AlarmeService.instance.nomeDeQuemDispara(), 'Edson');

      await CacheLocal.instance.guardarEstado(ColunasEstado.meuNome, '   ');
      expect(await AlarmeService.instance.nomeDeQuemDispara(), isNull);
    });
  });
}
