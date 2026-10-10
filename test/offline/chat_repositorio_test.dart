import 'package:flutter_test/flutter_test.dart';
import 'package:hakuna_connect/models/chat_message.dart';
import 'package:hakuna_connect/models/team.dart';
import 'package:hakuna_connect/models/team_message.dart';
import 'package:hakuna_connect/offline/chat_repositorio.dart';
import 'package:hakuna_connect/offline/local_db.dart';
import 'package:hakuna_connect/offline/outbox.dart';
import 'package:hakuna_connect/offline/sync_service.dart';
import 'package:hakuna_connect/services/supabase_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    LocalDb.overridePathForTests = inMemoryDatabasePath;
    await LocalDb.instance.close();
    SyncService.instance.resetForTests();
    // Finge a sessão: o repositório precisa do id de quem envia, e subir o
    // Supabase inteiro num teste de unidade não prova nada sobre a fila.
    SupabaseService.idDeUsuarioParaTestes = 'hakuna-1';
  });

  tearDown(() async {
    SupabaseService.idDeUsuarioParaTestes = null;
    await LocalDb.instance.close();
  });

  final repo = ChatRepositorio.instance;

  TeamMessage doServidor({
    required int id,
    String? clientId,
    required String body,
    required DateTime em,
  }) => TeamMessage(
    id: id,
    clientId: clientId,
    topId: 'top-1',
    team: TeamKey.geral,
    senderId: 'hakuna-1',
    body: body,
    createdAt: em,
    isAlert: false,
  );

  TeamMessage pendente({
    required String clientId,
    required String body,
    required DateTime em,
  }) => TeamMessage(
    clientId: clientId,
    topId: 'top-1',
    team: TeamKey.geral,
    senderId: 'hakuna-1',
    body: body,
    createdAt: em,
    isAlert: false,
  );

  group('envio — vai para a fila, não para a rede', () {
    test('mensagem de equipe entra na fila com client_id no payload', () async {
      final m = await repo.enviarParaEquipe(
        topId: 'top-1',
        team: TeamKey.seguranca,
        body: 'participante caiu no km 8',
      );

      expect(m.pendente, isTrue, reason: 'sem id, ainda não subiu');
      expect(m.clientId, isNotNull);

      final fila = await Outbox.instance.pending(
        entity: ChatRepositorio.entityTeam,
      );
      expect(fila.length, 1);
      // O client_id tem de estar DENTRO do payload: é ele que o upsert usa
      // como onConflict. Só na linha da fila não serve — o servidor não vê.
      expect(fila.single.payload['client_id'], m.clientId);
      expect(fila.single.payload['team'], 'seguranca');
      expect(fila.single.payload['sender_id'], 'hakuna-1');
      expect(fila.single.payload['body'], 'participante caiu no km 8');
      expect(fila.single.payload['created_at'], isA<String>());
    });

    test('mensagem do Top entra na fila', () async {
      await repo.enviarParaTop(topId: 'top-1', body: 'subindo a serra');
      final fila = await Outbox.instance.pending(
        entity: ChatRepositorio.entityTop,
      );
      expect(fila.single.payload['body'], 'subindo a serra');
      expect(fila.single.payload['client_id'], isNotNull);
    });

    test('cada envio tem client_id próprio', () async {
      await repo.enviarParaEquipe(
        topId: 'top-1',
        team: TeamKey.geral,
        body: 'um',
      );
      await repo.enviarParaEquipe(
        topId: 'top-1',
        team: TeamKey.geral,
        body: 'dois',
      );
      final fila = await Outbox.instance.pending(
        entity: ChatRepositorio.entityTeam,
      );
      final ids = fila.map((e) => e.payload['client_id']).toSet();
      expect(ids.length, 2, reason: 'id repetido viraria mensagem perdida');
    });

    test('is_alert vai no payload — a RLS decide se aceita', () async {
      await repo.enviarParaEquipe(
        topId: 'top-1',
        team: TeamKey.seguranca,
        body: 'ALERTA',
        isAlert: true,
      );
      final fila = await Outbox.instance.pending(
        entity: ChatRepositorio.entityTeam,
      );
      expect(fila.single.payload['is_alert'], isTrue);
    });

    test('sem sessão, lança em vez de enfileirar mensagem sem autor', () async {
      SupabaseService.idDeUsuarioParaTestes = null;
      await expectLater(
        repo.enviarParaTop(topId: 'top-1', body: 'oi'),
        throwsA(isA<StateError>()),
      );
      expect(await Outbox.instance.pendingCount(), 0);
    });

    test('a mensagem pendente reconstrói do payload com fromMap', () async {
      final enviada = await repo.enviarParaEquipe(
        topId: 'top-1',
        team: TeamKey.logistica,
        body: 'faltou água no posto 2',
      );
      final fila = await Outbox.instance.pending(
        entity: ChatRepositorio.entityTeam,
      );
      // É esse caminho que a tela usa para mostrar a pendente.
      final reconstruida = TeamMessage.fromMap(fila.single.payload);
      expect(reconstruida.pendente, isTrue);
      expect(reconstruida.clientId, enviada.clientId);
      expect(reconstruida.team, TeamKey.logistica);
      expect(reconstruida.body, 'faltou água no posto 2');
    });
  });

  group('juntar — o bug da mensagem duplicada', () {
    final t0 = DateTime(2026, 10, 10, 9);

    test('pendente que já voltou do servidor NÃO aparece duas vezes', () {
      // Cenário real: o upload terminou e o realtime trouxe a mensagem,
      // mas a fila ainda não foi limpa. As duas cópias existem.
      final r = ChatRepositorio.juntar<TeamMessage>(
        doServidor: [
          doServidor(id: 1, clientId: 'cid-a', body: 'subiu', em: t0),
        ],
        pendentes: [pendente(clientId: 'cid-a', body: 'subiu', em: t0)],
        quando: (m) => m.createdAt,
        clientIdDe: (m) => m.clientId,
      );

      expect(r.mensagens.length, 1);
      expect(r.mensagens.single.pendente, isFalse, reason: 'vale a do servidor');
      expect(r.pendentes, 0);
    });

    test('pendente que ainda não subiu aparece, marcada', () {
      final r = ChatRepositorio.juntar<TeamMessage>(
        doServidor: [
          doServidor(id: 1, clientId: 'cid-a', body: 'antiga', em: t0),
        ],
        pendentes: [
          pendente(
            clientId: 'cid-b',
            body: 'nova',
            em: t0.add(const Duration(minutes: 5)),
          ),
        ],
        quando: (m) => m.createdAt,
        clientIdDe: (m) => m.clientId,
      );

      expect(r.mensagens.length, 2);
      expect(r.pendentes, 1);
      expect(r.mensagens.last.pendente, isTrue);
    });

    test('ordena por horário, misturando servidor e fila', () {
      final r = ChatRepositorio.juntar<TeamMessage>(
        doServidor: [
          doServidor(id: 1, clientId: 'a', body: '9h', em: t0),
          doServidor(
            id: 2,
            clientId: 'b',
            body: '11h',
            em: t0.add(const Duration(hours: 2)),
          ),
        ],
        pendentes: [
          pendente(
            clientId: 'c',
            body: '10h',
            em: t0.add(const Duration(hours: 1)),
          ),
        ],
        quando: (m) => m.createdAt,
        clientIdDe: (m) => m.clientId,
      );

      expect(r.mensagens.map((m) => m.body), ['9h', '10h', '11h']);
    });

    test('mensagem antiga sem client_id não é deduplicada por engano', () {
      // Mensagens anteriores à v1.0.18 têm client_id null. Dois nulls não
      // podem casar entre si: seriam mensagens diferentes escondidas.
      final r = ChatRepositorio.juntar<TeamMessage>(
        doServidor: [
          doServidor(id: 1, body: 'antiga do servidor', em: t0),
        ],
        pendentes: [
          pendente(
            clientId: 'cid-novo',
            body: 'nova da fila',
            em: t0.add(const Duration(minutes: 1)),
          ),
        ],
        quando: (m) => m.createdAt,
        clientIdDe: (m) => m.clientId,
      );
      expect(r.mensagens.length, 2);
      expect(r.pendentes, 1);
    });

    test('fila vazia e servidor vazio devolve lista vazia, não erro', () {
      final r = ChatRepositorio.juntar<TeamMessage>(
        doServidor: const [],
        pendentes: const [],
        quando: (m) => m.createdAt,
        clientIdDe: (m) => m.clientId,
      );
      expect(r.mensagens, isEmpty);
      expect(r.pendentes, 0);
      expect(r.offline, isFalse);
    });

    test('erro de rede é carregado junto das mensagens, não em vez delas', () {
      // Era o bug da tela antiga: `hasError` escondia o histórico inteiro.
      final r = ChatRepositorio.juntar<TeamMessage>(
        doServidor: [doServidor(id: 1, clientId: 'a', body: 'oi', em: t0)],
        pendentes: const [],
        quando: (m) => m.createdAt,
        clientIdDe: (m) => m.clientId,
        erroDeRede: 'socket fechado',
      );
      expect(r.offline, isTrue);
      expect(r.mensagens.length, 1, reason: 'histórico continua visível');
    });

    test('funciona igual para o chat do Top (ChatMessage)', () {
      final r = ChatRepositorio.juntar<ChatMessage>(
        doServidor: [
          ChatMessage(
            id: 1,
            clientId: 'cid-a',
            topId: 'top-1',
            senderId: 'h1',
            body: 'subiu',
            createdAt: t0,
          ),
        ],
        pendentes: [
          ChatMessage(
            clientId: 'cid-a',
            topId: 'top-1',
            senderId: 'h1',
            body: 'subiu',
            createdAt: t0,
          ),
        ],
        quando: (m) => m.createdAt,
        clientIdDe: (m) => m.clientId,
      );
      expect(r.mensagens.length, 1);
      expect(r.mensagens.single.pendente, isFalse);
    });
  });

  group('contagem de pendentes', () {
    test('soma os dois chats', () async {
      await repo.enviarParaEquipe(
        topId: 'top-1',
        team: TeamKey.geral,
        body: 'a',
      );
      await repo.enviarParaTop(topId: 'top-1', body: 'b');
      expect(await repo.pendentesDeEnvio(), 2);
    });
  });
}
