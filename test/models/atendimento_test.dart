import 'package:flutter_test/flutter_test.dart';
import 'package:legendario_connect/models/atendimento.dart';

Atendimento _a({
  int? sistolica,
  int? diastolica,
  int? glicemia,
  int? spo2,
  int? fc,
  double? temperatura,
  double? lat,
  double? lng,
  String procedimento = 'avaliado, sem queixas',
}) {
  return Atendimento(
    clientId: 'c1',
    topId: 't1',
    participantId: 'p1',
    openedBy: 'h1',
    procedimento: procedimento,
    openedAt: DateTime.utc(2026, 8, 28, 22, 32),
    systolicBp: sistolica,
    diastolicBp: diastolica,
    glicemiaMgDl: glicemia,
    spo2: spo2,
    heartRate: fc,
    temperatureC: temperatura,
    latitude: lat,
    longitude: lng,
  );
}

void main() {
  group('pressão arterial', () {
    test('monta "150 x 90" quando tem as duas', () {
      expect(_a(sistolica: 150, diastolica: 90).pressaoArterial, '150 x 90');
    });

    test('null com só uma das duas — meia PA não é PA', () {
      expect(_a(sistolica: 150).pressaoArterial, isNull);
      expect(_a(diastolica: 90).pressaoArterial, isNull);
      expect(_a().pressaoArterial, isNull);
    });
  });

  group('resumo de vitais para o histórico', () {
    test('junta só o que foi aferido', () {
      final r = _a(sistolica: 140, diastolica: 90, glicemia: 93).resumoVitais;
      expect(r, contains('PA 140 x 90'));
      expect(r, contains('DX 93'));
      expect(r, isNot(contains('SpO')));
    });

    test('null quando nada foi aferido', () {
      expect(_a().resumoVitais, isNull);
      expect(_a().temSinaisVitais, isFalse);
    });

    test('um único vital já conta', () {
      expect(_a(spo2: 97).temSinaisVitais, isTrue);
      expect(_a(spo2: 97).resumoVitais, 'SpO₂ 97%');
    });
  });

  group('localização', () {
    test('precisa das duas coordenadas', () {
      expect(_a(lat: -20.55, lng: -47.41).temLocalizacao, isTrue);
      expect(_a(lat: -20.55).temLocalizacao, isFalse);
      expect(_a().temLocalizacao, isFalse);
    });
  });

  group('serialização', () {
    test('procedimento vai no campo notes, que é o do banco', () {
      final mapa = _a(procedimento: 'cefaleia e náuseas').toMap();
      expect(mapa['notes'], 'cefaleia e náuseas');
      expect(mapa['client_id'], 'c1');
    });

    test('data vai em UTC — fuso do celular não pode mudar o horário', () {
      final mapa = _a().toMap();
      expect(mapa['opened_at'], endsWith('Z'));
    });

    test('fotos NÃO vão no mesmo payload: sobem por tabela própria', () {
      final comFoto = Atendimento(
        clientId: 'c1',
        topId: 't1',
        participantId: 'p1',
        openedBy: 'h1',
        procedimento: 'x',
        openedAt: DateTime.utc(2026, 1, 1),
        fotosLocais: const ['/fotos/a.jpg', '/fotos/b.jpg'],
      );
      expect(comFoto.toMap().containsKey('fotosLocais'), isFalse);
      expect(comFoto.toMap().containsKey('fotos'), isFalse);
    });

    test('ida e volta pelo banco preserva os vitais', () {
      final original = {
        'id': 'uuid-1',
        'client_id': 'c1',
        'top_id': 't1',
        'participant_id': 'p1',
        'opened_by': 'h1',
        'notes': 'PACIENTE COM QUEIXA DE CEFALEIA',
        'numero_registro': 7,
        'systolic_bp': 150,
        'diastolic_bp': 90,
        'glicemia_mg_dl': 93,
        'spo2': 97,
        'latitude': -20.552884,
        'longitude': -47.419769,
        'opened_at': '2026-08-29T13:51:00Z',
      };
      final a = Atendimento.fromMap(original);
      expect(a.numeroRegistro, 7);
      expect(a.pressaoArterial, '150 x 90');
      expect(a.procedimento, 'PACIENTE COM QUEIXA DE CEFALEIA');
      expect(a.temLocalizacao, isTrue);
    });

    test('registro antigo sem client_id cai para o id do servidor', () {
      final a = Atendimento.fromMap({
        'id': 'uuid-antigo',
        'top_id': 't1',
        'participant_id': 'p1',
        'opened_by': 'h1',
        'notes': 'x',
        'opened_at': '2026-01-01T00:00:00Z',
      });
      expect(a.clientId, 'uuid-antigo');
    });
  });

  group('alertas de sinais vitais', () {
    // Destaque visual, não decisão clínica: marcam o número que merece um
    // segundo olhar, nunca bloqueiam o registro.

    test('PA: hipertensão e hipotensão acendem; normal não', () {
      expect(AlertaVital.pressaoAlterada(150, 95), isTrue);
      expect(AlertaVital.pressaoAlterada(85, 55), isTrue);
      expect(AlertaVital.pressaoAlterada(120, 80), isFalse);
    });

    test('PA incompleta não acende — evita alarme falso', () {
      expect(AlertaVital.pressaoAlterada(150, null), isFalse);
      expect(AlertaVital.pressaoAlterada(null, null), isFalse);
    });

    test('glicemia: hipo e hiper acendem', () {
      expect(AlertaVital.glicemiaAlterada(60), isTrue);
      expect(AlertaVital.glicemiaAlterada(250), isTrue);
      expect(AlertaVital.glicemiaAlterada(93), isFalse);
    });

    test('SpO2 abaixo de 94 acende', () {
      expect(AlertaVital.spo2Alterado(90), isTrue);
      expect(AlertaVital.spo2Alterado(94), isFalse);
      expect(AlertaVital.spo2Alterado(98), isFalse);
    });

    test('FC fora de 50-120 acende', () {
      expect(AlertaVital.frequenciaAlterada(45), isTrue);
      expect(AlertaVital.frequenciaAlterada(130), isTrue);
      expect(AlertaVital.frequenciaAlterada(72), isFalse);
    });

    test('temperatura: hipotermia e febre acendem', () {
      expect(AlertaVital.temperaturaAlterada(34.5), isTrue);
      expect(AlertaVital.temperaturaAlterada(38.2), isTrue);
      expect(AlertaVital.temperaturaAlterada(36.5), isFalse);
    });

    test('campo vazio nunca acende', () {
      expect(AlertaVital.glicemiaAlterada(null), isFalse);
      expect(AlertaVital.spo2Alterado(null), isFalse);
      expect(AlertaVital.frequenciaAlterada(null), isFalse);
      expect(AlertaVital.temperaturaAlterada(null), isFalse);
    });
  });
}
