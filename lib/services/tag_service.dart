import '../models/participant.dart';
import '../models/participant_tag.dart';
import 'supabase_service.dart';

/// O que a leitura de uma tag produziu.
class LeituraTag {
  final ResultadoLeitura resultado;
  final Participant? participante;
  final ParticipantTag? tag;

  const LeituraTag(this.resultado, {this.participante, this.tag});

  bool get identificou =>
      resultado == ResultadoLeitura.ok && participante != null;
}

/// Resolve tokens de tag em participantes.
///
/// Regra do sistema: **ler a tag não autentica**. Este serviço só é útil
/// para quem já está logado, e a RLS de `participant_tags` recusa a
/// consulta de quem não é Hakuna liberado no Top. Quem acha uma pulseira
/// no chão e abre a URL não descobre nada.
class TagService {
  TagService._();

  static final TagService instance = TagService._();

  /// Cache em memória do que já foi resolvido nesta sessão.
  ///
  /// Serve para a segunda leitura da mesma pulseira funcionar mesmo depois
  /// de o sinal cair — o cenário real de uma trilha, onde o Hakuna lê a
  /// mesma pessoa mais de uma vez.
  final Map<String, LeituraTag> _cache = {};

  /// Resolve o conteúdo lido do NDEF.
  ///
  /// [conteudo] é a URL gravada na tag. Toda leitura é registrada em
  /// `tag_leituras`, inclusive as que falham — auditoria serve justamente
  /// para ver tentativa com tag revogada ou desconhecida.
  Future<LeituraTag> resolver(
    String? conteudo, {
    required String topId,
    double? latitude,
    double? longitude,
  }) async {
    final token = TagNdef.tokenDe(conteudo);
    if (token == null) {
      return const LeituraTag(ResultadoLeitura.formatoInvalido);
    }

    try {
      final leitura = await _buscarNoServidor(token, topId);
      _cache[token] = leitura;
      // Auditoria não pode derrubar o atendimento: se falhar, a
      // identificação segue valendo.
      try {
        await SupabaseService.instance.registrarLeituraTag(
          token: token,
          topId: topId,
          participantId: leitura.participante?.id,
          resultado: leitura.resultado.paraAuditoria,
          latitude: latitude,
          longitude: longitude,
        );
      } catch (_) {}
      return leitura;
    } catch (_) {
      // Sem rede: vale o que já foi lido nesta sessão.
      final emCache = _cache[token];
      if (emCache != null) return emCache;
      return const LeituraTag(ResultadoLeitura.semDados);
    }
  }

  Future<LeituraTag> _buscarNoServidor(String token, String topId) async {
    final tag = await SupabaseService.instance.buscarTagPorToken(token);
    if (tag == null) return const LeituraTag(ResultadoLeitura.desconhecida);
    if (!tag.valida) {
      return LeituraTag(ResultadoLeitura.revogada, tag: tag);
    }
    final participante = await SupabaseService.instance.fetchParticipant(
      tag.participantId,
    );
    if (participante == null) {
      // Tag aponta para alguém que não existe mais no Top.
      return LeituraTag(ResultadoLeitura.desconhecida, tag: tag);
    }
    return LeituraTag(
      ResultadoLeitura.ok,
      participante: participante,
      tag: tag,
    );
  }

  /// Guarda uma resolução no cache. Usado ao baixar as tags do Top antes
  /// de entrar no mato.
  void preencherCache(String token, LeituraTag leitura) {
    _cache[token] = leitura;
  }

  void limparCache() => _cache.clear();
}
