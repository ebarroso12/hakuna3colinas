import 'package:supabase_flutter/supabase_flutter.dart';

/// Pedido de acesso visto pelo admin.
class PedidoAcesso {
  final String id;
  final String numero;
  final String? nome;
  final String? telefone;
  final String status;
  final DateTime solicitadoEm;

  PedidoAcesso({
    required this.id,
    required this.numero,
    required this.status,
    required this.solicitadoEm,
    this.nome,
    this.telefone,
  });

  factory PedidoAcesso.fromMap(Map<String, dynamic> map) => PedidoAcesso(
    id: map['id'] as String,
    numero: map['legendarios_number'] as String,
    nome: map['full_name'] as String?,
    telefone: map['phone'] as String?,
    status: map['status'] as String,
    solicitadoEm: DateTime.parse(map['requested_at'] as String),
  );

  bool get pendente => status == 'pendente';
}

/// Entrada no app pelo número do Legendários.
///
/// O Supabase Auth exige um identificador em formato de e-mail, então o
/// número vira `<numero>@legendarios.app` por baixo. **Nenhum e-mail é
/// enviado para esse endereço** — ele existe só como identificador, e o
/// usuário digita apenas o número.
///
/// Criar conta e definir senha exigem a chave `service_role`, que não pode
/// ir dentro do APK: quem extraísse o arquivo viraria admin do projeto.
/// Por isso essas operações vivem na Edge Function `acesso`, no servidor.
class AcessoService {
  AcessoService._();

  static final AcessoService instance = AcessoService._();

  static const dominioInterno = 'legendarios.app';
  static const _funcao = 'acesso';

  SupabaseClient get _client => Supabase.instance.client;

  /// Identificador interno a partir do número. Só dígitos entram.
  static String emailPara(String numero) => '${numero.trim()}@$dominioInterno';

  /// Converte o que a pessoa digitou no e-mail que o Supabase Auth espera.
  ///
  /// Um campo só para as duas formas de entrar, em vez de obrigar a
  /// escolher "modo número" ou "modo e-mail" antes de digitar:
  ///
  /// ```
  ///   203460                  ->  203460@legendarios.app
  ///   edson.barroso@gmail.com ->  edson.barroso@gmail.com
  /// ```
  ///
  /// A regra é a presença do `@`. Número do Legendários é só dígito (ver
  /// [regexNumero]), então nunca contém arroba — não há ambiguidade.
  ///
  /// **Os dois caminhos existem porque servem a gente diferente.** O
  /// Legendário entra por número: é a identidade dele no movimento, e
  /// `203460@legendarios.app` não é caixa de entrada nenhuma — ninguém
  /// nunca digita isso. Admin e equipe entram por e-mail real, porque
  /// foram cadastrados assim e precisam de recuperação por e-mail.
  ///
  /// Quem libera e-mail é o admin, pelo `approved` em `profiles`: conta
  /// criada sem aprovação autentica mas para na tela de espera do
  /// `AuthGate`. Autenticar e ter acesso são coisas separadas aqui.
  ///
  /// **Armadilha conhecida:** quem tem número E e-mail próprio precisa
  /// entrar pelo e-mail. O admin master, por exemplo, tem
  /// `legendarios_number = 203460` mas conta no Gmail; digitar 203460
  /// procuraria `203460@legendarios.app`, que não existe. São contas
  /// diferentes para o Supabase, e unificá-las custaria a recuperação por
  /// e-mail dele.
  static String identificadorParaEmail(String digitado) {
    final texto = digitado.trim();
    if (texto.contains('@')) return texto;
    return emailPara(texto);
  }

  /// Número do Legendários: só dígitos, de 1 a 12.
  ///
  /// Era `{4,10}`. Mudou porque ninguém sabe até onde a numeração vai
  /// chegar, e um teto apertado quebraria o cadastro de gente real no dia
  /// do evento — sem ninguém entender por quê, já que a mensagem só diria
  /// "número inválido".
  ///
  /// O mínimo caiu para 1 pelo motivo inverso: Legendários antigos podem
  /// ter número curto, e barrar "7" seria inventar uma regra que o
  /// movimento não tem.
  ///
  /// Isto é validação de **formato**, não de segurança. Quem decide se o
  /// número vale é a lista do Top (`participante_elegivel`), conferida no
  /// servidor. Aqui só se evita mandar letra e espaço para a API.
  ///
  /// **Esta regra existe em dois lugares e eles têm de andar juntos:** aqui
  /// e em `numeroValido` na Edge Function `acesso`. TypeScript não importa
  /// Dart; se um mudar sem o outro, o app aceita e o servidor recusa.
  static const regexNumero = r'^[0-9]{1,12}$';

