import 'package:supabase_flutter/supabase_flutter.dart';

/// Quanto dado clínico está amarrado a uma pessoa, e se dá para apagá-la.
class Dependencias {
  const Dependencias({
    required this.id,
    required this.podeApagar,
    required this.motivos,
  });

  final String id;
  final bool podeApagar;

  /// O que impede, em texto pronto para a tela: "12 atendimentos
  /// registrados". Vazio quando dá para apagar.
  final List<String> motivos;

  String get porque => motivos.isEmpty ? '' : motivos.join(' · ');
}

/// Exclusão de usuários e senderistas — só para o admin master.
///
/// O cuidado todo deste arquivo tem uma razão só: **apagar pessoa de um
/// evento médico pode levar prontuário com ela.** Dois achados no banco,
/// em 11/10/2026, antes de escrever qualquer tela:
///
/// 1. `atendimentos.opened_by` tinha `ON DELETE CASCADE`. Apagar um Hakuna
///    APAGARIA TODOS OS ATENDIMENTOS QUE ELE REGISTROU — um clique de
///    limpeza de cadastro destruindo o registro clínico de dezenas de
///    pessoas, em silêncio. Hoje é `RESTRICT` (ver
///    `supabase/exclusao_protegida.sql`).
/// 2. `top_participants` não tinha NENHUMA policy de DELETE: ninguém
///    conseguia apagar senderista, nem o admin. Não era proteção pensada,
///    era ausência.
///
/// A regra que ficou: **apaga quem não deixou rastro clínico; quem deixou,
/// desativa.** Cadastro de teste, duplicado e quem não compareceu saem de
/// verdade. Quem atendeu ou foi atendido, não — a história fica.
///
/// POR QUE A EXCLUSÃO **NÃO** VAI PELA FILA OFFLINE, e isso é decisão.
///
/// Todo o resto do app grava no aparelho e sobe depois: atendimento, foto,
/// posição, chat, auditoria, alarme, sinais vitais e ficha. Apagar é a
/// única exceção, por três motivos:
///
/// 1. **É irreversível e chegaria atrasado.** Uma exclusão enfileirada às
///    9h e executada às 16h pode apagar alguém que foi atendido às 11h.
///    Entre 9h e 16h o mundo mudou, e a fila não sabe disso.
/// 2. **A conferência de prontuário é feita no servidor.** Ela depende de
///    contar atendimento, aferição e auditoria — dados que o aparelho não
///    tem inteiros. Enfileirar seria decidir com informação incompleta.
/// 3. **Não é tarefa de campo.** Apagar cadastro se faz sentado, com
///    internet, não com uma mão no celular no meio da trilha.
///
/// Então sem rede isto **falha e diz que falhou**, com a mensagem certa —
/// ver `mensagemDeErro`. Falhar alto aqui é o comportamento seguro; a fila
/// seria o comportamento perigoso.
class ExclusaoService {
  ExclusaoService._();

  static final ExclusaoService instance = ExclusaoService._();

  SupabaseClient get _client => Supabase.instance.client;

  /// Teto por chamada, igual ao da Edge Function.
  ///
  /// Existe por dois motivos: um toque errado não varre a base inteira, e
  /// a requisição não estoura o tempo da função.
  static const maxPorVez = 50;

  /// Traduz a falha para o que o admin precisa ler.
  ///
  /// Sem isto a tela mostrava a exceção crua — `SocketException` ou
  /// `ClientException: Failed host lookup` —, que não diz a única coisa
  /// que importa: **precisa de internet, tente de novo com sinal.**
  static String mensagemDeErro(Object e) {
    final texto = e.toString().toLowerCase();
    final semRede =
        texto.contains('socketexception') ||
        texto.contains('failed host lookup') ||
        texto.contains('connection') ||
        texto.contains('network') ||
        texto.contains('timeout') ||
        texto.contains('clientexception');
    if (semRede) {
      return 'Apagar precisa de internet. Isto não fica guardado para '
          'depois de propósito: uma exclusão atrasada poderia apagar '
          'alguém que foi atendido no meio do caminho.';
    }
    return 'Não foi possível concluir: $e';
  }

  /// Confere, para cada perfil, o que seria perdido.
  ///
  /// Chamado ANTES de mostrar a confirmação: a tela diz "este tem 12
  /// atendimentos" em vez de deixar o banco responder com erro 23503, que
  /// não significa nada para quem está usando o app.
  Future<Map<String, Dependencias>> dependenciasDePerfis(
    List<String> ids,
  ) async {
    if (ids.isEmpty) return const {};
    final linhas = await _client.rpc<List<dynamic>>(
      'dependencias_do_perfil',
      params: {'p_ids': ids},
    );
    return _mapear(linhas, 'profile_id', (m) {
      final motivos = <String>[];
      void add(String chave, String rotulo) {
        final n = (m[chave] as num?)?.toInt() ?? 0;
        if (n > 0) motivos.add('$n $rotulo');
      }

      add('atendimentos_feitos', 'atendimento(s) registrado(s)');
      add('atendimentos_fechados', 'atendimento(s) encerrado(s)');
      add('afericoes_feitas', 'aferição(ões) feita(s)');
      add('afericoes_proprias', 'aferição(ões) própria(s)');
      add('auditoria', 'registro(s) de auditoria');
      add('tags_emitidas', 'pulseira(s)');
      add('alarmes', 'alarme(s)');
      // Sem nenhuma contagem e ainda assim bloqueado: é o admin master.
      if (motivos.isEmpty && m['pode_apagar'] != true) {
        motivos.add('é o administrador master');
      }
      return motivos;
    });
  }

