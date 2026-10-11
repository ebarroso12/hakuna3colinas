enum TopStatus { draft, active, finished }

TopStatus topStatusFromString(String value) {
  return TopStatus.values.firstWhere(
    (s) => s.name == value,
    orElse: () => TopStatus.draft,
  );
}

class Top {
  final String id;
  final String name;
  final String? topNumber;

  /// Pista / local do evento ("Fazenda 3 Colinas").
  final String? location;

  /// Cidade. Separada de [location] porque são coisas diferentes: a pista
  /// tem nome próprio e a cidade é o que situa quem vem de fora.
  final String? cidade;

  /// Diretor responsável pelo Top.
  ///
  /// Campo informativo — quem manda no app é decidido por `role` e por
  /// `top_hakunas`, não por este texto. Serve para a equipe saber a quem
  /// recorrer no evento.
  final String? diretorResponsavel;

  /// Caminho do emblema/brasão da pista no Storage. Null = sem emblema.
  final String? emblemaPath;
  final String? description;
  final TopStatus status;
  final DateTime? startsAt;
  final DateTime? endsAt;

  /// Interruptor do autocadastro por número + senha do Top.
  ///
  /// A senha do Top é COMPARTILHADA e anunciada ao grupo: circula em
  /// WhatsApp, cartaz e voz. Depois que a equipe se cadastrou, ela
  /// continua valendo — e não deveria. Este campo fecha a porta sem
  /// precisar gerar senha nova (o que invalidaria a que todos anotaram).
  ///
  /// `true` por padrão, para não travar Top que já está rodando. A
  /// proteção de Top novo é outra: ele nasce em `draft`, e o autocadastro
  /// recusa draft.
  final bool autocadastroLiberado;

  Top({
    required this.id,
    required this.name,
    this.topNumber,
    this.location,
    this.cidade,
    this.diretorResponsavel,
    this.emblemaPath,
    this.description,
    required this.status,
    this.startsAt,
    this.endsAt,
    this.autocadastroLiberado = true,
  });

  factory Top.fromMap(Map<String, dynamic> map) {
    return Top(
      id: map['id'] as String,
      name: map['name'] as String,
      topNumber: map['top_number'] as String?,
      location: map['location'] as String?,
      cidade: map['cidade'] as String?,
      diretorResponsavel: map['diretor_responsavel'] as String?,
      emblemaPath: map['emblema_path'] as String?,
      description: map['description'] as String?,
      status: topStatusFromString(map['status'] as String),
      startsAt: map['starts_at'] != null
          ? DateTime.parse(map['starts_at'] as String)
          : null,
      endsAt: map['ends_at'] != null
          ? DateTime.parse(map['ends_at'] as String)
          : null,
      // `?? true` e nao `?? false`: consulta antiga que nao traga a coluna
      // nao deve FECHAR o cadastro de um Top que esta aberto.
      autocadastroLiberado: map['autocadastro_liberado'] as bool? ?? true,
    );
  }
}
