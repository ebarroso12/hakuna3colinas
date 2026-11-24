// A CADEIA DE ATUALIZAÇÃO: versão visível, aviso, e o botão que baixa do
// GitHub.
//
// Pedido do dono em 24/11/2026, nestas palavras: *"sempre colocar a versão
// que está e avisar aos usuários sobre atualização, ter o botão de atualizar
// que irá baixar do github a atualização"*.
//
// São quatro elos, e cada um já falhou ou quase falhou neste projeto:
//
// 1. **A versão instalada** vem de `lib/versao.dart`, compilada dentro do
//    APK — é o único jeito de o aparelho saber a própria versão sem rede.
//    Esquecer de bumpar essas constantes ao bumpar o `pubspec.yaml` é
//    travado por `versao_bate_com_pubspec_test.dart`.
// 2. **A comparação** é por `build_number`, NUNCA pelo texto: como string,
//    `"1.0.9" > "1.0.10"`, e o app diria que está em dia estando atrasado.
// 3. **O link** tem de apontar para a Release do GitHub, que abre sem
//    login. De 1.0.40 a 1.0.44 nenhuma linha foi escrita em `app_versions`
//    e ninguém viu o botão.
// 4. **`null` é "não sei"**, não "está atualizado". Sem rede — o estado
//    normal na trilha — a tela não pode afirmar nenhum dos dois.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:legendario_connect/services/atualizacao_service.dart';
import 'package:legendario_connect/versao.dart';

void main() {
  final raiz = Directory.current.path;
  String fonte(String caminho) => File('$raiz/$caminho').readAsStringSync();

  VersaoPublicada publicada({
    required String nome,
    required int build,
    String url = 'https://github.com/x/y/releases/download/v1/a.apk',
    String? notas,
  }) => VersaoPublicada(nome: nome, build: build, apkUrl: url, notas: notas);

  group('a comparação é por build, nunca pelo texto', () {
    test('build maior que o instalado = desatualizado', () {
      expect(
        publicada(nome: '9.9.9', build: Versao.build + 1).maisNovaQueEsta,
        isTrue,
      );
    });

    test('o mesmo build não avisa', () {
      expect(
        publicada(nome: Versao.nome, build: Versao.build).maisNovaQueEsta,
        isFalse,
      );
    });

    test('build menor não avisa, mesmo com nome "maior"', () {
      expect(
        publicada(nome: '99.0.0', build: Versao.build - 1).maisNovaQueEsta,
        isFalse,
      );
    });

    test('a armadilha do texto: 1.0.9 vs 1.0.10', () {
      // Como string, '1.0.9' > '1.0.10'. Se a comparação fosse textual, um
      // app na 1.0.9 se diria atualizado com a 1.0.10 publicada. O build
      // resolve, e este caso trava a regra.
      expect('1.0.9'.compareTo('1.0.10'), greaterThan(0));
      final maisNova = publicada(nome: '1.0.10', build: Versao.build + 1);
      expect(maisNova.maisNovaQueEsta, isTrue);
    });
  });

  group('o link do APK', () {
    test('fromMap lê as quatro colunas que a consulta pede', () {
      final v = VersaoPublicada.fromMap({
        'version': '1.0.99',
        'build_number': 100,
        'apk_url': 'https://github.com/a/b/releases/download/v1.0.99/x.apk',
        'notes': 'o que mudou',
      });
      expect(v.nome, '1.0.99');
      expect(v.build, 100);
      expect(v.apkUrl, endsWith('.apk'));
      expect(v.notas, 'o que mudou');
    });

    test('build_number aceita num (o Postgrest manda int ou double)', () {
      // `(map['build_number'] as num).toInt()` existe por isso: um cast
      // direto para `int` estoura se o JSON trouxer 100.0.
      final v = VersaoPublicada.fromMap({
        'version': '1.0.99',
        'build_number': 100.0,
        'apk_url': 'https://x/y.apk',
      });
      expect(v.build, 100);
      expect(v.notas, isNull);
    });

    test('a consulta pede colunas EXPLÍCITAS e as quatro existem', () {
      final src = fonte('lib/services/atualizacao_service.dart');
      expect(
        src.contains(".select('version, build_number, apk_url, notes')"),
        isTrue,
        reason: '`select()` pelado foi o caminho pelo qual o hash da senha '
            'do Top vazou de `tops`; a regra vale para toda consulta',
      );
    });
  });

  group('o botão que baixa', () {
    test('o AndroidManifest declara <queries> para http e https', () {
      // Sem isto, a partir do Android 11 `canLaunchUrl` devolve false e o
      // botão ATUALIZAR **não faz nada** — o app não vê que existe
      // navegador instalado. É invisível em emulador antigo.
      final manifest = fonte('android/app/src/main/AndroidManifest.xml');
      expect(manifest.contains('<queries>'), isTrue);
      expect(manifest.contains('android.intent.action.VIEW'), isTrue);
      expect(manifest.contains('android:scheme="https"'), isTrue);
      expect(manifest.contains('android:scheme="http"'), isTrue);
    });

    test('a falha de launchUrl é tratada E mostrada', () {
      // `launchUrl` levanta `PlatformException` quando nada resolve o
      // intent. Sem `catch`, a exceção escapa de um callback async, em
      // release é engolida, e o toque fica sem resposta nenhuma.
      final src = fonte('lib/widgets/gaveta_do_app.dart');
      final i = src.indexOf('launchUrl(');
      expect(i, greaterThan(0), reason: 'launchUrl saiu da gaveta?');
      final volta = src.substring((i - 1200).clamp(0, i), i + 1400);
      expect(
        volta.contains('try {') && volta.contains('} catch'),
        isTrue,
        reason: 'launchUrl sem try/catch: o botão falha calado',
      );
      expect(
        volta.contains('showSnackBar'),
        isTrue,
        reason: 'falhar sem dizer nada é pior que falhar',
      );
      expect(
        volta.contains(r'${v.apkUrl}'),
        isTrue,
        reason: 'a mensagem tem de trazer o endereço, para dar para baixar '
            'à mão quando o launchUrl não servir',
      );
    });
  });

  group('a versão instalada aparece na tela', () {
    test('no login, que é a tela de quem NÃO consegue entrar', () {
      final src = fonte('lib/screens/login_screen.dart');
      expect(
        src.contains('Versao.completa'),
        isTrue,
        reason: 'suporte começa em "qual versão você está usando?", e quem '
            'não entra não alcança a gaveta para descobrir',
      );
    });

    test('na gaveta', () {
      expect(fonte('lib/widgets/gaveta_do_app.dart').contains('Versao.'), isTrue);
    });

    test('Versao.completa junta nome e build', () {
      expect(Versao.completa, '${Versao.nome} (${Versao.build})');
    });
  });

  test('no iPhone não se oferece APK', () {
    // `app_versions` aponta para um .apk; mandar um iPhone baixar APK é
    // mandar a pessoa para um arquivo que o aparelho não abre. No iOS quem
    // atualiza é o TestFlight.
    expect(AtualizacaoService.atualizaPeloTestFlight, isFalse,
        reason: 'nos testes a plataforma não é iOS; o que este caso trava é '
            'a existência do portão, não o valor dele aqui');
    final src = fonte('lib/services/atualizacao_service.dart');
    expect(src.contains('if (atualizaPeloTestFlight) return null;'), isTrue);
  });
}
