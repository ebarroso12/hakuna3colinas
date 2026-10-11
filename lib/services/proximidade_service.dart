import 'package:geolocator/geolocator.dart';

import '../models/hakuna_position.dart';

/// Um Hakuna e a distância dele até um ponto.
class HakunaProximo {
  const HakunaProximo({
    required this.profileId,
    required this.metros,
    required this.posicao,
  });

  final String profileId;
  final double metros;
  final HakunaPosition posicao;

  /// Há quanto tempo essa posição foi registrada.
  ///
  /// Importa tanto quanto a distância: um ponto de 40 minutos atrás diz
  /// onde a pessoa **estava**, e numa trilha 40 minutos são dois ou três
  /// quilômetros. Quem decide quem vai atender precisa ver os dois
  /// números juntos.
  Duration get idade => DateTime.now().toUtc().difference(posicao.recordedAt);

  /// Distância em texto curto: "320 m" ou "2,4 km".
  String get distanciaFormatada => metros < 1000
      ? '${metros.round()} m'
      : '${(metros / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';

  /// Idade da posição em texto curto: "agora", "8 min", "1 h 10".
  String get idadeFormatada {
    final m = idade.inMinutes;
    if (m < 2) return 'agora';
    if (m < 60) return '$m min';
    final h = idade.inHours;
    return '$h h ${m - h * 60}';
  }
}

/// Responde "quem está mais perto?".
///
/// A pergunta não tinha resposta no app: havia GPS dos Hakunas, havia
/// atendimento e alarme com coordenada, e **nada cruzava os dois**. Na
/// prática a coordenação era por rádio, perguntando quem estava onde — com
/// a informação já no banco, sem ninguém para ler.
///
/// Cálculo só com o que está no aparelho: a distância é a de Haversine do
/// `geolocator`, que é a mesma conta que [StatsService] já usa para a
/// trilha. Nenhuma API de rotas — não há sinal para isso, e rota de trilha
/// não existe em mapa de rua de qualquer forma. Então o número é a
/// distância em **linha reta**, que subestima a caminhada real. Serve para
/// ordenar quem está mais perto, não para prometer tempo de chegada.
class ProximidadeService {
  ProximidadeService._();

  /// Posições cuja idade passa disto são descartadas.
  ///
  /// Duas horas: mais que isso e o ponto não diz mais onde a pessoa está,
  /// diz onde ela passou. Mostrar "250 m" baseado num ponto de três horas
  /// atrás é pior que não mostrar nada, porque alguém vai confiar.
  static const idadeMaxima = Duration(hours: 2);

  /// Hakunas ordenados do mais perto ao mais longe do ponto dado.
  ///
  /// [posicoes] pode ter vários pontos do mesmo Hakuna — a trilha inteira,
  /// como vem de `fetchPositions`. Só a **última** posição de cada um é
  /// considerada: as anteriores são histórico, e usar a mais perto da
  /// trilha diria que alguém está a 50 m porque passou ali de manhã.
  static List<HakunaProximo> maisProximos({
    required double latitude,
    required double longitude,
    required List<HakunaPosition> posicoes,
    Duration? idadeMaxima,
  }) {
    final limite = idadeMaxima ?? ProximidadeService.idadeMaxima;
    final agora = DateTime.now().toUtc();

    final ultimaDeCada = <String, HakunaPosition>{};
    for (final p in posicoes) {
      final atual = ultimaDeCada[p.profileId];
      if (atual == null || p.recordedAt.isAfter(atual.recordedAt)) {
        ultimaDeCada[p.profileId] = p;
      }
    }

    final resultado = <HakunaProximo>[];
    for (final p in ultimaDeCada.values) {
      if (agora.difference(p.recordedAt) > limite) continue;
      resultado.add(
        HakunaProximo(
          profileId: p.profileId,
          metros: Geolocator.distanceBetween(
            latitude,
            longitude,
            p.latitude,
            p.longitude,
          ),
          posicao: p,
        ),
      );
    }

    resultado.sort((a, b) => a.metros.compareTo(b.metros));
    return resultado;
  }
}
