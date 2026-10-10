import '../models/participant.dart';
import '../models/participant_tag.dart';
import '../offline/dados_do_top.dart';
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

  /// Quanto esperar a rede antes de desistir e ir ao disco.
  ///
  /// Sem isto, sinal fraco (que é diferente de sinal nenhum) deixava o
  /// Hakuna olhando um spinner por 30 s com a pulseira na mão. A resposta
  /// local chega em milissegundos; não vale a pena esperar muito mais.
  static const _timeoutRede = Duration(seconds: 4);

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

    // Rede primeiro quando ela responde rápido: o servidor é a autoridade
    // sobre revogação, e uma pulseira revogada há dez minutos ainda consta
    // como válida no cache do aparelho.
    LeituraTag? daRede;
    try {
      daRede = await _buscarNoServidor(token, topId).timeout(_timeoutRede);
    } catch (_) {
      daRede = null;
    }

    final leitura = daRede ?? await _buscarNoDisco(token);

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
    } catch (_) {
      // TODO: enfileirar no outbox — hoje leitura offline não é auditada.
    }
    return leitura;
  }

  /// Resolve o token no SQLite do aparelho.
  ///
  /// É este caminho que faz a leitura NFC funcionar **em cold start no
  /// mato**: o app foi morto pelo sistema, reabriu sem rede, e a resposta
  /// vem do disco. Antes o fallback era um `Map` em memória, que morria
  /// junto com o processo — ou seja, não existia fallback nenhum.
  Future<LeituraTag> _buscarNoDisco(String token) async {
    final tag = await DadosDoTop.instance.tagPorToken(token);
    if (tag == null) {
      // Desconhecida no disco não é o mesmo que inexistente: pode ser tag
      // emitida depois do último download. `semDados` diz a verdade — o
      // aparelho não sabe — e manda conferir pelo nome.
      return const LeituraTag(ResultadoLeitura.semDados);
    }
    if (!tag.valida) return LeituraTag(ResultadoLeitura.revogada, tag: tag);

    final participante = await DadosDoTop.instance.participante(
      tag.participantId,
    );
    if (participante == null) {
      return LeituraTag(ResultadoLeitura.semDados, tag: tag);
    }
    return LeituraTag(
      ResultadoLeitura.ok,
      participante: participante,
      tag: tag,
    );
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

  /// Emite uma tag nova para um participante.
  ///
  /// Gera o token, revoga a tag anterior (se houver) e devolve a URL que
  /// deve ser GRAVADA na pulseira. O indice unico no banco garante uma tag
  /// ativa por pessoa: sem revogar a antiga, o insert falha.
  Future<ParticipantTag> emitir({
    required String participantId,
    required String topId,
    String? tagUid,
  }) async {
    await revogarAtivaDe(
      participantId,
      motivo: 'substituida por tag nova',
      silencioso: true,
    );
    final token = TagNdef.novoToken();
    return SupabaseService.instance.criarTag(
      token: token,
      participantId: participantId,
      topId: topId,
      tagUid: tagUid,
    );
  }

  /// Revoga a tag ativa de um participante — pulseira perdida, trocada ou
  /// participante que saiu do Top.
  ///
  /// A tag nao e apagada: vira `revogada` e para de valer na hora. Apagar
  /// perderia o rastro de que aquela pulseira existiu e de quem a portava.
  Future<void> revogarAtivaDe(
    String participantId, {
    required String motivo,
    bool silencioso = false,
  }) async {
    try {
      await SupabaseService.instance.revogarTagDoParticipante(
        participantId: participantId,
        motivo: motivo,
      );
    } catch (e) {
      if (!silencioso) rethrow;
    }
  }

  Future<void> revogar(String tagId, {required String motivo}) =>
      SupabaseService.instance.revogarTag(tagId: tagId, motivo: motivo);

  /// Baixa tags e participantes do Top para o disco.
  ///
  /// Substitui o antigo `preencherCache`, que populava um `Map` em memória
  /// — inútil depois de o app ser morto.
  Future<void> prepararParaOMato(String topId) =>
      DadosDoTop.instance.baixar(topId);
}
