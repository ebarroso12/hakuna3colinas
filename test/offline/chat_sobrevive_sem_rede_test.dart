import 'package:flutter_test/flutter_test.dart';
import 'package:legendario_connect/offline/cache_local.dart';
import 'package:legendario_connect/offline/chat_repositorio.dart';
import 'package:legendario_connect/offline/local_db.dart';
import 'package:legendario_connect/offline/tabelas.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A conversa da equipe tem de existir sem rede.
///
/// Até a v1.0.40 o chat juntava o stream do Supabase com a fila local, e
/// mais nada. Sem rede o stream fica **calado** — não emite lista vazia
/// nem erro imediato —, então a tela mostrava apenas o que o próprio
/// usuário tinha escrito. A conversa da equipe sumia.
///
/// No mato isso é o oposto do que se precisa: quem chega ao acampamento
/// sem sinal é justamente quem mais precisa ler o que foi combinado
/// enquanto estava fora.
///
/// Este cache também é a base para entrega entre aparelhos: sem um lugar
/// onde guardar, não há o que trocar por Bluetooth nem onde escrever o
/// que chegou.
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

  Map<String, Object?> msg({
    required int id,
    required String corpo,
    String top = 'top-1',
    String? team = 'seguranca',
    bool alerta = false,
    String? criadaEm,
  }) => {
    'id': id,
    'client_id': 'c$id',
    'top_id': top,
    'team': team,
    'sender_id': 'perfil-2',
    'body': corpo,
    'is_alert': alerta,
    'created_at': criadaEm ?? '2026-10-12T0$id:00:00.000Z',
    'edited_at': null,
  };

  group('a conversa sobrevive no disco', () {
    test('o que foi salvo volta, na ordem em que a tela desenha', () async {
      await CacheLocal.instance.salvarMensagens(
        entidade: ChatRepositorio.entityTeam,
        linhas: [
          msg(id: 3, corpo: 'terceira'),
          msg(id: 1, corpo: 'primeira'),
          msg(id: 2, corpo: 'segunda'),
        ],
      );

      final lidas = await CacheLocal.instance.lerMensagens(
        entidade: ChatRepositorio.entityTeam,
        topId: 'top-1',
        team: 'seguranca',
      );

      // Da mais velha para a mais nova — a ordem de leitura de um chat.
      expect(lidas.map((m) => m['body']), ['primeira', 'segunda', 'terceira']);
    });

    test('mensagem editada SOBRESCREVE, nao duplica', () async {
      const entidade = ChatRepositorio.entityTeam;
      await CacheLocal.instance.salvarMensagens(
        entidade: entidade,
        linhas: [msg(id: 7, corpo: 'texto original')],
      );
      await CacheLocal.instance.salvarMensagens(
        entidade: entidade,
        linhas: [msg(id: 7, corpo: 'texto corrigido')],
      );

      final lidas = await CacheLocal.instance.lerMensagens(
        entidade: entidade,
        topId: 'top-1',
        team: 'seguranca',
      );
      expect(lidas, hasLength(1));
      expect(lidas.first['body'], 'texto corrigido');
    });

    test('as 9 equipes nao se misturam', () async {
      await CacheLocal.instance.salvarMensagens(
        entidade: ChatRepositorio.entityTeam,
        linhas: [
          msg(id: 1, corpo: 'da seguranca', team: 'seguranca'),
          msg(id: 2, corpo: 'da midia', team: 'midia'),
          msg(id: 3, corpo: 'dos hakunas', team: 'hakunas'),
        ],
      );

      for (final par in [
        ('seguranca', 'da seguranca'),
        ('midia', 'da midia'),
        ('hakunas', 'dos hakunas'),
      ]) {
        final lidas = await CacheLocal.instance.lerMensagens(
          entidade: ChatRepositorio.entityTeam,
          topId: 'top-1',
          team: par.$1,
        );
        expect(lidas, hasLength(1), reason: par.$1);
        expect(lidas.first['body'], par.$2);
      }
    });

    test('Tops diferentes nao se misturam', () async {
      await CacheLocal.instance.salvarMensagens(
        entidade: ChatRepositorio.entityTeam,
        linhas: [
          msg(id: 1, corpo: 'do top 1', top: 'top-1'),
          msg(id: 2, corpo: 'do top 2', top: 'top-2'),
        ],
      );
      final doUm = await CacheLocal.instance.lerMensagens(
        entidade: ChatRepositorio.entityTeam,
        topId: 'top-1',
        team: 'seguranca',
      );
      expect(doUm, hasLength(1));
      expect(doUm.first['body'], 'do top 1');
    });
  });

  group('os dois chats dividem a tabela sem colidir', () {
    test('mesmo id em entidades diferentes NAO se sobrescreve', () async {
      // `team_messages.id` e `top_hakuna_messages.id` sao sequencias
      // INDEPENDENTES no Postgres: as duas tem id 1. Se a chave local
      // fosse o id cru, uma apagaria a outra — e o chat clinico perderia
      // mensagem sem erro nenhum. Dai a chave ser `<entidade>|<id>`.
      await CacheLocal.instance.salvarMensagens(
        entidade: ChatRepositorio.entityTeam,
        linhas: [msg(id: 1, corpo: 'da equipe')],
      );
      await CacheLocal.instance.salvarMensagens(
        entidade: ChatRepositorio.entityTop,
        linhas: [msg(id: 1, corpo: 'do chat clinico', team: null)],
      );

      expect(await CacheLocal.instance.contarMensagens(), 2);

      final daEquipe = await CacheLocal.instance.lerMensagens(
        entidade: ChatRepositorio.entityTeam,
        topId: 'top-1',
        team: 'seguranca',
      );
      final doClinico = await CacheLocal.instance.lerMensagens(
        entidade: ChatRepositorio.entityTop,
        topId: 'top-1',
      );
      expect(daEquipe.first['body'], 'da equipe');
      expect(doClinico.first['body'], 'do chat clinico');
    });

    test('team null busca o clinico — igualdade nunca casaria', () async {
      // Em SQL, `coluna = NULL` nao casa NUNCA, nem com NULL. Escrito com
      // igualdade, esta consulta devolveria lista vazia para sempre e
      // pareceria "o cache nao funcionou".
      await CacheLocal.instance.salvarMensagens(
        entidade: ChatRepositorio.entityTop,
        linhas: [msg(id: 5, corpo: 'clinico', team: null)],
      );
      final lidas = await CacheLocal.instance.lerMensagens(
        entidade: ChatRepositorio.entityTop,
        topId: 'top-1',
      );
      expect(lidas, hasLength(1));
      expect(lidas.first['team'], isNull);
    });
  });

  group('detalhes que silenciam defeito', () {
    test('is_alert volta como bool, nao como 0 ou 1', () async {
      // SQLite nao tem boolean. Se voltasse inteiro, `TeamMessage.fromMap`
      // faria `map['is_alert'] as bool?` estourar — e o chat inteiro
      // quebraria ao ler um alerta guardado.
      await CacheLocal.instance.salvarMensagens(
        entidade: ChatRepositorio.entityTeam,
        linhas: [
          msg(id: 1, corpo: 'normal'),
          msg(id: 2, corpo: 'urgente', alerta: true),
        ],
      );
      final lidas = await CacheLocal.instance.lerMensagens(
        entidade: ChatRepositorio.entityTeam,
        topId: 'top-1',
        team: 'seguranca',
      );
      expect(lidas[0]['is_alert'], isFalse);
      expect(lidas[1]['is_alert'], isTrue);
      expect(lidas[1]['is_alert'], isA<bool>());
    });

    test('a hora sobrevive à ida e volta, em UTC', () async {
      await CacheLocal.instance.salvarMensagens(
        entidade: ChatRepositorio.entityTeam,
        linhas: [msg(id: 1, corpo: 'x', criadaEm: '2026-10-12T03:04:05.000Z')],
      );
      final lidas = await CacheLocal.instance.lerMensagens(
        entidade: ChatRepositorio.entityTeam,
        topId: 'top-1',
        team: 'seguranca',
      );
      final volta = DateTime.parse(lidas.first['created_at']! as String);
      expect(volta.toUtc(), DateTime.utc(2026, 10, 12, 3, 4, 5));
    });

    test('lista vazia nao estoura', () async {
      await CacheLocal.instance.salvarMensagens(
        entidade: ChatRepositorio.entityTeam,
        linhas: const [],
      );
      expect(await CacheLocal.instance.contarMensagens(), 0);
    });

    test('o limite devolve as mais NOVAS, nao as mais velhas', () async {
      // Poda errada guardaria o comeco da conversa e jogaria fora o fim —
      // exatamente o contrario do que serve a quem chega sem sinal.
      await CacheLocal.instance.salvarMensagens(
        entidade: ChatRepositorio.entityTeam,
        linhas: [
          for (var i = 1; i <= 5; i++)
            msg(id: i, corpo: 'msg$i', criadaEm: '2026-10-12T0$i:00:00.000Z'),
        ],
      );
      final lidas = await CacheLocal.instance.lerMensagens(
        entidade: ChatRepositorio.entityTeam,
        topId: 'top-1',
        team: 'seguranca',
        limite: 2,
      );
      expect(lidas.map((m) => m['body']), ['msg4', 'msg5']);
    });
  });

  test('a tabela existe no esquema novo (migracao v5)', () async {
    expect(Tabelas.mensagens, 'cache_mensagens');
    // Se a migracao nao rodasse, qualquer consulta estouraria aqui.
    expect(await CacheLocal.instance.contarMensagens(), 0);
  });
}
