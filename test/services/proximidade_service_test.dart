import 'package:flutter_test/flutter_test.dart';
import 'package:legendario_connect/models/hakuna_position.dart';
import 'package:legendario_connect/services/proximidade_service.dart';

/// A pergunta "quem está mais perto?" não tinha resposta no app: havia GPS
/// dos Hakunas, havia alarme com coordenada, e nada cruzava os dois.
///
/// Os dois erros fáceis de cometer aqui, e que estes testes travam:
///
/// 1. Usar a posição mais PERTO da trilha de alguém em vez da mais
///    RECENTE. Diria que o Hakuna está a 50 m porque passou ali de manhã.
/// 2. Aceitar posição velha. Um ponto de três horas atrás diz onde a
///    pessoa esteve; mandar alguém com base nele é pior que não ter nada,
///    porque o número parece confiável.
void main() {
  HakunaPosition pos(
    String id,
    double lat,
    double lon, {
    Duration atras = Duration.zero,
  }) => HakunaPosition(
    profileId: id,
    topId: 'top-1',
    latitude: lat,
    longitude: lon,
    recordedAt: DateTime.now().toUtc().subtract(atras),
  );

  // Ponto de referência: o alarme.
  const alvoLat = -20.5000;
  const alvoLon = -47.4000;

  test('ordena do mais perto ao mais longe', () {
    final r = ProximidadeService.maisProximos(
      latitude: alvoLat,
      longitude: alvoLon,
      posicoes: [
        pos('longe', -20.5300, -47.4000),
        pos('perto', -20.5010, -47.4000),
        pos('medio', -20.5100, -47.4000),
      ],
    );
    expect(r.map((e) => e.profileId).toList(), ['perto', 'medio', 'longe']);
  });

  test('usa a ÚLTIMA posição de cada Hakuna, não a mais próxima', () {
    // Passou colado no ponto às 8h e está longe agora. A resposta certa é
    // "longe" — a trilha inteira vem na lista, e pegar o ponto mais perto
    // dela mandaria o Hakuna errado.
    final r = ProximidadeService.maisProximos(
      latitude: alvoLat,
      longitude: alvoLon,
      posicoes: [
        pos('a', -20.5001, -47.4000, atras: const Duration(minutes: 90)),
        pos('a', -20.5400, -47.4000, atras: const Duration(minutes: 2)),
        pos('b', -20.5100, -47.4000, atras: const Duration(minutes: 2)),
      ],
    );
    expect(r.first.profileId, 'b');
    expect(r.length, 2);
    // ~4,4 km, não ~11 m.
    expect(r.last.metros, greaterThan(3000));
  });

  test('posição velha é descartada, não mostrada com ressalva', () {
    final r = ProximidadeService.maisProximos(
      latitude: alvoLat,
      longitude: alvoLon,
      posicoes: [pos('antigo', -20.5001, -47.4000, atras: const Duration(hours: 3))],
    );
    expect(r, isEmpty);
  });

  test('o limite de idade é configurável', () {
    final posicoes = [
      pos('x', -20.5001, -47.4000, atras: const Duration(minutes: 30)),
    ];
    expect(
      ProximidadeService.maisProximos(
        latitude: alvoLat,
        longitude: alvoLon,
        posicoes: posicoes,
        idadeMaxima: const Duration(minutes: 10),
      ),
      isEmpty,
    );
    expect(
      ProximidadeService.maisProximos(
        latitude: alvoLat,
        longitude: alvoLon,
        posicoes: posicoes,
        idadeMaxima: const Duration(hours: 1),
      ).length,
      1,
    );
  });

  test('lista vazia devolve lista vazia, não estoura', () {
    expect(
      ProximidadeService.maisProximos(
        latitude: alvoLat,
        longitude: alvoLon,
        posicoes: const [],
      ),
      isEmpty,
    );
  });

  group('formatação', () {
    test('abaixo de 1 km mostra metros inteiros', () {
      final r = ProximidadeService.maisProximos(
        latitude: alvoLat,
        longitude: alvoLon,
        posicoes: [pos('a', -20.5010, -47.4000)],
      );
      expect(r.single.distanciaFormatada, endsWith(' m'));
      expect(r.single.distanciaFormatada, isNot(contains('.')));
    });

    test('acima de 1 km mostra km com vírgula decimal', () {
      final r = ProximidadeService.maisProximos(
        latitude: alvoLat,
        longitude: alvoLon,
        posicoes: [pos('a', -20.5400, -47.4000)],
      );
      // Vírgula, não ponto: o app é em português e "4.4 km" lido rápido
      // vira "44 km".
      expect(r.single.distanciaFormatada, contains(','));
      expect(r.single.distanciaFormatada, endsWith(' km'));
    });

    test('idade recente diz "agora"', () {
      final r = ProximidadeService.maisProximos(
        latitude: alvoLat,
        longitude: alvoLon,
        posicoes: [pos('a', -20.5010, -47.4000)],
      );
      expect(r.single.idadeFormatada, 'agora');
    });

    test('idade em minutos e em horas', () {
      final r = ProximidadeService.maisProximos(
        latitude: alvoLat,
        longitude: alvoLon,
        posicoes: [
          pos('m', -20.5010, -47.4000, atras: const Duration(minutes: 25)),
          pos('h', -20.5011, -47.4000, atras: const Duration(minutes: 70)),
        ],
      );
      final porId = {for (final e in r) e.profileId: e.idadeFormatada};
      expect(porId['m'], '25 min');
      expect(porId['h'], '1 h 10');
    });
  });
}
