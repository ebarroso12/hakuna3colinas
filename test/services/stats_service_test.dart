import 'package:flutter_test/flutter_test.dart';
import 'package:hakuna_connect/models/hakuna_position.dart';
import 'package:hakuna_connect/services/stats_service.dart';

final _inicio = DateTime.utc(2026, 1, 1, 8);

HakunaPosition _pos(double lat, double lng, Duration offset) {
  return HakunaPosition(
    profileId: 'h1',
    topId: 't1',
    latitude: lat,
    longitude: lng,
    recordedAt: _inicio.add(offset),
  );
}

/// Trilha em linha reta no meridiano 0, percorrida em [duracao].
/// Um grau de latitude ≈ 111.320 m, então [metros] vira um delta de latitude.
List<HakunaPosition> _trilha({
  required double metros,
  required Duration duracao,
}) {
  final deltaLat = metros / 111320.0;
  return [
    _pos(0, 0, Duration.zero),
    _pos(deltaLat, 0, duracao),
  ];
}

void main() {
  group('StatsService.compute — casos degenerados', () {
    test('lista vazia devolve TopStats.zero', () {
      final stats = StatsService.compute(const []);
      expect(stats.distanceMeters, 0);
      expect(stats.avgSpeedKmh, 0);
      expect(stats.calories, 0);
      expect(stats.duration, Duration.zero);
    });

    test('um único ponto devolve TopStats.zero (não dá pra medir trajeto)', () {
      final stats = StatsService.compute([_pos(0, 0, Duration.zero)]);
      expect(stats.distanceMeters, 0);
      expect(stats.duration, Duration.zero);
    });

    test('dois pontos no mesmo lugar: distância zero, sem dividir por zero', () {
      final stats = StatsService.compute([
        _pos(0, 0, Duration.zero),
        _pos(0, 0, const Duration(hours: 1)),
      ]);
      expect(stats.distanceMeters, closeTo(0, 0.01));
      expect(stats.avgSpeedKmh, 0);
      expect(stats.calories, 0, reason: 'velocidade 0 cai no ramo MET <= 0');
      expect(stats.duration, const Duration(hours: 1));
    });

    test('dois pontos no mesmo instante não estouram com divisão por zero', () {
      final stats = StatsService.compute([
        _pos(0, 0, Duration.zero),
        _pos(0.001, 0, Duration.zero),
      ]);
      expect(stats.distanceMeters, greaterThan(0));
      expect(stats.avgSpeedKmh, 0, reason: 'hours == 0 não pode virar Infinity');
      expect(stats.calories, 0);
      expect(stats.avgSpeedKmh.isFinite, isTrue);
      expect(stats.calories.isFinite, isTrue);
    });
  });

  group('StatsService.compute — distância e velocidade', () {
    test('soma a distância entre pontos consecutivos (Haversine)', () {
      final stats = StatsService.compute(
        _trilha(metros: 1000, duracao: const Duration(hours: 1)),
      );
      expect(stats.distanceMeters, closeTo(1000, 5));
      expect(stats.distanceKm, closeTo(1.0, 0.005));
    });

    test('acumula ao longo de vários trechos, não só do primeiro ao último', () {
      final deltaLat = 1000 / 111320.0;
      final stats = StatsService.compute([
        _pos(0, 0, Duration.zero),
        _pos(deltaLat, 0, const Duration(minutes: 20)),
        _pos(deltaLat * 2, 0, const Duration(minutes: 40)),
        _pos(deltaLat * 3, 0, const Duration(minutes: 60)),
      ]);
      expect(stats.distanceMeters, closeTo(3000, 15));
    });

    test('ida e volta conta o caminho percorrido, não o deslocamento final', () {
      final deltaLat = 1000 / 111320.0;
      final stats = StatsService.compute([
        _pos(0, 0, Duration.zero),
        _pos(deltaLat, 0, const Duration(minutes: 30)),
        _pos(0, 0, const Duration(minutes: 60)),
      ]);
      expect(
        stats.distanceMeters,
        closeTo(2000, 10),
        reason: 'voltou ao ponto inicial mas caminhou 2 km',
      );
    });

    test('velocidade média usa o intervalo entre o primeiro e o último ponto', () {
      final stats = StatsService.compute(
        _trilha(metros: 8000, duracao: const Duration(hours: 2)),
      );
      expect(stats.avgSpeedKmh, closeTo(4.0, 0.05));
      expect(stats.duration, const Duration(hours: 2));
    });

    test('paradas longas derrubam a velocidade média (é média geral, não de movimento)', () {
      final deltaLat = 4000 / 111320.0;
      final stats = StatsService.compute([
        _pos(0, 0, Duration.zero),
        // andou 4 km na primeira hora...
        _pos(deltaLat, 0, const Duration(hours: 1)),
        // ...e ficou parado por mais 3 horas
        _pos(deltaLat, 0, const Duration(hours: 4)),
      ]);
      expect(stats.distanceMeters, closeTo(4000, 20));
      expect(
        stats.avgSpeedKmh,
        closeTo(1.0, 0.05),
        reason: '4 km / 4 h, e não os 4 km/h do trecho em movimento',
      );
    });
  });

  group('StatsService.compute — faixas de MET no gasto calórico', () {
    /// MET efetivamente aplicado = calorias / (peso * horas).
    double metAplicado(double velocidadeKmh, {double peso = 80}) {
      const duracao = Duration(hours: 2);
      final stats = StatsService.compute(
        _trilha(metros: velocidadeKmh * 2 * 1000, duracao: duracao),
        weightKg: peso,
      );
      return stats.calories / (peso * duracao.inSeconds / 3600);
    }

    test('até 3 km/h usa MET 3.5 (caminhada leve)', () {
      expect(metAplicado(2), closeTo(3.5, 0.001));
    });

    test('de 3 a 5 km/h usa MET 5.0 (trilha moderada)', () {
      expect(metAplicado(4), closeTo(5.0, 0.001));
    });

    test('de 5 a 7 km/h usa MET 7.0 (ritmo forte / subida)', () {
      expect(metAplicado(6), closeTo(7.0, 0.001));
    });

    test('acima de 7 km/h usa MET 8.5 (trilha rápida)', () {
      expect(metAplicado(9), closeTo(8.5, 0.001));
    });

    test('calorias = MET x peso x horas', () {
      final stats = StatsService.compute(
        _trilha(metros: 8000, duracao: const Duration(hours: 2)),
        weightKg: 80,
      );
      // 4 km/h -> MET 5.0 ; 5.0 * 80 kg * 2 h = 800 kcal
      expect(stats.calories, closeTo(800, 5));
    });

    test('calorias escalam com o peso informado', () {
      final leve = StatsService.compute(
        _trilha(metros: 8000, duracao: const Duration(hours: 2)),
        weightKg: 60,
      );
      final pesado = StatsService.compute(
        _trilha(metros: 8000, duracao: const Duration(hours: 2)),
        weightKg: 120,
      );
      expect(pesado.calories, closeTo(leve.calories * 2, 1));
    });
  });

  group('StatsService.compute — peso padrão e flag de estimativa', () {
    test('sem peso informado usa 70 kg e marca caloriesIsEstimate', () {
      final semPeso = StatsService.compute(
        _trilha(metros: 8000, duracao: const Duration(hours: 2)),
      );
      final com70 = StatsService.compute(
        _trilha(metros: 8000, duracao: const Duration(hours: 2)),
        weightKg: 70,
      );
      expect(semPeso.calories, closeTo(com70.calories, 0.001));
      expect(semPeso.caloriesIsEstimate, isTrue);
    });

    test('com peso informado NÃO marca caloriesIsEstimate', () {
      final stats = StatsService.compute(
        _trilha(metros: 8000, duracao: const Duration(hours: 2)),
        weightKg: 82.5,
      );
      expect(stats.caloriesIsEstimate, isFalse);
    });
  });

  group('StatsService.compute — contrato implícito de ordenação', () {
    test(
      'FRAGILIDADE: compute assume pontos em ordem crescente de recorded_at. '
      'Em ordem decrescente a distância continua certa, mas duração fica '
      'negativa e velocidade/calorias zeram silenciosamente',
      () {
        final crescente = _trilha(
          metros: 8000,
          duracao: const Duration(hours: 2),
        );
        final decrescente = crescente.reversed.toList();

        final ok = StatsService.compute(crescente, weightKg: 80);
        final invertido = StatsService.compute(decrescente, weightKg: 80);

        expect(invertido.distanceMeters, closeTo(ok.distanceMeters, 0.01));
        expect(
          invertido.duration.isNegative,
          isTrue,
          reason: 'duração negativa nunca deveria chegar à UI',
        );
        expect(invertido.avgSpeedKmh, 0);
        expect(
          invertido.calories,
          0,
          reason:
              'relatório mostraria 8 km percorridos com 0 kcal — compute '
              'deveria ordenar internamente ou rejeitar a entrada',
        );
      },
    );
  });
}
