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
  Future<String> liberar(String numero) async {
    final resposta = await _client.functions.invoke(
      _funcao,
      body: {'acao': 'liberar', 'numero': numero.trim()},
    );
    final dados = resposta.data as Map<String, dynamic>?;
    final codigo = dados?['codigo'] as String?;
    if (codigo == null) {
      throw StateError(
        dados?['error'] as String? ?? 'Não foi possível gerar o código.',
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