  Future<Map<String, Dependencias>> dependenciasDeSenderistas(
    List<String> ids,
  ) async {
    if (ids.isEmpty) return const {};
    final linhas = await _client.rpc<List<dynamic>>(
      'dependencias_do_senderista',
      params: {'p_ids': ids},
    );
    return _mapear(linhas, 'participante_id', (m) {
      final n = (m['atendimentos'] as num?)?.toInt() ?? 0;
      // Só atendimento trava. `atendimentos.participant_id` é SET NULL:
      // apagar o senderista NÃO apaga o atendimento, deixa ele ÓRFÃO — um
      // prontuário que ninguém sabe de quem é. Pior que apagar.
      //
      // Pulseira e leitura não travam: a pulseira vai em cascata (é
      // daquela pessoa) e a leitura vira SET NULL, mas leitura de pulseira
      // sem participante ainda responde "quando e onde alguém passou",
      // que é para o que ela serve.
      return n > 0 ? ['$n atendimento(s) no prontuário'] : const [];
    });
  }

  Map<String, Dependencias> _mapear(
    List<dynamic> linhas,
    String chaveId,
    List<String> Function(Map<String, dynamic>) motivosDe,
  ) {
    final fora = <String, Dependencias>{};
    for (final linha in linhas) {
      final m = linha as Map<String, dynamic>;
      final id = m[chaveId] as String;
      fora[id] = Dependencias(
        id: id,
        podeApagar: m['pode_apagar'] == true,
        motivos: motivosDe(m),
      );
    }
    return fora;
  }

  /// Apaga usuários (conta + perfil) pela Edge Function.
  ///
  /// Passa pelo servidor e não por um `delete` daqui porque `profiles.id`
  /// referencia `auth.users(id) ON DELETE CASCADE`: apagar a linha de
  /// `profiles` pelo app **não** apaga o usuário do auth, e sobra um
  /// órfão que continua conseguindo fazer login e cai num app sem perfil,
  /// numa tela de erro sem saída. O caminho certo é o inverso — apagar o
  /// `auth.users` e deixar o perfil cair em cascata —, e isso exige a
  /// chave `service_role`, que nunca pode estar dentro do APK.
  ///
  /// Devolve (apagados, recusados com o motivo). Recusa parcial é normal e
  /// não é erro: apagar 8 de 10 e dizer quais 2 ficaram é mais útil que
  /// falhar tudo.
  Future<({List<String> apagados, Map<String, String> recusados})>
  apagarUsuarios(List<String> ids) async {
    final resposta = await _client.functions.invoke(
      'acesso',
      body: {'acao': 'apagar_usuarios', 'ids': ids},
    );
    final dados = resposta.data as Map<String, dynamic>?;
    if (dados == null) throw StateError('resposta vazia do servidor');
    if (dados['error'] != null) {
      throw StateError(dados['error'].toString());
    }
    final apagados = (dados['apagados'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();
    final recusados = <String, String>{};
    for (final r in (dados['recusados'] as List<dynamic>? ?? [])) {
      final m = r as Map<String, dynamic>;
      recusados[m['id'].toString()] = m['motivo'].toString();
    }
    return (apagados: apagados, recusados: recusados);
  }

  /// Apaga senderistas direto pela RLS.
  ///
  /// Aqui não há conta de autenticação envolvida, então não precisa da
  /// Edge Function: a policy `top_participants_delete_master` já restringe
  /// ao admin master, e o `RESTRICT`/`SET NULL` do banco é a rede de
  /// segurança. A conferência de prontuário é feita antes, na tela, com
  /// [dependenciasDeSenderistas].
  ///
  /// Devolve quantos saíram de fato.
  Future<int> apagarSenderistas(List<String> ids) async {
    if (ids.isEmpty) return 0;
    final apagados = await _client
        .from('top_participants')
        .delete()
        .inFilter('id', ids)
        .select('id');
    return apagados.length;
  }

  /// Desativa em vez de apagar — a saída para quem tem prontuário.
  ///
  /// `active = false` tira o senderista das listas e da busca sem tocar em
  /// nada do histórico clínico.
  Future<void> desativarSenderistas(List<String> ids) async {
    if (ids.isEmpty) return;
    await _client
        .from('top_participants')
        .update({'active': false})
        .inFilter('id', ids);
  }
}
