import 'dart:async';

import '../models/anotacao.dart';
import '../models/team.dart';
import '../offline/outbox.dart';
import '../offline/sync_service.dart';
import 'supabase_service.dart';

/// Anotações de equipe — o bloco de texto das 8 equipes não-médicas.
///
/// Funciona **sem rede**, como todo o resto que se escreve em campo: a
/// anotação entra na fila e sobe quando o sinal voltar. Numa trilha isso
/// não é detalhe — é onde a anotação é escrita.
///
/// **Append-only, e isso é decisão.** Não existe editar nem apagar. Dois
/// motivos:
///
/// 1. Um bloco único editável, offline, perde texto: duas pessoas da
///    mesma equipe editam sem sinal e a última a sincronizar sobrescreve a
///    outra, sem aviso. Com registros separados nada se perde.
/// 2. Fica rastreável quem anotou o quê e quando — e numa ocorrência de
///    segurança isso é metade do valor da anotação.
///
/// Para corrigir, escreve-se outra. É o mesmo desenho de `atendimentos`.
class AnotacaoService {
  AnotacaoService._();

  static final AnotacaoService instance = AnotacaoService._();

  static const entidade = 'anotacoes';

  void registrarUploader() {
    SyncService.instance.registerUploader(entidade, (entrada) async {
      await SupabaseService.instance.enviarAnotacao(entrada.payload);
    });
  }

  /// Grava uma anotação. Devolve o que ficou no aparelho.
  ///
  /// [participanteId] é opcional: com ele a anotação é sobre a pessoa, sem
  /// ele é sobre o turno.
  Future<Anotacao> registrar({
    required String topId,
    required TeamKey team,
    required String texto,
    String? participanteId,
  }) async {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) {
      throw StateError('Sessão expirada — entre de novo para anotar');
    }
    final limpo = texto.trim();
    if (limpo.isEmpty) {
      // O banco também recusa (`check length(trim(texto)) > 0`), mas
      // falhar aqui evita uma entrada na fila que seria quarentenada.
      throw ArgumentError('anotação vazia');
    }

    final clientId = Outbox.novoClientId();
    final anotacao = Anotacao(
      id: clientId,
      topId: topId,
      team: team,
      autorId: uid,
      texto: limpo,
      // Hora do aparelho: offline a anotação é escrita horas antes do
      // upload, e `now()` no Postgres marcaria a hora em que o sinal
      // voltou.
      criadaEm: DateTime.now().toUtc(),
      participanteId: participanteId,
    );

    await Outbox.instance.enqueue(
      entity: entidade,
      topId: topId,
      clientId: clientId,
      payload: {...anotacao.toMap(), 'client_id': clientId},
    );
    unawaited(SyncService.instance.syncNow());

    return anotacao;
  }

  /// Anotações da equipe neste Top, as que já subiram.
  Future<List<Anotacao>> doTop({
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

  /// As que ainda estão no aparelho, esperando sinal.
  ///
  /// A tela mostra estas junto com as do servidor, marcadas — sem isso o
  /// autor escreveria a anotação e não a veria na lista, concluindo que
  /// não salvou.
  Future<List<Anotacao>> naFila({
    required String topId,
    required TeamKey team,
    String? participanteId,
  }) async {
    final fila = await Outbox.instance.pending(entity: entidade, limit: 500);
    return fila
        .map((e) => e.payload)
        .where((p) {
          if (p['top_id'] != topId) return false;
          if (p['team'] != team.name) return false;
          if (participanteId != null && p['participante_id'] != participanteId) {
            return false;
          }
          return true;
        })
        .map(Anotacao.fromMap)
        .toList()
      // Mais recente primeiro, a mesma ordem da lista do servidor.
      ..sort((a, b) => b.criadaEm.compareTo(a.criadaEm));
  }
}
