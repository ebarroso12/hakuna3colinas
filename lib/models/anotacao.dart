import 'team.dart';

/// Uma anotação de equipe.
///
/// É o equivalente **não-médico** do prontuário: o app é dos Legendários,
/// não só dos Hakunas, e as outras 8 equipes precisam de um lugar para
/// registrar o que aconteceu no turno.
///
/// Dois usos, cobertos pelo mesmo modelo:
///
/// - com [participanteId]: anotação **sobre uma pessoa** ("perdeu a
///   mochila", "saiu da trilha no km 8");
/// - sem [participanteId]: anotação **do turno** ("portão 2 sem cobertura
///   das 14h às 15h").
///
/// **Não é lugar de dado clínico.** Sintoma, sinal vital e conduta vão em
/// `atendimentos` — escritos aqui, ficariam fora da triagem e invisíveis
/// para quem vai atender. A tela avisa isso em cima do campo.
class Anotacao {
  const Anotacao({
    required this.id,
    required this.topId,
    required this.team,
    required this.autorId,
    required this.texto,
    required this.criadaEm,
    this.participanteId,
    this.autorNome,
    this.participanteNome,
  });

  final String id;
  final String topId;
  final TeamKey team;
  final String autorId;
  final String texto;
  final DateTime criadaEm;
  final String? participanteId;

  /// Nomes vêm da consulta com join, para a lista não fazer N buscas.
  /// Null quando a anotação foi lida da fila local (ainda não subiu) — e
  /// aí quem a escreveu é quem está olhando.
  final String? autorNome;
  final String? participanteNome;

  bool get sobrePessoa => participanteId != null;

  factory Anotacao.fromMap(Map<String, dynamic> map) {
    return Anotacao(
      id: map['id'] as String,
      topId: map['top_id'] as String,
      // `?? TeamKey.geral` e não `!`: equipe desconhecida (enum novo no
      // banco, app antigo) não deve derrubar a tela inteira.
      team: teamKeyFromString(map['team'] as String?) ?? TeamKey.geral,
      autorId: map['autor_id'] as String,
      texto: map['texto'] as String,
      criadaEm: DateTime.parse(map['criada_em'] as String),
      participanteId: map['participante_id'] as String?,
      autorNome: _nomeDe(map['autor']),
      participanteNome: _nomeDe(map['participante']),
    );
  }

  /// Extrai `full_name` de um join do Postgrest.
  ///
  /// O Postgrest devolve relação como objeto ou como lista de um item,
  /// dependendo da cardinalidade que ele infere. Tratar os dois evita um
  /// cast que estoura em campo por causa do formato da resposta.
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

  /// O que vai para o servidor. Os nomes dos joins ficam de fora: são
  /// leitura, não dado desta linha.
  Map<String, dynamic> toMap() => {
    'id': id,
    'top_id': topId,
    'team': team.name,
    'autor_id': autorId,
    'participante_id': participanteId,
    'texto': texto,
    'criada_em': criadaEm.toUtc().toIso8601String(),
  };
}
