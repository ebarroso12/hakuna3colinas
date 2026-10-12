import 'package:flutter_test/flutter_test.dart';
import 'package:legendario_connect/models/team_message.dart';
import 'package:legendario_connect/offline/cache_local.dart';
import 'package:legendario_connect/offline/chat_repositorio.dart';
import 'package:legendario_connect/offline/local_db.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Mensagem que chega pelo RÁDIO local não é autenticada, e isso tem de
/// sobreviver até a tela.
///
/// No servidor a RLS prende `sender_id = auth.uid()`: é impossível falar
/// no nome de outro. Pelo rádio, qualquer aparelho ao alcance pode
/// afirmar o que quiser de quem quiser.
///
/// Numa emergência isso move gente — "o coordenador mandou descer"
/// forjado tira 200 pessoas do lugar. Esconder a diferença seria pior
/// que não ter a funcionalidade, e é isso que estes testes travam.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    LocalDb.overridePathForTests = inMemoryDatabasePath;
    await LocalDb.instance.close();
  });

  tearDown(() async => LocalDb.instance.close());

  Future<bool> doRadio({
    String clientId = 'c1',
    String autorNome = 'Edson Barroso',
    String corpo = 'queda no km 4',
  }) => CacheLocal.instance.salvarMensagemDoRadio(
    entidade: ChatRepositorio.entityTeam,
    clientId: clientId,
    topId: 'top-1',
    team: 'seguranca',
    autorId: 'perfil-2',
    autorNome: autorNome,
    corpo: corpo,
    criadaEm: DateTime.utc(2026, 10, 12, 10),
  );

  Future<List<Map<String, Object?>>> ler() => CacheLocal.instance.lerMensagens(
    entidade: ChatRepositorio.entityTeam,
    topId: 'top-1',
    team: 'seguranca',
  );

  group('o que vem do rádio nasce NÃO confirmado', () {
    test('e o model carrega isso até a tela', () async {
      expect(await doRadio(), isTrue);

      final lidas = await ler();
      expect(lidas, hasLength(1));
      expect(lidas.first['confirmada'], isFalse);

      // O caminho completo: disco -> model -> tela.
      final m = TeamMessage.fromMap(Map<String, dynamic>.from(lidas.first));
      expect(m.confirmada, isFalse);
      expect(m.semAutoriaConfirmada, isTrue);
      expect(m.senderName, 'Edson Barroso');
    });

    test('o que vem do SERVIDOR nasce confirmado', () async {
      await CacheLocal.instance.salvarMensagens(
        entidade: ChatRepositorio.entityTeam,
        linhas: [
          {
            'id': 1,
            'client_id': 'c9',
            'top_id': 'top-1',
            'team': 'seguranca',
            'sender_id': 'perfil-2',
            'body': 'veio do supabase',
            'is_alert': false,
            'created_at': '2026-10-12T10:00:00.000Z',
            'edited_at': null,
          },
        ],
      );
      final m = TeamMessage.fromMap(Map<String, dynamic>.from((await ler()).first));
      expect(m.confirmada, isTrue);
    });

    test('mensagem sem o campo é tratada como CONFIRMADA', () async {
      // Toda mensagem do Supabase chega sem este campo. Se o padrão fosse
      // `false`, o chat inteiro apareceria marcado como não confiável — e
      // um aviso que aparece em tudo deixa de ser aviso.
      final m = TeamMessage.fromMap({
        'id': 1,
        'top_id': 'top-1',
        'team': 'seguranca',
        'sender_id': 'p',
        'body': 'x',
        'created_at': '2026-10-12T10:00:00.000Z',
      });
      expect(m.confirmada, isTrue);
    });
  });

  group('o servidor CONFIRMA o que o rádio entregou antes', () {
    test('a linha do rádio some e fica só a autenticada', () async {
      // Cenário real: a mensagem chega pelo rádio no mato, a pessoa lê, e
      // horas depois o aparelho recupera sinal e a mesma mensagem vem do
      // Supabase. Se as duas ficassem, a pessoa veria a mesma frase duas
      // vezes — uma com aviso e outra sem — e não saberia em qual
      // acreditar. Isso é pior que duplicar.
      await doRadio(clientId: 'mesma', corpo: 'texto da mensagem');
      expect((await ler()).first['confirmada'], isFalse);

      await CacheLocal.instance.salvarMensagens(
        entidade: ChatRepositorio.entityTeam,
        linhas: [
          {
            'id': 42,
            'client_id': 'mesma',
            'top_id': 'top-1',
            'team': 'seguranca',
            'sender_id': 'perfil-2',
            'body': 'texto da mensagem',
            'is_alert': false,
            'created_at': '2026-10-12T10:00:00.000Z',
            'edited_at': null,
          },
        ],
      );

      final lidas = await ler();
      expect(lidas, hasLength(1), reason: 'nao pode sobrar a copia do radio');
      expect(lidas.first['confirmada'], isTrue);
      expect(lidas.first['id'], 42);
    });

    test('depois de confirmada, o rádio não a rebaixa de novo', () async {
      // A malha repassa o mesmo pacote por vários caminhos. Se um deles
      // chegar DEPOIS da confirmação, não pode transformar uma mensagem
      // autenticada em "não confirmada".
      await CacheLocal.instance.salvarMensagens(
        entidade: ChatRepositorio.entityTeam,
        linhas: [
          {
            'id': 7,
            'client_id': 'c7',
            'top_id': 'top-1',
            'team': 'seguranca',
            'sender_id': 'perfil-2',
            'body': 'autenticada',
            'is_alert': false,
            'created_at': '2026-10-12T10:00:00.000Z',
            'edited_at': null,
          },
        ],
      );

      expect(
        await doRadio(clientId: 'c7', corpo: 'tentativa de rebaixar'),
        isFalse,
        reason: 'ja existe versao confirmada',
      );

      final lidas = await ler();
      expect(lidas, hasLength(1));
      expect(lidas.first['confirmada'], isTrue);
      expect(lidas.first['body'], 'autenticada');
    });
  });

  group('a malha entrega o mesmo pacote várias vezes', () {
    test('o segundo recebimento não duplica e devolve false', () async {
      expect(await doRadio(clientId: 'repetida'), isTrue);
      expect(await doRadio(clientId: 'repetida'), isFalse);
      expect(await doRadio(clientId: 'repetida'), isFalse);
      expect(await ler(), hasLength(1));
    });

    test('clientIds diferentes coexistem', () async {
      await doRadio(clientId: 'a', corpo: 'primeira');
      await doRadio(clientId: 'b', corpo: 'segunda');
      expect(await ler(), hasLength(2));
    });
  });

  test('mensagem do rádio NÃO tem id de servidor', () async {
    // Ela nunca passou por lá. `id` null é o que `TeamMessage.pendente`
    // usa para mostrar o relógio — e é verdade: ainda não chegou ao
    // servidor.
    await doRadio();
    final m = TeamMessage.fromMap(Map<String, dynamic>.from((await ler()).first));
    expect(m.id, isNull);
    expect(m.pendente, isTrue);
  });
}