  static bool numeroValido(String numero) =>
      RegExp(regexNumero).hasMatch(numero.trim());

  /// O Legendário pede acesso. Não exige estar logado.
  ///
  /// A resposta é sempre a mesma, exista o número ou não — senão daria
  /// para descobrir quem é Legendário testando números um a um.
  Future<String> solicitar({
    required String numero,
    String? nome,
    String? telefone,
  }) async {
    final resposta = await _client.functions.invoke(
      _funcao,
      body: {
        'acao': 'solicitar',
        'numero': numero.trim(),
        if (nome != null && nome.trim().isNotEmpty) 'nome': nome.trim(),
        if (telefone != null && telefone.trim().isNotEmpty)
          'telefone': telefone.trim(),
      },
    );
    final dados = resposta.data as Map<String, dynamic>?;
    return dados?['mensagem'] as String? ??
        'Pedido registrado. Aguarde o código do administrador.';
  }

  // =====================================================================
  // AUTOCADASTRO POR SENHA DO TOP
  //
  //   1. admin gera UMA senha e anuncia ao grupo
  //   2. Legendário digita número + senha do Top   -> [validarConvite]
  //   3. preenche a ficha e cria a senha dele      -> [cadastrar]
  //   4. daí em diante entra com número + senha pessoal
  //
  // A senha do Top é CONVITE, não senha de entrada. Se servisse para
  // entrar, o Legendário 203460 digitaria o número 441892 com a mesma
  // senha e abriria o prontuário do outro.
  // =====================================================================

  /// Passo 1: confere número + senha do Top. Não cria nada, não loga.
  ///
  /// Devolve o nome e a família que já estão na lista do Top, para a tela
  /// de cadastro vir preenchida — os Legendários do evento já existem como
  /// participantes, só sem conta.
  ///
  /// Lança [AcessoRecusado] com a mensagem do servidor quando o convite
  /// não vale. A mensagem é a mesma para senha errada e para número fora
  /// da lista, de propósito: distingui-las deixaria descobrir quem está
  /// inscrito testando números.
  Future<ConviteValidado> validarConvite({
    required String numero,
    required String senhaDoTop,
  }) async {
    final resposta = await _invocar({
      'acao': 'validar_convite',
      'numero': numero.trim(),
      'senha_top': senhaDoTop.trim(),
    });
    return ConviteValidado(
      topId: resposta['top_id'] as String,
      topNome: resposta['top_nome'] as String? ?? '',
      nome: resposta['nome'] as String? ?? '',
      familia: resposta['familia'] as String?,
    );
  }

  /// Passo 2: cria a conta com a senha PESSOAL e vincula a ficha.
  ///
  /// [ficha] usa os mesmos nomes de coluna do Postgres (`full_name`,
  /// `blood_type`, `comorbidades`…), como o resto do projeto — ver a
  /// convenção em CLAUDE.md.
  ///
  /// O servidor revalida a senha do Top do zero: o passo 1 serviu para
  /// montar a tela, não como permissão. Se desse para pular direto para
  /// cá, a validação do cliente não valeria nada.
  Future<void> cadastrar({
    required String numero,
    required String senhaDoTop,
    required String senhaPessoal,
    required Map<String, dynamic> ficha,
  }) async {
    await _invocar({
      'acao': 'cadastrar',
      'numero': numero.trim(),
      'senha_top': senhaDoTop.trim(),
      'senha': senhaPessoal,
      'ficha': ficha,
    });
  }

  /// Gera (ou regera) a senha de convite do Top. Só admin.
  ///
  /// Devolve a senha em claro **uma única vez** — o banco guarda só o
  /// hash. Gerar de novo invalida a anterior na hora, que é como se corta
  /// o acesso quando a senha vaza para fora do grupo.
  Future<SenhaDoTop> gerarSenhaDoTop(String topId) async {
    final r = await _invocar({'acao': 'gerar_senha_top', 'top_id': topId});
    return SenhaDoTop(
      senha: r['senha'] as String,
      topNome: r['top_nome'] as String? ?? '',
      topNumero: r['top_numero'] as String?,
      aviso: r['aviso'] as String?,
    );
  }

