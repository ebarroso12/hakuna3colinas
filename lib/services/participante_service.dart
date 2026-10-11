import 'dart:async';

import '../models/participant.dart';
import '../offline/dados_do_top.dart';
import '../offline/outbox.dart';
import '../offline/sync_service.dart';
import 'supabase_service.dart';

/// Cadastro e edição de ficha de participante, **funcionando sem rede**.
///
/// O defeito que isto corrige: o formulário gravava direto no Supabase, e
/// ele é aberto de **duas telas de campo** — do botão "Novo" na lista de
/// participantes e do "Editar" dentro da ficha. Sem sinal, salvar falhava
/// com uma mensagem técnica e o cadastro era perdido. O Hakuna digitava
/// ficha inteira de alguém no mato, com comorbidade e alergia, e perdia
/// tudo ao tocar em salvar.
///
/// Era a mesma falha do alarme e dos sinais vitais: escrita de dado
/// clínico fora da fila.
///
/// DUAS COISAS ACONTECEM AO SALVAR, nesta ordem:
///
/// 1. O participante vai para o **cache local**, então aparece na lista na
///    hora — com ou sem rede. Sem isto o Hakuna salvaria e não acharia a
///    pessoa que acabou de cadastrar.
/// 2. A escrita entra na **fila** e sobe quando o sinal voltar.
///
/// O `id` é gerado NO APARELHO. `top_participants.id` é uuid com default
/// no Postgres, mas aceitar o id de fora resolve dois problemas de uma
/// vez: o cadastro offline já tem identidade definitiva (dá para abrir a
/// ficha, registrar atendimento e emitir pulseira antes de ter rede), e o
/// próprio id serve de chave de idempotência no envio — reenviar o mesmo
/// cadastro não cria um segundo.
class ParticipanteService {
  ParticipanteService._();

  static final ParticipanteService instance = ParticipanteService._();

  static const entidade = 'top_participants';

  void registrarUploader() {
    SyncService.instance.registerUploader(entidade, (entrada) async {
      await SupabaseService.instance.enviarParticipante(entrada.payload);
    });
  }

  /// Grava um cadastro novo. Devolve o participante como ficou no
  /// aparelho, já com id.
  Future<Participant> criar({
    required String topId,
    required Map<String, dynamic> dados,
  }) {
    return _salvar(
      topId: topId,
      // Id novo, gerado aqui. Ver a explicação na doc da classe.
      id: Outbox.novoClientId(),
      dados: dados,
    );
  }

  /// Grava uma edição. O id é o que já existe.
  Future<Participant> atualizar({
    required String id,
    required String topId,
    required Map<String, dynamic> dados,
  }) {
    return _salvar(id: id, topId: topId, dados: dados);
  }

  Future<Participant> _salvar({
    required String id,
    required String topId,
    required Map<String, dynamic> dados,
  }) async {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) {
      throw StateError('Sessão expirada — entre de novo para salvar');
    }

    final payload = {
      ...dados,
      'id': id,
      'top_id': topId,
      // `registered_by` é NOT NULL e é o que permite saber depois quem
      // colocou cada pessoa no Top. Numa edição o servidor ignora (ver
      // `enviarParticipante`), para não reescrever a autoria original.
      'registered_by': uid,
    };

    final participante = Participant.fromMap(payload);

    // Cache PRIMEIRO. Se o enfileiramento falhar depois, o pior caso é um
    // cadastro visível no aparelho que não subiu — e isso a tela da fila
    // mostra. A ordem inversa daria o pior caso ruim: subir e a pessoa não
    // aparecer na lista de quem cadastrou.
    await DadosDoTop.instance.salvarUmParticipante(participante);

    await Outbox.instance.enqueue(
      entity: entidade,
      topId: topId,
      clientId: id,
      payload: payload,
    );
    unawaited(SyncService.instance.syncNow());

    return participante;
  }

  /// Cadastros/edições deste Top que ainda não subiram.
  ///
  /// A lista usa isto para marcar quem está esperando sinal — o Hakuna
  /// precisa saber que a ficha que ele digitou ainda não chegou para os
  /// outros.
  Future<Set<String>> idsNaFila(String topId) async {
    final fila = await Outbox.instance.pending(entity: entidade, limit: 1000);
    return fila
        .where((e) => e.payload['top_id'] == topId)
        .map((e) => e.payload['id'] as String?)
        .whereType<String>()
        .toSet();
  }
}
