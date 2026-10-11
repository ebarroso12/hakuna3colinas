import 'team.dart';

/// O bloco de anotações de **uma pessoa** numa equipe.
///
/// É o equivalente não-médico do prontuário: o app é dos Legendários, e as
/// equipes precisam de um lugar para registrar o que acontece no turno —
/// mas sem nada clínico, que tem tabela e cerca próprias.
///
/// **Um bloco por membro, editável.** Era append-only na primeira versão,
/// por medo de duas pessoas sobrescreverem o texto uma da outra offline. O
/// dono do projeto apontou que isso não acontece: cada membro tem login
/// próprio e o bloco é dele. Sem concorrência, sem perda — e aí um bloco
/// que se edita é melhor que uma lista de recados.
///
/// Dois escopos, pelo mesmo modelo:
///
/// - com [participanteId]: o bloco daquela pessoa sobre **um participante**;
/// - sem [participanteId]: o bloco do **turno** dela naquela equipe.
class Anotacao {
  const Anotacao({
    required this.blocoId,
    required this.topId,
    required this.team,
    required this.autorId,
    required this.texto,
    required this.criadaEm,
    required this.atualizadoEm,
    this.id,
    this.participanteId,
    this.autorNome,
    this.participanteNome,
  });

  /// Chave do bloco: `<top>|<team>|<autor>|<participante ou ->`.
  ///
  /// Texto, e calculada no aparelho por [chaveDe] — então funciona offline,
  /// sem consultar nada. Não é índice composto porque `participante_id` é
  /// nulo no bloco do turno, e em Postgres NULL não conflita com NULL num
  /// índice único: dois blocos de turno da mesma pessoa não colidiriam e
  /// virariam duplicata. Resolver com índice **parcial** quebraria o upsert
  /// (o Postgres não infere índice parcial na forma simples do
  /// `ON CONFLICT` — foi o bug da v1.0.29, que mandou a fila inteira para
  /// quarentena).
  final String blocoId;

  /// Id do servidor. Null enquanto o bloco só existe no aparelho.
  final String? id;

  final String topId;
  final TeamKey team;
  final String autorId;
  final String texto;
  final DateTime criadaEm;

  /// Hora da última edição, **do aparelho**. Offline a edição acontece
  /// horas antes do upload.
  final DateTime atualizadoEm;

  final String? participanteId;

  /// Vêm do join, para a lista não fazer uma busca por linha. Null quando
  /// o bloco foi lido da fila local — e aí o autor é quem está olhando.
  final String? autorNome;
  final String? participanteNome;

  bool get sobrePessoa => participanteId != null;

  /// Monta a chave do bloco. **Não mudar o formato**: o valor está gravado
  /// no banco e é por ele que o upsert encontra o bloco existente. Mudar
  /// faria cada aparelho criar um bloco novo em vez de editar o seu.
  static String chaveDe({
    required String topId,
    required TeamKey team,
    required String autorId,
    String? participanteId,
  }) => '$topId|${team.name}|$autorId|${participanteId ?? '-'}';

  Anotacao comTexto(String novoTexto, DateTime quando) => Anotacao(
    blocoId: blocoId,
    id: id,
    topId: topId,
    team: team,
    autorId: autorId,
    texto: novoTexto,
    criadaEm: criadaEm,
    atualizadoEm: quando,
    participanteId: participanteId,
    autorNome: autorNome,
    participanteNome: participanteNome,
  );

  factory Anotacao.fromMap(Map<String, dynamic> map) {
    final criada = DateTime.parse(map['criada_em'] as String);
    return Anotacao(
      blocoId: map['bloco_id'] as String,
      id: map['id'] as String?,
      topId: map['top_id'] as String,
      // `?? TeamKey.geral` e não `!`: equipe nova no banco com app antigo
      // instalado não deve derrubar a tela inteira.
      team: teamKeyFromString(map['team'] as String?) ?? TeamKey.geral,
      autorId: map['autor_id'] as String,
      texto: map['texto'] as String,
      criadaEm: criada,
      // Bloco gravado antes da coluna existir cai em `criada_em`.
      atualizadoEm: map['atualizado_em'] != null
          ? DateTime.parse(map['atualizado_em'] as String)
          : criada,
      participanteId: map['participante_id'] as String?,
      autorNome: _nomeDe(map['autor']),
      participanteNome: _nomeDe(map['participante']),
    );
  }

  /// Extrai `full_name` de um join do Postgrest.
  ///
  /// Ele devolve relação como objeto OU como lista de um item, conforme a
  /// cardinalidade que infere. Tratar só um dos dois daria um cast que
  /// estoura em campo por causa do formato da resposta.
  static String? _nomeDe(Object? bruto) {
    if (bruto is Map<String, dynamic>) return bruto['full_name'] as String?;
    if (bruto is List && bruto.isNotEmpty) {
      final primeiro = bruto.first;
      if (primeiro is Map<String, dynamic>) {
        return primeiro['full_name'] as String?;
      }
    }
    return null;
  }

  /// O que vai para o servidor.
  ///
  /// `id` fica de fora: quem identifica o bloco é `bloco_id`, e mandar um
  /// `id` nulo num upsert faria o Postgres recusar a chave primária.
  /// Os nomes dos joins também: são leitura, não coluna desta tabela —
  /// mandá-los daria erro de coluna inexistente, classificado como
  /// PERMANENTE e mandado para quarentena.
  Map<String, dynamic> toMap() => {
    'bloco_id': blocoId,
    'top_id': topId,
    'team': team.name,
    'autor_id': autorId,
    'participante_id': participanteId,
    'texto': texto,
    'criada_em': criadaEm.toUtc().toIso8601String(),
    'atualizado_em': atualizadoEm.toUtc().toIso8601String(),
  };
}
