import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legendario_connect/models/top.dart';
import 'package:legendario_connect/offline/cache_local.dart';
import 'package:legendario_connect/offline/local_db.dart';
import 'package:legendario_connect/offline/tabelas.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A lista de Tops no disco é o que leva quem entrou sem servidor até a
/// tela do Top — onde estão EMERGÊNCIA, a leitura da pulseira e os
/// participantes guardados. Sem ela, o `AuthGate` deixava passar e a
/// pessoa caía numa tela de erro sem saída.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  final cache = CacheLocal.instance;

  Top top(
    String id, {
    String nome = 'Top',
    String? numero,
    DateTime? inicio,
    TopStatus status = TopStatus.active,
    bool autocadastro = true,
  }) => Top(
    id: id,
    name: nome,
    topNumber: numero,
    location: 'Fazenda 3 Colinas',
    cidade: 'Itabirito',
    diretorResponsavel: null,
    emblemaPath: 'tops/$id/emblema',
    description: 'descrição',
    status: status,
    startsAt: inicio,
    endsAt: inicio?.add(const Duration(days: 3)),
    autocadastroLiberado: autocadastro,
  );

  group('em memória', () {
    setUp(() async {
      LocalDb.overridePathForTests = inMemoryDatabasePath;
      await LocalDb.instance.close();
    });

    tearDown(() async {
      await LocalDb.instance.close();
    });

    test('ida e volta preserva todos os campos', () async {
      final original = top(
        't1',
        nome: 'Pico',
        numero: '1782',
        inicio: DateTime.utc(2026, 10, 10, 8),
        status: TopStatus.finished,
        autocadastro: false,
      );
      await cache.salvarTops('a', [original]);

      final lidos = await cache.tops('a');
      expect(lidos, hasLength(1));
      final t = lidos.single;
      expect(t.id, 't1');
      expect(t.name, 'Pico');
      expect(t.topNumber, '1782');
      expect(t.location, 'Fazenda 3 Colinas');
      expect(t.cidade, 'Itabirito');
      expect(t.diretorResponsavel, isNull);
      expect(t.emblemaPath, 'tops/t1/emblema');
      expect(t.description, 'descrição');
      expect(t.status, TopStatus.finished);
      expect(t.startsAt, DateTime.utc(2026, 10, 10, 8));
      expect(t.endsAt, DateTime.utc(2026, 10, 13, 8));
      // `false` precisa voltar `false`: o SQLite guarda inteiro, e o
      // `?? true` de `Top.fromMap` transformaria um 0 mal lido em aberto.
      expect(t.autocadastroLiberado, isFalse);
    });

    test('mantém a ordem em que o servidor mandou', () async {
      // Postgres põe NULL primeiro em `order by starts_at desc`; ordenar
      // de novo aqui divergiria da tela com rede. A ordem é a da lista.
      await cache.salvarTops('a', [
        top('sem-data'),
        top('novo', inicio: DateTime.utc(2026, 11)),
        top('velho', inicio: DateTime.utc(2025, 1)),
      ]);
      final ids = (await cache.tops('a')).map((t) => t.id).toList();
      expect(ids, ['sem-data', 'novo', 'velho']);
    });

    test('outra conta no mesmo aparelho NÃO vê os Tops da anterior', () async {
      await cache.salvarTops('a', [top('do-a')]);
      await cache.salvarTops('b', [top('do-b')]);

      expect((await cache.tops('a')).map((t) => t.id), ['do-a']);
      expect((await cache.tops('b')).map((t) => t.id), ['do-b']);
      expect(await cache.tops('c'), isEmpty);
    });

    test('o mesmo Top em duas contas não colide', () async {
      await cache.salvarTops('a', [top('t1', nome: 'visto por a')]);
      await cache.salvarTops('b', [top('t1', nome: 'visto por b')]);
      expect((await cache.tops('a')).single.name, 'visto por a');
      expect((await cache.tops('b')).single.name, 'visto por b');
    });

    test('salvar de novo SUBSTITUI a lista daquela conta', () async {
      await cache.salvarTops('a', [top('t1'), top('t2')]);
      await cache.salvarTops('b', [top('t9')]);
      // O t2 saiu da lista do servidor (desvinculado, apagado): tem de
      // sair do disco também, senão o aparelho mostra Top que não é mais
      // dele.
      await cache.salvarTops('a', [top('t1')]);

      expect((await cache.tops('a')).map((t) => t.id), ['t1']);
      expect((await cache.tops('b')).map((t) => t.id), ['t9']);
    });

    test('lista vazia do servidor esvazia o disco daquela conta', () async {
      await cache.salvarTops('a', [top('t1')]);
      await cache.salvarTops('a', const []);
      expect(await cache.tops('a'), isEmpty);
    });

    test('uid vazio não grava nem lê nada', () async {
      await cache.salvarTops('', [top('t1')]);
      expect(await cache.tops(''), isEmpty);
    });
  });

  group('migração v5 → v6 num banco de arquivo', () {
    late Directory dir;
    late String caminho;

    setUp(() async {
      await LocalDb.instance.close();
      dir = await Directory.systemTemp.createTemp('tops_v5_');
      caminho = p.join(dir.path, 'hakuna_offline.db');
      LocalDb.overridePathForTests = caminho;
    });

    tearDown(() async {
      await LocalDb.instance.close();
      LocalDb.overridePathForTests = inMemoryDatabasePath;
      await dir.delete(recursive: true);
    });

    test(
      'aparelho com banco v5 ganha a tabela e não perde o que tinha',
      () async {
        // A v5 é a que está instalada hoje (v1.0.45). Só a tabela que esta
        // migração toca de perto é recriada aqui: `estado_local`, onde fica
        // a aprovação conhecida — perdê-la tiraria a entrada sem servidor.
        final v5 = await databaseFactory.openDatabase(
          caminho,
          options: OpenDatabaseOptions(
            version: 5,
            onCreate: (db, _) async {
              await db.execute(ColunasEstado.criar);
            },
          ),
        );
        await v5.insert(Tabelas.estado, {
          ColunasEstado.chave: ColunasEstado.aprovacaoConhecida,
          ColunasEstado.valor: 'a|1',
          ColunasEstado.gravadoEm: 1,
        });
        await v5.close();

        await cache.salvarTops('a', [top('t1')]);
        expect((await cache.tops('a')).single.id, 't1');
        expect(await cache.lerEstado(ColunasEstado.aprovacaoConhecida), 'a|1');
        final db = await LocalDb.instance.database;
        expect(await db.getVersion(), greaterThanOrEqualTo(6));
      },
    );
  });
}
