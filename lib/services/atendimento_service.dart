import 'dart:io';

import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/afericao.dart';
import '../models/atendimento.dart';
import '../offline/dados_do_top.dart';
import '../offline/outbox.dart';
import '../offline/sync_service.dart';
import 'supabase_service.dart';

/// Registro de atendimento, feito para funcionar no mato.
///
/// Nada aqui escreve direto no Supabase: o atendimento entra na fila local
/// e sobe quando o sinal volta. É o que permite o Hakuna atender, fotografar
/// e seguir caminhando sem depender de cobertura.
class AtendimentoService {
  AtendimentoService._();

  static final AtendimentoService instance = AtendimentoService._();

  static const entityAtendimento = 'atendimentos';
  static const entityFoto = 'atendimento_fotos';

  /// Pasta no próprio celular onde as fotos ficam até subirem.
  static const pastaFotos = 'fotos_atendimento';

  /// Liga os envios à fila. Chamar uma vez, na subida do app.
  void registrarUploaders() {
    SyncService.instance.registerUploader(entityAtendimento, (entrada) async {
      // A operação importa. `enviarAtendimento` faz
      // `upsert(ignoreDuplicates: true)`, que é o certo para o registro
      // novo e **errado** para o encerramento: a linha já existe, o
      // `ignoreDuplicates` não faz nada e o atendimento ficaria aberto
      // para sempre sem ninguém notar.
      if (entrada.operation == OutboxOperation.update) {
        await SupabaseService.instance.atualizarAtendimento(entrada.payload);
      } else {
        await SupabaseService.instance.enviarAtendimento(entrada.payload);
      }
    });
    SyncService.instance.registerUploader(entityFoto, (entrada) async {
      await SupabaseService.instance.enviarFotoAtendimento(entrada.payload);
    });
  }

