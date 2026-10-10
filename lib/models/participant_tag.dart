import 'dart:math';

/// Situação de uma tag. Espelha o enum `tag_status` do Postgres.
enum TagStatus { ativa, revogada, substituida }

TagStatus tagStatusFromString(String? v) {
  for (final s in TagStatus.values) {
    if (s.name == v) return s;
  }
  // Status desconhecido é tratado como revogada: na dúvida, não libera.
  return TagStatus.revogada;
}

extension TagStatusUi on TagStatus {
  String get label => switch (this) {
    TagStatus.ativa => 'Ativa',
    TagStatus.revogada => 'Revogada',
    TagStatus.substituida => 'Substituída',
  };

  bool get valida => this == TagStatus.ativa;
}

/// Vínculo entre uma pulseira/cartão NFC e um participante.
///
/// A tag grava **apenas** [token] — um valor aleatório sem significado.
/// Nunca nome, documento, telefone ou dado médico: quem acha a pulseira no
/// chão não pode descobrir nada sobre a pessoa.
///
/// E o mais importante: **ler a tag não autentica ninguém**. NTAG213/215
/// são clonáveis, então posse da pulseira não prova identidade. O token só
/// é resolvido para quem já está logado e é Hakuna liberado no Top.
class ParticipantTag {
  final String id;
  final String token;
  final String participantId;
  final String topId;
  final TagStatus status;

  /// UID de fábrica. Guardado só para inventário físico — saber qual
  /// pulseira é qual na caixa. Nunca para identificar pessoa.
  final String? tagUid;

  final DateTime issuedAt;
  final DateTime? revokedAt;
  final String? revokedReason;
  final String? replacedByToken;

  ParticipantTag({
    required this.id,
    required this.token,
    required this.participantId,
    required this.topId,
    required this.status,
    required this.issuedAt,
    this.tagUid,
    this.revokedAt,
    this.revokedReason,
    this.replacedByToken,
  });

  factory ParticipantTag.fromMap(Map<String, dynamic> map) {
    return ParticipantTag(
      id: map['id'] as String,
      token: map['token'] as String,
      participantId: map['participant_id'] as String,
      topId: map['top_id'] as String,
      status: tagStatusFromString(map['status'] as String?),
      tagUid: map['tag_uid'] as String?,
      issuedAt: DateTime.parse(map['issued_at'] as String),
      revokedAt: map['revoked_at'] != null
          ? DateTime.parse(map['revoked_at'] as String)
          : null,
      revokedReason: map['revoked_reason'] as String?,
      replacedByToken: map['replaced_by_token'] as String?,
    );
  }

  bool get valida => status.valida;
}

/// Como a tag é lida e escrita.
abstract final class TagNdef {
  /// Prefixo da URL gravada na tag.
  ///
  /// O app lê o token direto do NDEF e resolve **no banco local**, por isso
  /// a leitura funciona sem internet. A URL existe para a tag ser um NDEF
  /// válido e para um celular sem o app não ver nada de útil.
  static const prefixo = 'https://legendarios.app/t/';

  static final _rand = Random.secure();

  /// Token novo: 16 bytes aleatórios em hex. 128 bits não se adivinha nem
  /// se enumera.
  static String novoToken() {
    final bytes = List<int>.generate(16, (_) => _rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// O que vai gravado na pulseira.
  static String urlPara(String token) => '$prefixo$token';

  /// Extrai o token de uma URL lida da tag.
  ///
  /// Aceita a URL inteira ou só o token, e tolera variação de host — o que
  /// importa é o último segmento. Devolve null se não parecer um token
  /// válido, para tag de outro sistema não virar consulta inútil.
  static String? tokenDe(String? conteudo) {
    if (conteudo == null) return null;
    final limpo = conteudo.trim();
    if (limpo.isEmpty) return null;

    final candidato = limpo.contains('/')
        ? limpo.split('/').where((s) => s.isNotEmpty).last
        : limpo;

    // Só hex de 32 caracteres é token nosso.
    if (!RegExp(r'^[0-9a-fA-F]{32}$').hasMatch(candidato)) return null;
    return candidato.toLowerCase();
  }
}

/// O que acontece ao encostar o celular numa tag.
enum ResultadoLeitura {
  /// Token válido e participante encontrado.
  ok,

  /// Tag legível, mas o token não está no sistema.
  desconhecida,

  /// Token existe e foi revogado — pulseira perdida ou trocada.
  revogada,

  /// Não é uma tag deste sistema.
  formatoInvalido,

  /// Sem internet e o token não está no cache local.
  semDados,
}

extension ResultadoLeituraUi on ResultadoLeitura {
  String get mensagem => switch (this) {
    ResultadoLeitura.ok => 'Participante identificado',
    ResultadoLeitura.desconhecida =>
      'Tag não reconhecida. Ela não está vinculada a nenhum participante '
          'deste Top.',
    ResultadoLeitura.revogada =>
      'Esta tag foi REVOGADA e não vale mais. Confirme a identidade pelo '
          'nome na lista.',
    ResultadoLeitura.formatoInvalido =>
      'Esta tag não é do sistema dos Legendários.',
    ResultadoLeitura.semDados =>
      'Sem internet e esta tag não está na memória do aparelho. Busque '
          'pelo nome na lista.',
  };

  /// Valor que vai para o log de auditoria.
  String get paraAuditoria => name;
}
