/// Versão desta build, gravada aqui porque é o único lugar que o próprio
/// aparelho consegue ler sem rede.
///
/// Não existe `package_info_plus` no projeto de propósito: estes dois
/// valores são compilados DENTRO do APK, então descrevem exatamente a
/// build que está rodando — que é o que interessa para decidir se há
/// versão nova. Um pacote a mais não daria resposta melhor.
///
/// O risco óbvio é esquecer de atualizar aqui ao bumpar o `pubspec.yaml`,
/// e aí o app se anuncia como uma versão que não é. Esse esquecimento é
/// travado por `test/versao_bate_com_pubspec_test.dart`, que lê o
/// `pubspec.yaml` e falha se os valores divergirem.
class Versao {
  Versao._();

  /// `version:` do pubspec, parte antes do `+`. Aparece na gaveta.
  static const nome = '1.0.34';

  /// Parte depois do `+` — o `versionCode` do Android.
  ///
  /// É por ELE que se compara, nunca pelo texto: como string, "1.0.9" é
  /// maior que "1.0.10", e o app diria que está atualizado estando atrás.
  static const build = 35;

  /// O que a tela mostra, no formato `1.0.34 (35)`.
  static const completa = '$nome ($build)';
}