  /// Chama a Edge Function e transforma a recusa em exceção com a mensagem
  /// que o servidor escreveu.
  ///
  /// Sem isto, `functions.invoke` devolve `FunctionException` com o corpo
  /// cru dentro — e a tela mostraria JSON ao Hakuna. As mensagens de lá
  /// são escritas para serem lidas por quem está se cadastrando.
  Future<Map<String, dynamic>> _invocar(Map<String, dynamic> corpo) async {
    try {
      final resposta = await _client.functions.invoke(_funcao, body: corpo);
      final dados = resposta.data as Map<String, dynamic>?;
      if (dados == null) throw const AcessoRecusado('resposta vazia');
      if (dados['error'] != null) {
        throw AcessoRecusado(
          dados['mensagem'] as String? ?? dados['error'].toString(),
        );
      }
      return dados;
    } on FunctionException catch (e) {
      final detalhes = e.details;
      if (detalhes is Map) {
        final msg = detalhes['mensagem'] ?? detalhes['error'];
        if (msg != null) throw AcessoRecusado(msg.toString());
      }
      throw AcessoRecusado('Não foi possível falar com o servidor.');
    }
  }

  /// Entra com número + código.
  ///
  /// O código é a senha da conta, definida pelo admin ao liberar. Depois
  /// disso o `supabase_flutter` mantém a sessão e renova o token sozinho —
  /// não é preciso entrar de novo até deslogar.
  Future<AuthResponse> entrarComCodigo({
    required String numero,
    required String codigo,
  }) {
    return _client.auth.signInWithPassword(
      email: emailPara(numero),
      password: codigo.trim().toUpperCase(),
    );
  }

  /// Entra com NUMERO do Legendarios, seja qual for o e-mail da conta.
  ///
  /// `signInWithPassword(email: emailPara(numero))` so funciona para quem
  /// se cadastrou pelo "Primeiro acesso", porque so esse caminho cria a
  /// conta como `<numero>@legendarios.app`. Quem criou a conta com e-mail
  /// proprio ou pelo Google tem OUTRO e-mail no `auth.users`, e o numero
  /// dele nao abria porta nenhuma: a tela dizia "numero ou senha
  /// incorretos" com a senha certa.
  ///
  /// Aconteceu com o admin master em 11/10/2026 — numero 203460, conta no
  /// Gmail. E ia acontecer com todo mundo que entrasse pelo Google.
  ///
  /// Descobrir o e-mail real exige ler `auth.users`, que so o service_role
  /// le — por isso a resolucao fica na Edge Function e nao aqui. O app
  /// recebe de volta apenas os tokens e monta a sessao com eles; o e-mail
  /// da outra pessoa nunca passa pelo aparelho.
  Future<void> entrarPorNumeroOuEmail({
    required String identificador,
    required String senha,
  }) async {
    // Funcao SEPARADA, nao uma acao dentro de `acesso`. `acesso` tem 780
    // linhas e publicar qualquer mudanca nela exige reenviar o arquivo
    // inteiro — foi assim que ela ja foi destruida uma vez neste projeto.
    // Login cabe em 100 linhas e e outra preocupacao: separado, um nao
    // quebra o outro.
    final Map<String, dynamic> dados;
    try {
      final resposta = await _client.functions.invoke(
        'login',
        body: {'identificador': identificador.trim(), 'senha': senha},
      );
      dados = (resposta.data as Map<String, dynamic>?) ?? const {};
    } on FunctionException catch (e) {
      // Senha errada volta 401, e `invoke` LANCA em status fora do 2xx —
      // o corpo com a mensagem vem dentro de `details`, nao em `data`.
      // Sem este catch, a recusa normal de login apareceria na tela como
      // "FunctionException", que e o tipo de erro cru que esta tela
      // existe para nao mostrar.
      final detalhes = e.details;
      if (detalhes is Map && detalhes['error'] != null) {
        throw AcessoRecusado(detalhes['error'].toString());
      }
      throw const AcessoRecusado('Número/e-mail ou senha incorretos.');
    }

    final refresh = dados['refresh_token'] as String?;
    if (refresh == null) {
      throw const AcessoRecusado(
        'Não foi possível entrar. Tente de novo em instantes.',
      );
    }

    // `setSession` com o refresh token, e nao `recoverSession`: e o caminho
    // que o `supabase_flutter` usa para assumir uma sessao vinda de fora e
    // passar a renova-la sozinho dali em diante.
    await _client.auth.setSession(refresh);
  }

  // --- daqui pra baixo, só admin ---

  Future<List<PedidoAcesso>> pedidos({bool apenasPendentes = true}) async {
    var consulta = _client.from('access_requests').select();
    if (apenasPendentes) consulta = consulta.eq('status', 'pendente');
    final linhas = await consulta.order('requested_at', ascending: false);
    return linhas.map((l) => PedidoAcesso.fromMap(l)).toList();
  }

