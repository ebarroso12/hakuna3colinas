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
      await SupabaseService.instance.enviarAtendimento(entrada.payload);
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
      await Outbox.instance.enqueue(
        entity: entityFoto,
        payload: {
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
}
