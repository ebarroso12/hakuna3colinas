import 'dart:math' as math;

/// Distância em linha reta entre coordenadas — cálculo determinístico
/// (fórmula de Haversine), sem depender de nenhum serviço de rotas.
///
/// Não implementa distância/tempo REAL por rota (que exigiria um provedor
/// pago tipo Google Directions ou um servidor OSRM próprio) — isso fica
/// pra quando o Dr. Edson decidir qual provedor aceita pagar/manter, já
/// que envolve custo recorrente e chave de API (ver auditoria/Fase 7).
/// Enquanto isso, a distância linear + uma estimativa grosseira de tempo a
/// pé já cobre a decisão operacional de "quem está mais perto".
class DistanceService {
  DistanceService._();

  static const _earthRadiusMeters = 6371000.0;

  /// Distância em metros entre dois pontos, em linha reta.
  static double meters({
    required double lat1,
    required double lng1,
    required double lat2,
    required double lng2,
  }) {
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return _earthRadiusMeters * c;
  }

  static double _toRad(double deg) => deg * math.pi / 180;

  /// Rótulo pronto pra tela: "420 m" ou "1,2 km".
  static String formatDistance(double meters) {
    if (meters < 1000) return '${meters.round()} m';
    return '${(meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
  }

  /// Estimativa GROSSEIRA de tempo a pé em trilha (linha reta, sem
  /// considerar relevo/obstáculo) — ~4,5 km/h, velocidade conservadora de
  /// caminhada em trilha. Sempre rotular como estimativa na UI.
  static int estimateWalkMinutes(double meters) {
    const walkingSpeedMetersPerMinute = 4500 / 60;
    return math.max(1, (meters / walkingSpeedMetersPerMinute).round());
  }
}
