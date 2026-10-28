import '../models/afericao.dart';
import '../models/participant.dart';
import '../models/participant_tag.dart';
import '../models/triage_rule.dart';
import '../services/supabase_service.dart';
import 'cache_local.dart';
import 'outbox.dart';

/// Resultado de uma descida de dados.
class ResumoDownload {
  final int participantes;
  final int tags;
  final int regras;
  final DateTime em;

  /// Quantas fichas feitas NESTE aparelho ainda não subiram. Quando é
  /// maior que zero a lista do disco foi MANTIDA, sem a versão do
  /// servidor — ver [DadosDoTop.baixar].
  final int fichasSoNoAparelho;

  const ResumoDownload({
    required this.participantes,
    required this.tags,
    required this.regras,
    required this.em,
    this.fichasSoNoAparelho = 0,
  });

  bool get listaMantida => fichasSoNoAparelho > 0;
}

/// Fonte única de leitura dos dados de um Top.
///
/// **A inversão que este arquivo faz:** antes as telas chamavam
/// `SupabaseService` direto, então em cold start sem sinal a lista vinha
/// vazia e a tag não resolvia. Agora o disco é a fonte de leitura e a rede
/// é só quem alimenta o disco.
///
/// A ordem é sempre: **disco primeiro, rede depois**. Não é otimização —
/// é o único arranjo em que o app funciona no mato, que é onde ele é usado.
class DadosDoTop {
  DadosDoTop._();

  static final DadosDoTop instance = DadosDoTop._();

  final _cache = CacheLocal.instance;

  /// Baixa participantes, tags e regras do Top para o disco.
  ///
  /// Chamado ao entrar no Top **com sinal**, antes de subir a trilha. É o
  /// momento em que o aparelho fica autossuficiente.
  ///
  /// Grava cada bloco assim que ele chega, em vez de esperar os três: com
  /// sinal ruim é comum o primeiro passar e o terceiro falhar, e aí ter
  /// participantes gravados já é melhor que não ter nada.
  ///
  /// **Não substitui a lista se houver ficha que só existe aqui.**
  /// `salvarParticipantes` apaga o Top inteiro do disco e grava o que veio
  /// do servidor. Ficha cadastrada ou editada sem sinal, ainda na fila,
  /// sumiria da lista — ou voltaria à versão antiga — até sincronizar. Em
  /// campo é a ficha que o Hakuna acabou de fazer desaparecendo da tela.
  /// Nesse caso a lista do disco fica e só pulseiras e regras descem.
  Future<ResumoDownload> baixar(String topId) async {
    // Literal e não `ParticipanteService.entidade`: este arquivo é da
    // camada de disco e não importa serviço de tela.
    final soNoAparelho = await Outbox.instance.naoEnviadas(
      entity: 'top_participants',
      topId: topId,
    );

    var nParticipantes = 0;
    if (soNoAparelho == 0) {
      final participantes = await SupabaseService.instance.fetchParticipants(
        topId,
      );
      nParticipantes = await _cache.salvarParticipantes(topId, participantes);
    }

    var nTags = 0;
    try {
      final tags = await SupabaseService.instance.fetchTags(topId);
      nTags = await _cache.salvarTags(topId, tags);
    } catch (_) {
      // Tag é o que mais importa, mas se falhar aqui a lista por nome
      // continua valendo — e é ela o plano B da pulseira.
    }

    var nRegras = 0;
    try {
      final regras = await SupabaseService.instance.fetchActiveTriageRules();
      await _cache.salvarRegras(regras);
      nRegras = regras.length;
    } catch (_) {}

    return ResumoDownload(
      participantes: nParticipantes,
      tags: nTags,
      regras: nRegras,
      em: DateTime.now(),
      fichasSoNoAparelho: soNoAparelho,
    );
  }

  /// Participantes do Top, do disco.
  ///
  /// Se o disco estiver vazio, tenta baixar uma vez — primeiro acesso ao
  /// Top ainda com sinal. Sem sinal e sem cache devolve lista vazia, e é a
  /// tela que diz ao usuário que ele precisa baixar os dados antes de subir.
  Future<List<Participant>> participantes(
    String topId, {
    String? termo,
    String? familia,
  }) async {
    var lista = await _cache.participantes(
      topId,
      termo: termo,
      familia: familia,
    );
    if (lista.isEmpty && await baixadoEm(topId) == null) {
      try {
        await baixar(topId);
        lista = await _cache.participantes(
          topId,
          termo: termo,
          familia: familia,
        );
      } catch (_) {}
    }
    return lista;
  }

  Future<Participant?> participante(String id) => _cache.participante(id);

  /// Grava um participante cadastrado ou editado NO APARELHO.
  ///
  /// Sem apagar o resto do Top: `baixar` e para o download completo, esta
  /// e para o que o Hakuna acabou de digitar. Ver
  /// `ParticipanteService._salvar`.
  Future<void> salvarUmParticipante(Participant p) =>
      _cache.salvarUmParticipante(p);

  /// Quando este Top foi baixado. Null = nunca — a tela precisa avisar.
  Future<DateTime?> baixadoEm(String topId) => _cache.baixadoEm(topId);

  Future<List<TriageRule>> regras() async {
    final doDisco = await _cache.regras();
    if (doDisco.isNotEmpty) return doDisco;
    try {
      final daRede = await SupabaseService.instance.fetchActiveTriageRules();
      await _cache.salvarRegras(daRede);
      return daRede;
    } catch (_) {
      // Sem regras a lista funciona, só não pinta a cor de cadastro. A
      // escalada por sinal vital continua valendo: ela não depende delas.
      return const [];
    }
  }

  Future<Map<String, Afericao>> afericoes(String topId) =>
      _cache.afericoesDoTop(topId);

  Future<Afericao?> afericaoDe(String participantId) =>
      _cache.afericaoDe(participantId);

  Future<void> registrarAfericao(
    String participantId,
    String topId,
    Afericao afericao,
  ) => _cache.registrarAfericao(participantId, topId, afericao);

  /// Resolve um token de tag **no disco**, sem rede.
  Future<ParticipantTag?> tagPorToken(String token) =>
      _cache.tagPorToken(token);

  Future<int> totalTags(String topId) => _cache.totalTags(topId);

  Future<void> limpar(String topId) => _cache.limparTop(topId);
}
