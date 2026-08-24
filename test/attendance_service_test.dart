import 'package:flutter_test/flutter_test.dart';
import 'package:hakuna_connect/models/attendance.dart';
import 'package:hakuna_connect/services/attendance_service.dart';

void main() {
  group('AttendanceService.primaryAction', () {
    test('aberto e reconhecido levam a ACEITAR -> atribuido', () {
      expect(AttendanceService.primaryAction(AttendanceStatus.aberto), (
        AttendanceStatus.atribuido,
        'ACEITAR',
      ));
      expect(AttendanceService.primaryAction(AttendanceStatus.reconhecido), (
        AttendanceStatus.atribuido,
        'ACEITAR',
      ));
    });

    test('segue a sequencia correta ate encerrado', () {
      expect(AttendanceService.primaryAction(AttendanceStatus.atribuido), (
        AttendanceStatus.aCaminho,
        'A CAMINHO',
      ));
      expect(AttendanceService.primaryAction(AttendanceStatus.aCaminho), (
        AttendanceStatus.noLocal,
        'CHEGUEI',
      ));
      expect(AttendanceService.primaryAction(AttendanceStatus.noLocal), (
        AttendanceStatus.emAndamento,
        'INICIAR ATENDIMENTO',
      ));
      expect(AttendanceService.primaryAction(AttendanceStatus.emAndamento), (
        AttendanceStatus.encerrado,
        'FINALIZAR',
      ));
    });

    test('escalado ainda permite finalizar', () {
      expect(AttendanceService.primaryAction(AttendanceStatus.escalado), (
        AttendanceStatus.encerrado,
        'FINALIZAR',
      ));
    });

    test('estados terminais nao tem proxima acao', () {
      expect(
        AttendanceService.primaryAction(AttendanceStatus.encerrado),
        isNull,
      );
      expect(
        AttendanceService.primaryAction(AttendanceStatus.cancelado),
        isNull,
      );
    });
  });

  group('AttendanceService.timestampColumnFor', () {
    test('mapeia cada transicao pra sua coluna de timestamp', () {
      expect(
        AttendanceService.timestampColumnFor(AttendanceStatus.reconhecido),
        'acknowledged_at',
      );
      expect(
        AttendanceService.timestampColumnFor(AttendanceStatus.atribuido),
        'assigned_at',
      );
      expect(
        AttendanceService.timestampColumnFor(AttendanceStatus.aCaminho),
        'en_route_at',
      );
      expect(
        AttendanceService.timestampColumnFor(AttendanceStatus.noLocal),
        'on_scene_at',
      );
      expect(
        AttendanceService.timestampColumnFor(AttendanceStatus.encerrado),
        'closed_at',
      );
      expect(
        AttendanceService.timestampColumnFor(AttendanceStatus.cancelado),
        'closed_at',
      );
    });

    test('estados sem timestamp dedicado retornam null', () {
      expect(
        AttendanceService.timestampColumnFor(AttendanceStatus.aberto),
        isNull,
      );
      expect(
        AttendanceService.timestampColumnFor(AttendanceStatus.emAndamento),
        isNull,
      );
    });
  });

  group('attendanceStatusToString / attendanceStatusFromString', () {
    test('faz round-trip pros valores com underscore', () {
      for (final status in AttendanceStatus.values) {
        final asString = attendanceStatusToString(status);
        expect(attendanceStatusFromString(asString), status);
      }
    });

    test('mapeia os nomes exatos usados no enum do Postgres', () {
      expect(attendanceStatusToString(AttendanceStatus.aCaminho), 'a_caminho');
      expect(attendanceStatusToString(AttendanceStatus.noLocal), 'no_local');
      expect(
        attendanceStatusToString(AttendanceStatus.emAndamento),
        'em_andamento',
      );
    });
  });
}