  /// Libera o acesso e devolve o código em claro.
  ///
  /// O código volta **uma única vez**: o banco guarda só o hash. Admin que
  /// perder o código gera outro — é mais seguro que deixá-lo legível no
  /// banco para sempre.
  ///
  /// Lança [ContaComEmailProprio] quando a pessoa já entra por e-mail: o
  /// servidor recusa com 409 em vez de trocar a senha calada. Para seguir,
  /// chame de novo com [confirmarTrocaDeSenha] — depois de perguntar.
  Future<String> liberar(
    String numero, {
    bool confirmarTrocaDeSenha = false,
  }) async {
    final n = numero.trim();
    final Map<String, dynamic> dados;
    try {
      final resposta = await _client.functions.invoke(
        _funcao,
        body: {
          'acao': 'liberar',
          'numero': n,
          if (confirmarTrocaDeSenha) 'confirmar_troca_de_senha': true,
        },
      );
      dados = (resposta.data as Map<String, dynamic>?) ?? const {};
    } on FunctionException catch (e) {
      // O 409 `conta_com_email_proprio` NAO e falha: e a Edge Function
      // pedindo confirmação, porque gerar código substitui a senha de uma
      // conta que entra por e-mail.
      //
      // Sem este catch ele chegava cru na tela como
      // `FunctionsHttpException(status: 409, details: {...})`, com a
      // instrução `repita a chamada com "confirmar_troca_de_senha": true`
      // — que é instrução para quem chama a API, não para o admin que
      // está olhando o celular. E a tela não tinha como obedecê-la: o
      // caminho existia no servidor e era inalcançável pelo app, o mesmo
      // defeito de "UI mais restrita que o banco" que já apareceu no
      // botão de emergência e nas 9 equipes.
      final detalhes = e.details;
      if (detalhes is Map) {
        if (detalhes['error'] == 'conta_com_email_proprio') {
          throw ContaComEmailProprio(
            n,
            (detalhes['email_da_conta'] ?? '?').toString(),
          );
        }
        final msg = detalhes['mensagem'] ?? detalhes['error'];
        if (msg != null) throw AcessoRecusado(msg.toString());
      }
      throw const AcessoRecusado('Não foi possível falar com o servidor.');
    }

    final codigo = dados['codigo'] as String?;
    if (codigo == null) {
      throw AcessoRecusado(
        dados['error'] as String? ?? 'Não foi possível gerar o código.',
      );
    }
    return codigo;
  }

  Future<void> negar(String numero, {String? motivo}) async {
    await _client.functions.invoke(
      _funcao,
      body: {'acao': 'negar', 'numero': numero.trim(), 'motivo': ?motivo},
    );
  }
}

/// Recusa do servidor, com a mensagem pronta para a tela.
///
/// Existe para a tela não precisar abrir JSON nem adivinhar código HTTP:
/// as mensagens da Edge Function são escritas para quem está se
/// cadastrando ler ("este Top ainda não foi aberto pelo administrador"),
/// não para desenvolvedor.
class AcessoRecusado implements Exception {
  final String mensagem;
  const AcessoRecusado(this.mensagem);

  @override
  String toString() => mensagem;
}

/// O Legendário já tem conta, e ela entra por **e-mail próprio**.
///
/// Gerar código substitui a senha dessa conta — e para quem entra por
/// e-mail isso apaga o único jeito de acessar. Por isso a Edge Function
/// recusa com 409 e exige confirmação explícita, em vez de trocar calada.
///
/// A tela pergunta e, só com o sim, chama
/// `liberar(numero, confirmarTrocaDeSenha: true)`.
class ContaComEmailProprio implements Exception {
  final String numero;
  final String email;
  const ContaComEmailProprio(this.numero, this.email);

  @override
  String toString() =>
      'O Legendário $numero já tem conta com e-mail próprio ($email).';
}

/// O que o servidor devolveu quando o convite vale.
///
/// [nome] e [familia] vêm da lista de participantes do Top — a pessoa já
/// está lá, só sem conta. A tela de cadastro abre com eles preenchidos,
/// o que também serve de conferência: se o nome não for o dela, digitou o
/// número de outra pessoa.
class ConviteValidado {
  final String topId;
  final String topNome;
  final String nome;
  final String? familia;

  const ConviteValidado({
    required this.topId,
    required this.topNome,
    required this.nome,
    this.familia,
  });
}

/// Senha de convite recém-gerada, devolvida ao admin uma única vez.
class SenhaDoTop {
  final String senha;
  final String topNome;
  final String? topNumero;

  /// Preenchido quando algo impede o cadastro mesmo com a senha na mão —
  /// hoje, Top em rascunho. Avisar aqui evita o admin distribuir a senha
  /// e só descobrir depois que ninguém consegue entrar.
  final String? aviso;

  const SenhaDoTop({
    required this.senha,
    required this.topNome,
    this.topNumero,
    this.aviso,
  });
}
