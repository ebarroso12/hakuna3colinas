import 'package:flutter_test/flutter_test.dart';
import 'package:legendario_connect/services/atualizacao_service.dart';
import 'package:legendario_connect/versao.dart';

/// O erro que estes testes travam é o de comparar versão como texto.
///
/// `"1.0.9" > "1.0.10"` é verdadeiro em ordem lexicográfica — o app diria
/// que está em dia estando uma versão atrás, e ninguém atualizaria. Por
/// isso a comparação é pelo `build_number` (o `versionCode` do Android),
/// que é inteiro e só cresce.
void main() {
  VersaoPublicada publicada(int build, {String? nome}) => VersaoPublicada(
    nome: nome ?? 'x',
    build: build,
    apkUrl: 'https://exemplo/app.apk',
  );

  group('maisNovaQueEsta', () {
    test('build maior é versão nova', () {
      expect(publicada(Versao.build + 1).maisNovaQueEsta, isTrue);
    });

    test('o mesmo build NÃO é versão nova', () {
      // Sem isto o app avisaria de atualização para quem já está na
      // última, e o aviso perderia o sentido em duas horas de uso.
      expect(publicada(Versao.build).maisNovaQueEsta, isFalse);
    });

    test('build menor não é versão nova', () {
      // Acontece de verdade: linha antiga continua na tabela, e
      // despublicar a nova faz a consulta cair na anterior.
      expect(publicada(Versao.build - 1).maisNovaQueEsta, isFalse);
    });

    test('a comparação ignora o texto da versão', () {
      // O par que quebra ordenação de string: instalada "1.0.10",
      // publicada "1.0.9". Pelo texto a publicada pareceria mais nova;
      // pelo build, que é o que vale, não é.
      final v = VersaoPublicada(
        nome: '1.0.9',
        build: Versao.build - 1,
        apkUrl: 'https://exemplo/app.apk',
      );
      expect(v.nome.compareTo(Versao.nome) > 0, isTrue,
          reason: 'confirma que o texto engana nesta comparacao');
      expect(v.maisNovaQueEsta, isFalse);
    });
  });

  group('fromMap', () {
    test('lê o formato que o Postgres devolve', () {
      // O build e `Versao.build + 1`, nao um numero fixo: fixar 32 fez
      // este teste quebrar no bump seguinte, afirmando que a versao
      // publicada nao era mais nova quando o que mudou foi o app.
      final novo = Versao.build + 1;
      final v = VersaoPublicada.fromMap({
        'version': 'proxima',
        'build_number': novo,
        'apk_url': 'https://drive.google.com/file/d/abc/view',
        'notes': 'corrige o upsert',
        'published': true,
      });
      expect(v.nome, 'proxima');
      expect(v.build, novo);
      expect(v.apkUrl, 'https://drive.google.com/file/d/abc/view');
      expect(v.notas, 'corrige o upsert');
      expect(v.maisNovaQueEsta, isTrue);
    });

    test('aceita build_number vindo como num', () {
      // O Postgrest entrega integer como int, mas numeric chega como
      // double. A coluna é integer hoje; o cast por `num` evita que uma
      // mudança de tipo no banco quebre o parse em campo.
      final v = VersaoPublicada.fromMap({
        'version': 'proxima',
        'build_number': 32.0,
        'apk_url': 'https://exemplo/app.apk',
      });
      expect(v.build, 32);
      expect(v.build, isA<int>());
    });

    test('notas ausentes viram null, não erro', () {
      final v = VersaoPublicada.fromMap({
        'version': 'proxima',
        'build_number': 32,
        'apk_url': 'https://exemplo/app.apk',
      });
      expect(v.notas, isNull);
    });
  });

  test('Versao.completa é o que a gaveta exibe', () {
    expect(Versao.completa, contains(Versao.nome));
    expect(Versao.completa, contains('${Versao.build}'));
  });
}
