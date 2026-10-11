import 'dart:async';

import '../models/anotacao.dart';
import '../models/team.dart';
import '../offline/outbox.dart';
import '../offline/sync_service.dart';
import 'supabase_service.dart';

/// Bloco de anotações de equipe — o equivalente não-médico do prontuário.
///
/// **Um bloco por membro, editável, e funciona sem rede.**
///
/// A primeira versão foi append-only, por medo de perda de texto: duas
/// pessoas editando o mesmo bloco offline, a última a sincronizar
/// sobrescreve a outra. O dono do projeto apontou que isso não acontece —
/// cada membro tem login próprio e o bloco é dele. Sem concorrência, sem
/// perda. Mudei.
///
/// O que RESTA de risco, e é honesto registrar: a **mesma pessoa** editando
/// em dois aparelhos offline. Aí vale o último a sincronizar, e o outro
/// texto se perde. Não há como resolver isso sem mesclar texto
/// automaticamente, o que erraria mais do que acerta. É raro (exige dois
/// celulares com a mesma conta) e está dito aqui para ninguém se
/// surpreender.
class AnotacaoService {
  AnotacaoService._();

  static final AnotacaoService instance = AnotacaoService._();

  static const entidade = 'anotacoes';

  void registrarUploader() {
    SyncService.instance.registerUploader(entidade, (entrada) async {
      await SupabaseService.instance.enviarAnotacao(entrada.payload);
    });
  }

  /// Salva o bloco. Cria na primeira vez, edita nas seguintes.
  ///
  /// Devolve como ficou no aparelho. Não lança por falta de rede.
  Future<Anotacao> salvar({
    required String topId,
    required TeamKey team,
    required String texto,
    String? participanteId,
    Anotacao? anterior,
  }) async {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) {
      throw StateError('Sessão expirada — entre de novo para anotar');
    }
    final limpo = texto.trim();
    if (limpo.isEmpty) {
      // O banco também recusa (`check length(trim(texto)) > 0`), mas
      // falhar aqui evita uma entrada na fila que iria para quarentena.
      throw ArgumentError('anotação vazia');
    }

    final agora = DateTime.now().toUtc();
    final blocoId = Anotacao.chaveDe(
      topId: topId,
      team: team,
      autorId: uid,
      participanteId: participanteId,
    );

    final bloco = anterior != null && anterior.blocoId == blocoId
        ? anterior.comTexto(limpo, agora)
        : Anotacao(
            blocoId: blocoId,
            topId: topId,
            team: team,
            autorId: uid,
            texto: limpo,
            criadaEm: agora,
            atualizadoEm: agora,
            participanteId: participanteId,
          );

    // `enqueueSubstituindo` e NAO `enqueue`, e a diferença decide se o
    // texto se perde.
    //
    // `enqueue` usa `ConflictAlgorithm.ignore`: enfileirar duas vezes o
    // mesmo `client_id` descarta o segundo. Isso é certo para atendimento
    // (append-only) e **errado** aqui — editar o bloco duas vezes sem
    // sinal faria a segunda edição ser ignorada em silêncio, e o texto
    // antigo subiria. Perda de texto sem erro na tela, que é o pior tipo.
    //
    // `clientId: blocoId` porque a identidade do envio É o bloco: uma
    // entrada na fila por bloco, sempre com o texto atual.
    await Outbox.instance.enqueueSubstituindo(
      entity: entidade,
      topId: topId,
      clientId: blocoId,
      payload: bloco.toMap(),
    );
    unawaited(SyncService.instance.syncNow());

    return bloco;
  }

  /// O bloco desta pessoa, lido do servidor.
  ///
  /// Null quando ela ainda não escreveu nada — e aí a tela abre vazia.
  Future<Anotacao?> meuBloco({
    required String topId,
    required TeamKey team,
    String? participanteId,
  }) async {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) return null;
    return SupabaseService.instance.buscarBloco(
      blocoId: Anotacao.chaveDe(
        topId: topId,
        team: team,
        autorId: uid,
        participanteId: participanteId,
      ),
    );
  }

  /// O bloco desta pessoa como está **no aparelho**, se ainda não subiu.
  ///
  /// Tem prioridade sobre o do servidor quando existe: é a versão mais
  /// recente, e sem isto quem editou offline veria o texto antigo voltar
  /// ao reabrir a tela.
  Future<Anotacao?> meuBlocoNaFila({
    required String topId,
    required TeamKey team,
    String? participanteId,
  }) async {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) return null;
    final chave = Anotacao.chaveDe(
      topId: topId,
      team: team,
      autorId: uid,
      participanteId: participanteId,
    );
    final fila = await Outbox.instance.pending(entity: entidade, limit: 500);
    for (final e in fila) {
      if (e.payload['bloco_id'] == chave) return Anotacao.fromMap(e.payload);
    }
    return null;
  }

  /// Os blocos da equipe inteira — o que a coordenação lê.
  ///
  /// A RLS decide o que volta: membro de uma equipe não lê o bloco de
  /// outra.
  Future<List<Anotacao>> daEquipe({
    required String topId,
    required TeamKey team,
    String? participanteId,
  }) {
    return SupabaseService.instance.buscarAnotacoes(
      topId: topId,
      team: team.name,
      participanteId: participanteId,
    );
  }
}