  /// Diretório das fotos, criado na primeira vez.
  Future<Directory> diretorioDeFotos() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, pastaFotos));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// Move a foto recém-tirada para a pasta do app.
  ///
  /// A câmera entrega o arquivo num diretório temporário que o sistema pode
  /// limpar a qualquer momento. Copiar para a pasta do app é o que garante
  /// que a foto continue lá horas depois, quando finalmente houver sinal.
  Future<String> guardarFoto(
    String caminhoOrigem, {
    required String clientId,
  }) async {
    final dir = await diretorioDeFotos();
    final extensao = p.extension(caminhoOrigem).isEmpty
        ? '.jpg'
        : p.extension(caminhoOrigem);
    final destino = p.join(dir.path, '$clientId$extensao');
    await File(caminhoOrigem).copy(destino);
    return destino;
  }

  /// O `client_id` da foto, lido do nome do arquivo.
  ///
  /// [guardarFoto] nomeia o arquivo com o `client_id` da foto, e esta
  /// função desfaz isso. O acoplamento é de propósito e as duas estão
  /// lado a lado para ficar à vista: é ele que permite `fotosLocais`
  /// continuar sendo uma lista de caminhos, sem um par caminho+id
  /// atravessando o modelo, o formulário e a fila.
  ///
  /// `atendimento_fotos.client_id` é `uuid` no Postgres, então o nome do
  /// arquivo tem de ser um uuid — ver o teste de ida e volta em
  /// `test/services/foto_do_atendimento_test.dart`.
  ///
  /// Corta nos DOIS separadores à mão em vez de usar
  /// `p.basenameWithoutExtension`. O `package:path` escolhe o estilo pelo
  /// sistema onde o Dart está rodando: no Linux ele não reconhece `\` como
  /// separador e devolveria o caminho inteiro como se fosse o nome do
  /// arquivo. O app roda em Android (POSIX), então na prática funcionaria —
  /// mas a correção de um `client_id` não deve depender de em qual sistema
  /// o código está sendo executado. Foi o CI (Linux) que mostrou isso; na
  /// máquina de desenvolvimento (Windows) o teste passava.
  static String clientIdDaFoto(String caminhoLocal) {
    final nome = caminhoLocal.split(RegExp(r'[/\\]')).last;
    final ponto = nome.lastIndexOf('.');
    return ponto <= 0 ? nome : nome.substring(0, ponto);
  }

  /// Registra o atendimento. Devolve o `clientId`, que já identifica o
  /// registro na tela antes de ele existir no servidor.
  ///
  /// [fotosLocais] são caminhos já dentro da pasta do app (ver
  /// [guardarFoto]) — cada um entra na fila como um envio próprio, porque
  /// o arquivo costuma subir bem depois do texto.
  Future<String> registrar(Atendimento atendimento) async {
    final clientId = await Outbox.instance.enqueue(
      entity: entityAtendimento,
      payload: atendimento.toMap(),
      topId: atendimento.topId,
      clientId: atendimento.clientId,
    );

    // Alimenta a triagem dinâmica no mesmo instante em que o atendimento
    // entra na fila — não quando ele chega ao servidor. Um SpO₂ 88% aferido
    // no mato tem de mudar a cor na lista na hora; esperar sinal para isso
    // é o bug que esta linha corrige.
    //
    // Fora do caminho crítico: se o cache falhar, o atendimento já está na
    // fila e o dado clínico está salvo. Só a cor fica velha.
    try {
      await DadosDoTop.instance.registrarAfericao(
        atendimento.participantId,
        atendimento.topId,
        Afericao(
          medidoEm: atendimento.openedAt,
          systolicBp: atendimento.systolicBp,
          diastolicBp: atendimento.diastolicBp,
          spo2: atendimento.spo2,
        ),
      );
    } catch (_) {}

    for (final caminho in atendimento.fotosLocais) {
      // `client_id` PRÓPRIO de cada foto, e não o do atendimento.
      //
      // O bug que isto corrige: todas as fotos iam com o `client_id` do
      // atendimento, e `atendimento_fotos.client_id` tem índice único. Da
      // segunda foto em diante o arquivo subia para o Storage e a LINHA
      // era descartada em silêncio pelo `ignoreDuplicates` — foto clínica
      // órfã, bytes no servidor que nada referencia.
      final fotoClientId = clientIdDaFoto(caminho);
      await Outbox.instance.enqueue(
        entity: entityFoto,
        clientId: fotoClientId,
        payload: {
          'client_id': fotoClientId,
          'atendimento_client_id': clientId,
          'top_id': atendimento.topId,
          'local_path': caminho,
          'taken_by': atendimento.openedBy,
          'taken_at': atendimento.openedAt.toUtc().toIso8601String(),
        },
        topId: atendimento.topId,
      );
    }

    // Tenta subir na hora. Se não houver rede, fica na fila sem erro —
    // é exatamente o comportamento esperado em campo.
    unawaited(SyncService.instance.syncNow());
    return clientId;
  }

  /// Próximo número de registro do Top.
  ///
  /// Calculado no aparelho a partir do que ele conhece. Dois Hakunas
  /// offline podem chegar ao mesmo número — e tudo bem: o registro é
  /// append-only e identificado pelo `clientId`, não pelo número. O número
  /// é para leitura humana no histórico, não é chave.
  Future<int> proximoNumero({
    required String topId,
    int jaExistentes = 0,
  }) async {
    final pendentes = await Outbox.instance.pending(
      entity: entityAtendimento,
      limit: 1000,
    );
    final doTop = pendentes.where((e) => e.topId == topId).length;
    return jaExistentes + doTop + 1;
  }

  /// Quantos atendimentos ainda não subiram. A tela mostra isso para o
  /// Hakuna saber que tem coisa esperando sinal.
  Future<int> pendentesDeEnvio() =>
      Outbox.instance.pendingCount(entity: entityAtendimento);

  /// Encerra um atendimento.
  ///
  /// Até aqui nada fechava atendimento nenhum: o app gravava e deixava
  /// `aberto` para sempre, porque `status` vinha só do default da coluna e
  /// `closed_at` nunca era escrito. Numa lista de 30 atendimentos num Top,
  /// todos abertos, não se distingue quem ainda precisa de atenção.
  ///
  /// Vai pela fila como UPDATE, e a chave é o `client_id`: offline o
  /// atendimento pode nem ter subido ainda, e aí não existe `id` do
  /// servidor para apontar.
  Future<void> encerrar({
    required String clientIdDoAtendimento,
    required String topId,
  }) async {
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) {
      throw StateError('Sessão expirada — não é possível encerrar');
    }
    await Outbox.instance.enqueue(
      entity: entityAtendimento,
      operation: OutboxOperation.update,
      topId: topId,
      payload: {
        'client_id': clientIdDoAtendimento,
        'status': 'encerrado',
        // Hora do aparelho: o atendimento acaba na trilha, não no upload.
        'closed_at': DateTime.now().toUtc().toIso8601String(),
        'closed_by': uid,
      },
    );
    unawaited(SyncService.instance.syncNow());
  }

  /// Caminhos locais das fotos de um atendimento que ainda estão na fila.
  ///
  /// São os arquivos no próprio celular. Serve para a ficha mostrar a foto
  /// **sem rede** — tanto do atendimento que ainda não subiu quanto
  /// daquele cujo texto já subiu mas a foto não.
  Future<List<String>> fotosNaFilaDe(String atendimentoClientId) async {
    final fila = await Outbox.instance.pending(entity: entityFoto, limit: 500);
    return fila
        .where((e) => e.payload['atendimento_client_id'] == atendimentoClientId)
        .map((e) => e.payload['local_path'] as String?)
        .whereType<String>()
        .toList();
  }

  /// Atendimentos deste participante que ainda estão na fila.
  ///
  /// O prontuário lia só do servidor. Offline — o estado normal na trilha
  /// — a busca falhava, caía no `catch` e o Hakuna não via **nem** o
  /// histórico **nem** o atendimento que ele mesmo tinha registrado cinco
  /// minutos antes. Com isto, o que está no aparelho aparece sempre, com
  /// ou sem rede.
  Future<List<Atendimento>> pendentesDoParticipante({
    required String topId,
    required String participantId,
  }) async {
    final fila = await Outbox.instance.pending(
      entity: entityAtendimento,
      limit: 1000,
    );
    final meus = fila.where(
      (e) =>
          e.payload['top_id'] == topId &&
          e.payload['participant_id'] == participantId,
    );
    return meus.map((e) => Atendimento.fromMap(e.payload)).toList()
      // Mais recente primeiro, a mesma ordem do histórico do servidor.
      ..sort((a, b) => b.openedAt.compareTo(a.openedAt));
  }
}
