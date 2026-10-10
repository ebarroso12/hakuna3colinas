import 'package:flutter_test/flutter_test.dart';
import 'package:hakuna_connect/offline/cache_local.dart';
import 'package:hakuna_connect/offline/local_db.dart';
import 'package:hakuna_connect/offline/tabelas.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Estado que tem de sobreviver ao processo ser morto.
///
/// É o substituto possível do `START_STICKY`: como o Foreground Service é
/// do plugin `geolocator_android`, quem retoma o rastreamento é o app ao
/// abrir — e para isso ele precisa ter gravado a intenção em disco.
///
/// **O que estes testes NÃO provam:** que o rastreamento religa de fato num
/// Android real. Isso depende do `geolocator` e só se verifica em aparelho
/// físico. Aqui se prova a parte determinística: a intenção é gravada, lida
/// de volta e apagada nos momentos certos.
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

  test('chave ausente devolve null', () async {
    expect(await cache.lerEstado(ColunasEstado.topRastreando), isNull);
  });

  test('grava e lê de volta', () async {
    await cache.guardarEstado(ColunasEstado.topRastreando, 'top-1782');
    expect(await cache.lerEstado(ColunasEstado.topRastreando), 'top-1782');
  });

  test('gravar de novo substitui em vez de duplicar', () async {
    await cache.guardarEstado(ColunasEstado.topRastreando, 'top-1');
    await cache.guardarEstado(ColunasEstado.topRastreando, 'top-2');
    expect(await cache.lerEstado(ColunasEstado.topRastreando), 'top-2');
  });

  test('null apaga a chave — parar é decisão, não queda', () async {
    await cache.guardarEstado(ColunasEstado.topRastreando, 'top-1');
    await cache.guardarEstado(ColunasEstado.topRastreando, null);
    expect(await cache.lerEstado(ColunasEstado.topRastreando), isNull);
  });

  test('chaves diferentes não se atropelam', () async {
    await cache.guardarEstado(ColunasEstado.topRastreando, 'top-1');
    await cache.guardarEstado('outra_coisa', 'valor');
    expect(await cache.lerEstado(ColunasEstado.topRastreando), 'top-1');
    expect(await cache.lerEstado('outra_coisa'), 'valor');
  });
}
