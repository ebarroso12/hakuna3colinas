import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legendario_connect/versao.dart';

/// Trava o esquecimento que torna o aviso de atualização mentiroso.
///
/// `Versao` existe porque o aparelho precisa saber a própria versão sem
/// rede, e a única forma de sabê-la offline é tê-la compilada dentro do
/// APK. O preço é a duplicação com o `pubspec.yaml` — e duplicação sem
/// guarda vira divergência: bumpa-se o pubspec, esquece-se o Dart, e o
/// app passa a se anunciar como uma versão que não é a dele. Aí o aviso
/// de "Atualizar" aparece para quem já está atualizado, ou pior, não
/// aparece para quem está atrasado.
///
/// Este teste roda no CI antes de gerar o APK, então a divergência nunca
/// chega a sair em release.
void main() {
  test('Versao.nome e Versao.build batem com o pubspec.yaml', () {
    final pubspec = File('pubspec.yaml');
    expect(
      pubspec.existsSync(),
      isTrue,
      reason: 'o teste roda da raiz do projeto; sem isto ele nao verifica nada',
    );

    final linha = pubspec
        .readAsLinesSync()
        .firstWhere(
          (l) => l.startsWith('version:'),
          orElse: () => '',
        );
    expect(linha, isNotEmpty, reason: 'pubspec sem linha version:');

    // "version: 1.0.29+30" -> nome "1.0.29", build 30.
    final valor = linha.substring('version:'.length).trim();
    final partes = valor.split('+');
    expect(
      partes.length,
      2,
      reason: 'o pubspec precisa do +build: e dele que sai o versionCode',
    );

    expect(Versao.nome, partes[0]);
    expect(Versao.build, int.parse(partes[1]));
  });

  test('completa mostra nome e build juntos', () {
    // A gaveta mostra os dois porque o nome sozinho não distingue dois
    // APKs gerados da mesma versão — e isso acontece quando um build do
    // CI falha e é refeito.
    expect(Versao.completa, '${Versao.nome} (${Versao.build})');
  });
}
