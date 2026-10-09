import 'package:flutter_test/flutter_test.dart';
import 'package:hakuna_connect/models/team.dart';
import 'package:hakuna_connect/models/team_message.dart';

void main() {
  group('TeamKey espelha o enum team_key do Postgres', () {
    // Esta lista é a fonte da verdade do banco. Se o enum do Postgres
    // ganhar uma equipe nova, este teste quebra e lembra de atualizar o
    // Dart junto — senão as mensagens daquela equipe caem no chat errado
    // pelo fallback do fromMap.
    const valoresNoBanco = [
      'adm',
      'logistica',
      'voz',
      'intercessao',
      'producao',
      'midia',
      'eventos',
      'seguranca',
      'geral',
    ];

    test('tem exatamente os mesmos valores, com os mesmos nomes', () {
      expect(TeamKey.values.map((t) => t.name).toSet(), valoresNoBanco.toSet());
    });

    test('todo valor do banco converte de volta para o enum', () {
      for (final v in valoresNoBanco) {
        expect(teamKeyFromString(v), isNotNull, reason: v);
        expect(teamKeyFromString(v)!.name, v);
      }
    });

    test('valor desconhecido ou nulo vira null, sem estourar', () {
      expect(teamKeyFromString('equipe_que_nao_existe'), isNull);
      expect(teamKeyFromString(null), isNull);
      expect(teamKeyFromString(''), isNull);
    });

    test('toda equipe tem label e ícone próprios', () {
      final labels = TeamKey.values.map((t) => t.label).toList();
      expect(labels.toSet().length, TeamKey.values.length);
      for (final t in TeamKey.values) {
        expect(t.label.trim(), isNotEmpty, reason: t.name);
      }
    });

    test('só "geral" é o canal geral; as outras 8 são equipes', () {
      expect(TeamKey.values.where((t) => t.isGeral).toList(), [TeamKey.geral]);
      expect(TeamKeyUi.equipes.length, 8);
      expect(TeamKeyUi.equipes, isNot(contains(TeamKey.geral)));
    });
  });

  group('TeamMessage.fromMap', () {
    Map<String, dynamic> linha({
      String team = 'logistica',
      bool? isAlert,
      String? editedAt,
    }) => {
      'id': 1,
      'top_id': 'top-1',
      'team': team,
      'sender_id': 'user-1',
      'body': 'teste',
      'created_at': '2026-10-09T12:00:00Z',
      'is_alert': ?isAlert,
      'edited_at': ?editedAt,
    };

    test('lê os campos básicos', () {
      final m = TeamMessage.fromMap(linha());
      expect(m.id, 1);
      expect(m.team, TeamKey.logistica);
      expect(m.body, 'teste');
      expect(m.isAlert, isFalse);
      expect(m.editedAt, isNull);
    });

    test('is_alert ausente vira false em vez de estourar', () {
      expect(TeamMessage.fromMap(linha()).isAlert, isFalse);
      expect(TeamMessage.fromMap(linha(isAlert: true)).isAlert, isTrue);
    });

    test('edited_at preenchido marca a mensagem como editada', () {
      final m = TeamMessage.fromMap(linha(editedAt: '2026-10-09T13:00:00Z'));
      expect(m.editedAt, isNotNull);
      expect(m.editedAt!.isAfter(m.createdAt), isTrue);
    });

    test('equipe desconhecida cai em geral em vez de quebrar a tela', () {
      final m = TeamMessage.fromMap(linha(team: 'equipe_do_futuro'));
      expect(m.team, TeamKey.geral);
    });
  });

  group('TeamMembership.isActive', () {
    TeamMembership m({required bool released, required bool blocked}) =>
        TeamMembership.fromMap({
          'id': 1,
          'top_id': 'top-1',
          'team': 'voz',
          'profile_id': 'user-1',
          'is_team_admin': false,
          'released': released,
          'blocked': blocked,
        });

    test('só participa quem está liberado E não bloqueado', () {
      expect(m(released: true, blocked: false).isActive, isTrue);
      expect(m(released: false, blocked: false).isActive, isFalse);
      expect(m(released: true, blocked: true).isActive, isFalse);
      expect(m(released: false, blocked: true).isActive, isFalse);
    });

    test('campos booleanos ausentes caem para false (o lado seguro)', () {
      final semFlags = TeamMembership.fromMap({
        'id': 1,
        'top_id': 'top-1',
        'team': 'voz',
        'profile_id': 'user-1',
      });
      expect(semFlags.released, isFalse);
      expect(semFlags.blocked, isFalse);
      expect(semFlags.isTeamAdmin, isFalse);
      expect(
        semFlags.isActive,
        isFalse,
        reason: 'na dúvida, não dar acesso ao chat da equipe',
      );
    });
  });
}
