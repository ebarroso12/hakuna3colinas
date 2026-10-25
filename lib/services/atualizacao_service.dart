import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../versao.dart';

/// Versão publicada do app, lida da tabela `app_versions`.
///
/// O que vem do servidor é só o **aviso**: o download e a instalação são
/// manuais, por "fontes desconhecidas". Atualização automática exigiria
/// Play Store, e o app não está lá — ver `CLAUDE.md`, seção Release.
class VersaoPublicada {
  const VersaoPublicada({
    required this.nome,
    required this.build,
    required this.apkUrl,
    this.notas,
  });

  final String nome;
  final int build;
  final String apkUrl;
  final String? notas;

  /// Compara por `build`, nunca pelo texto da versão: como string,
  /// "1.0.9" > "1.0.10", e o app diria que está atualizado estando atrás.
  bool get maisNovaQueEsta => build > Versao.build;

  factory VersaoPublicada.fromMap(Map<String, dynamic> map) {
    return VersaoPublicada(
      nome: map['version'] as String,
      build: (map['build_number'] as num).toInt(),
      apkUrl: map['apk_url'] as String,
      notas: map['notes'] as String?,
    );
  }
}

class AtualizacaoService {
  AtualizacaoService._();

  static final AtualizacaoService instance = AtualizacaoService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// No iPhone o app vem do TestFlight, que avisa e instala sozinho.
  ///
  /// `app_versions` aponta para um APK, e mandar um iPhone baixar APK é
  /// mandar a pessoa para um arquivo que o aparelho dela não abre. Por
  /// isso no iOS a consulta nem acontece e a gaveta não mostra ATUALIZAR.
  static bool get atualizaPeloTestFlight =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Último resultado conhecido, para a gaveta abrir já com a resposta em
  /// vez de piscar "verificando" a cada vez que o usuário a abre.
  VersaoPublicada? ultimaConhecida;

  /// Devolve a versão publicada mais alta, ou `null` quando não há nenhuma
  /// publicada **ou quando não deu para consultar**.
  ///
  /// Os dois casos devolvem `null` de propósito: sem rede — que é o estado
  /// normal na trilha — não há o que afirmar, e a tela não deve dizer nem
  /// "atualizado" nem "desatualizado". Quem chama trata `null` como
  /// "não sei".
  Future<VersaoPublicada?> consultar() async {
    if (atualizaPeloTestFlight) return null;
    try {
      final rows = await _client
          .from('app_versions')
          .select()
          .eq('published', true)
          .order('build_number', ascending: false)
          .limit(1);
      if (rows.isEmpty) return null;
      final v = VersaoPublicada.fromMap(rows.first);
      ultimaConhecida = v;
      return v;
    } catch (_) {
      // Offline, RLS, tabela ausente num ambiente antigo: nada disso é
      // motivo para quebrar a tela. O aviso de atualizar é conveniência,
      // não função clínica.
      return null;
    }
  }
}
