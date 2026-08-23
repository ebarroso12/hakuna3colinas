import 'package:geolocator/geolocator.dart';

import '../models/hakuna_position.dart';
import '../models/top_stats.dart';

/// Calcula distância, velocidade média e gasto calórico a partir da trilha
/// de GPS já registrada em hakuna_positions — sem nenhuma API externa. A
/// distância entre pontos vem da fórmula de Haversine (Geolocator.distanceBetween),
/// que é a mesma conta que qualquer serviço de mapas faria com dois pontos.
class StatsService {
  StatsService._();

  /// Peso padrão (kg) usado na estimativa de calorias quando o Hakuna não
  /// informou o próprio peso no cadastro — deixa a estimativa aproximada em
  /// vez de travar o cálculo por falta de um dado opcional.
  static const double _defaultWeightKg = 70;

  /// [positions] deve estar ordenado por recorded_at crescente e conter
  /// apenas os pontos de um único Hakuna em um único Top.
  static TopStats compute(List<HakunaPosition> positions, {double? weightKg}) {
    if (positions.length < 2) return TopStats.zero;

    double distanceMeters = 0;
    for (var i = 1; i < positions.length; i++) {
      final prev = positions[i - 1];
      final cur = positions[i];
      distanceMeters += Geolocator.distanceBetween(
        prev.latitude,
        prev.longitude,
        cur.latitude,
        cur.longitude,
      );
    }

    final duration = positions.last.recordedAt.difference(positions.first.recordedAt);
    final hours = duration.inSeconds / 3600;
    final avgSpeedKmh = hours > 0 ? (distanceMeters / 1000) / hours : 0.0;

    return TopStats(
      distanceMeters: distanceMeters,
      avgSpeedKmh: avgSpeedKmh,
      calories: _estimateCalories(avgSpeedKmh: avgSpeedKmh, hours: hours, weightKg: weightKg ?? _defaultWeightKg),
      duration: duration,
      caloriesIsEstimate: weightKg == null,
    );
  }

  /// Estimativa por MET (Metabolic Equivalent of Task), o método padrão pra
  /// gasto calórico a partir de atividade + peso + tempo — não é medição
  /// médica exata, é a mesma aproximação usada em relógios/apps de fitness.
  /// MET sobe com a velocidade média porque trilha em ritmo mais forte
  /// (subida, terreno irregular) consome mais energia por hora.
  static double _estimateCalories({required double avgSpeedKmh, required double hours, required double weightKg}) {
    final met = switch (avgSpeedKmh) {
      <= 0 => 0.0,
      < 3 => 3.5, // caminhada leve
      < 5 => 5.0, // caminhada/trilha moderada
      < 7 => 7.0, // trilha em ritmo forte / subida
      _ => 8.5, // trilha rápida
    };
    return met * weightKg * hours;
  }
}
