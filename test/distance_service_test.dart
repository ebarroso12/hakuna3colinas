import 'package:flutter_test/flutter_test.dart';
import 'package:hakuna_connect/services/distance_service.dart';

void main() {
  group('DistanceService.meters', () {
    test('distancia entre o mesmo ponto e zero', () {
      final d = DistanceService.meters(
        lat1: -23.55,
        lng1: -46.63,
        lat2: -23.55,
        lng2: -46.63,
      );
      expect(d, closeTo(0, 0.001));
    });

    test('distancia conhecida entre dois pontos (~1.1 km em 0.01 grau de latitude)', () {
      // 0.01 grau de latitude equivale a ~1.11 km, praticamente constante
      // em qualquer lugar do planeta (diferente de longitude).
      final d = DistanceService.meters(lat1: 0, lng1: 0, lat2: 0.01, lng2: 0);
      expect(d, closeTo(1113, 5));
    });

    test('nao inflaciona por jitter de GPS ruim (pontos muito proximos ficam em metros, nao km)', () {
      final d = DistanceService.meters(
        lat1: -23.55052,
        lng1: -46.63331,
        lat2: -23.55053,
        lng2: -46.63332,
      );
      expect(d, lessThan(5));
    });
  });

  group('DistanceService.formatDistance', () {
    test('mostra metros abaixo de 1km', () {
      expect(DistanceService.formatDistance(420), '420 m');
    });

    test('mostra km com uma casa decimal a partir de 1km', () {
      expect(DistanceService.formatDistance(1200), '1,2 km');
    });
  });

  group('DistanceService.estimateWalkMinutes', () {
    test('nunca retorna zero mesmo pra distancias minimas', () {
      expect(DistanceService.estimateWalkMinutes(1), greaterThanOrEqualTo(1));
    });

    test('cresce proporcionalmente a distancia', () {
      final near = DistanceService.estimateWalkMinutes(500);
      final far = DistanceService.estimateWalkMinutes(5000);
      expect(far, greaterThan(near));
    });
  });
}
