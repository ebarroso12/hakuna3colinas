import 'package:flutter_test/flutter_test.dart';
import 'package:legendario_connect/models/acesso_as_equipes.dart';
import 'package:legendario_connect/models/team.dart';
import 'package:legendario_connect/models/team_message.dart';

/// Quem vê quais das 9 equipes.
///
/// Dois defeitos que este arquivo existe para travar, os dois achados em
/// 11/10/2026 porque o dono abriu o app e não encontrou as equipes:
///
/// 1. A tela mostrava só as equipes em que a pessoa já era membro
///    liberado. Com `top_team_members` vazia — o estado de todo Top
///    recém-montado — ninguém via equipe nenhuma.
/// 2. **O admin não via nenhuma**, mesmo a RLS liberando todas para ele.
///    A tela fechava porta que o banco deixa aberta. Decisão do dono:
///    "como administrador devo ver e ter acesso a todas as equipes".
///
/// Esta classe NÃO é a fronteira de segurança — a RLS é. O que se testa
/// aqui é a tela não mentir em nenhuma direção: não oferecer o que o
/// banco recusa, nem esconder o que o banco permite.
void main() {
  TeamMembership vinculo(
    TeamKey team, {
    TeamRole papel = TeamRole.membro,
    bool released = true,
    bool blocked = false,
  }) => TeamMembership(
    id: 1,
    topId: 'top-1',
    team: team,
    profileId: 'perfil-1',
    teamRole: papel,
    released: released,
    blocked: blocked,
  );

  group('admin vê e acessa TODAS as equipes', () {
    final admin = AcessoAsEquipes(vinculos: const [], souAdmin: true);

    test('as 9 abrem, sem vínculo nenhum', () {
      expect(TeamKeyUi.equipes.length, 9);
      for (final equipe in TeamKeyUi.equipes) {
        expect(
          admin.aberta(equipe),
          isTrue,
          reason: '${equipe.label} tem de abrir para o admin',
        );
        expect(admin.estadoDe(equipe), EstadoDaEquipe.acessoDeAdmin);
      }
      expect(admin.quantasAbertas, 9);
    });

    test('pode alertar em todas as 9', () {
      // O "enviar como alerta" destaca a mensagem para a equipe inteira.
      // `team_message.dart` documenta que a RLS aceita admin da equipe
      // **ou admin geral**; garantido em
      // `supabase/admin_ve_todas_as_equipes.sql`.
      for (final equipe in TeamKeyUi.equipes) {
        expect(admin.podeAlertarEm(equipe), isTrue, reason: equipe.label);
      }
    });

    test('equipe aberta não tem explicação a dar — tem a abrir', () {
      for (final equipe in TeamKeyUi.equipes) {
        expect(admin.explicacaoDe(equipe), isEmpty);
      }
    });

    test('admin master também, mesmo com role diferente', () {
      // `souAdmin` já chega resolvido da tela como
      // `role == admin || isMasterAdmin` — este teste trava o contrato de
      // que basta a flag, sem segunda regra escondida aqui dentro.
      const master = AcessoAsEquipes(vinculos: [], souAdmin: true);
      expect(master.quantasAbertas, 9);
    });
  });

  group('o vínculo manda sobre o papel de admin', () {
    test('admin BLOQUEADO numa equipe aparece bloqueado, não como admin', () {
      // A ordem importa. Bloqueio é decisão explícita de alguém sobre
      // aquela pessoa naquela equipe; tratá-lo como ruído seria a tela
      // desfazendo pela leitura o que um admin fez pela escrita.
      final acesso = AcessoAsEquipes(
        vinculos: [vinculo(TeamKey.midia, blocked: true)],
        souAdmin: true,
      );
      expect(acesso.estadoDe(TeamKey.midia), EstadoDaEquipe.bloqueado);
      expect(acesso.aberta(TeamKey.midia), isFalse);
      expect(acesso.podeAlertarEm(TeamKey.midia), isFalse);
      // As outras 8 seguem abertas pelo papel.
      expect(acesso.quantasAbertas, 8);
    });

    test('admin NÃO LIBERADO numa equipe fica aguardando', () {
      final acesso = AcessoAsEquipes(
        vinculos: [vinculo(TeamKey.voz, released: false)],
        souAdmin: true,
      );
      expect(acesso.estadoDe(TeamKey.voz), EstadoDaEquipe.aguardandoLiberacao);
      expect(acesso.aberta(TeamKey.voz), isFalse);
    });

    test('admin que é membro comum vê os dois no subtítulo', () {
      final acesso = AcessoAsEquipes(
        vinculos: [vinculo(TeamKey.eventos)],
        souAdmin: true,
      );
      expect(acesso.descricaoDe(TeamKey.eventos), 'Membro · acesso de admin');
      // E pode alertar, que é o poder que o texto explica.
      expect(acesso.podeAlertarEm(TeamKey.eventos), isTrue);
    });

    test('coordenador não repete "acesso de admin" à toa', () {
      final acesso = AcessoAsEquipes(
        vinculos: [vinculo(TeamKey.adm, papel: TeamRole.coordenador)],
        souAdmin: true,
      );
      expect(acesso.descricaoDe(TeamKey.adm), 'Coordenador');
    });
  });

  group('quem não é admin', () {
    test('sem vínculo, as 9 ficam fechadas e cada uma DIZ por quê', () {
      const fora = AcessoAsEquipes(vinculos: [], souAdmin: false);
      expect(fora.quantasAbertas, 0);
      for (final equipe in TeamKeyUi.equipes) {
        expect(fora.estadoDe(equipe), EstadoDaEquipe.fora);
        expect(fora.descricaoDe(equipe), 'Você não está nesta equipe');
        // O texto nomeia QUEM resolve. "Sem acesso" sozinho manda o
        // usuário procurar o problema no app.
        expect(fora.explicacaoDe(equipe), contains('admin do Top'));
        expect(fora.explicacaoDe(equipe), contains(equipe.label));
      }
    });

    test('incluído mas não liberado é diferente de fora — e é o pior', () {
      // `is_team_member` exige `released = true`. Quem cai aqui não tem
      // chat nem anotações E não tem como saber o que pedir, se a tela
      // não distinguir os dois estados.
      final esperando = AcessoAsEquipes(
        vinculos: [vinculo(TeamKey.seguranca, released: false)],
        souAdmin: false,
      );
      expect(
        esperando.estadoDe(TeamKey.seguranca),
        EstadoDaEquipe.aguardandoLiberacao,
      );
      expect(esperando.descricaoDe(TeamKey.seguranca), contains('LIBERADO'));
      expect(
        esperando.explicacaoDe(TeamKey.seguranca),
        contains('Equipes do Top'),
      );
      expect(
        esperando.descricaoDe(TeamKey.seguranca),
        isNot(const AcessoAsEquipes(
          vinculos: [],
          souAdmin: false,
        ).descricaoDe(TeamKey.seguranca)),
        reason: 'os dois estados não podem dizer a mesma coisa',
      );
    });

    test('membro comum abre a sua equipe e não pode alertar', () {
      final membro = AcessoAsEquipes(
        vinculos: [vinculo(TeamKey.logistica)],
        souAdmin: false,
      );
      expect(membro.aberta(TeamKey.logistica), isTrue);
      expect(membro.podeAlertarEm(TeamKey.logistica), isFalse);
      expect(membro.quantasAbertas, 1);
    });

    test('coordenador e subcoordenador podem alertar na equipe deles', () {
      for (final papel in [TeamRole.coordenador, TeamRole.subcoordenador]) {
        final acesso = AcessoAsEquipes(
          vinculos: [vinculo(TeamKey.producao, papel: papel)],
          souAdmin: false,
        );
        expect(
          acesso.podeAlertarEm(TeamKey.producao),
          isTrue,
          reason: papel.label,
        );
        // Mas só na dele.
        expect(acesso.podeAlertarEm(TeamKey.midia), isFalse);
      }
    });

    test('bloqueado não alerta nem lê, mesmo sendo coordenador', () {
      final acesso = AcessoAsEquipes(
        vinculos: [
          vinculo(TeamKey.voz, papel: TeamRole.coordenador, blocked: true),
        ],
        souAdmin: false,
      );
      expect(acesso.aberta(TeamKey.voz), isFalse);
      expect(acesso.podeAlertarEm(TeamKey.voz), isFalse);
    });
  });

  group('`geral` não é equipe', () {
    test('não entra na conta das 9 nem na lista', () {
      expect(TeamKeyUi.equipes, isNot(contains(TeamKey.geral)));
      // O canal geral é aberto a todo aprovado por outra regra, na RLS, e
      // a tela o mostra sempre — sem passar por aqui.
      const ninguem = AcessoAsEquipes(vinculos: [], souAdmin: false);
      expect(ninguem.quantasAbertas, lessThanOrEqualTo(9));
    });
  });
}
