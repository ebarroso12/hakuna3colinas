import 'package:flutter_test/flutter_test.dart';
import 'package:legendario_connect/models/team.dart';
import 'package:legendario_connect/offline/transporte_local.dart';

/// Mensagem passando de celular a celular, sem rede nenhuma.
///
/// Toda a regra que decide se a malha funciona — ou se ela duplica
/// mensagem e derrete a bateria da equipe — mora em [RegrasDaMalha] e
/// [PacoteLocal], longe do rádio. É isso que permite prová-la sem dois
/// aparelhos na mão.
///
/// A ideia que destrava tudo: a mensagem viaja entre aparelhos **só para
/// ser vista**, e cada um sobe as suas quando tiver rede. Por isso não há
/// conflito com a RLS (`sender_id = auth.uid()`), que foi o que eu
/// apontei como bloqueio em `docs/comunicacao_sem_rede.md`.
void main() {
  PacoteLocal pacote({
    String clientId = 'c1',
    String topId = 'top-1',
    TeamKey? team = TeamKey.seguranca,
    String autorId = 'perfil-2',
    String autorNome = 'Edson Barroso',
    String corpo = 'queda na trilha, km 4',
    DateTime? criadaEm,
    int saltos = 0,
  }) => PacoteLocal(
    clientId: clientId,
    topId: topId,
    team: team,
    autorId: autorId,
    autorNome: autorNome,
    corpo: corpo,
    criadaEm: criadaEm ?? DateTime.utc(2026, 10, 12, 10),
    saltos: saltos,
  );

  group('o pacote sobrevive à ida e volta', () {
    test('tudo que importa volta igual', () {
      final original = pacote();
      final volta = PacoteLocal.deBytes(original.paraBytes())!;

      expect(volta.clientId, original.clientId);
      expect(volta.topId, original.topId);
      expect(volta.team, TeamKey.seguranca);
      expect(volta.autorId, original.autorId);
      expect(volta.autorNome, 'Edson Barroso');
      expect(volta.corpo, original.corpo);
      expect(volta.criadaEm, original.criadaEm);
    });

    test('o que chega por rádio NUNCA vem confirmado', () {
      // O ponto mais importante deste arquivo. Rádio local não tem
      // autenticação: qualquer aparelho ao alcance pode afirmar "fulano
      // disse X". No servidor isso é impossível, aqui não.
      //
      // Numa emergência, "o coordenador mandou descer" forjado move 200
      // pessoas. A tela TEM de distinguir, e isso começa aqui.
      final volta = PacoteLocal.deBytes(pacote().paraBytes())!;
      expect(volta.confirmada, isFalse);
    });

    test('team null é o chat geral, e sobrevive', () {
      final volta = PacoteLocal.deBytes(pacote(team: null).paraBytes())!;
      expect(volta.team, isNull);
    });

    test('as 9 equipes atravessam o fio', () {
      for (final equipe in TeamKeyUi.equipes) {
        final volta = PacoteLocal.deBytes(pacote(team: equipe).paraBytes())!;
        expect(volta.team, equipe, reason: equipe.label);
      }
    });

    test('acento e emoji não se perdem', () {
      const texto = 'Atenção: São três feridos na subida — ⚠️ pressa';
      final volta = PacoteLocal.deBytes(pacote(corpo: texto).paraBytes())!;
      expect(volta.corpo, texto);
    });
  });

  group('lixo no rádio não derruba a recepção', () {
    test('devolve null em vez de lançar, para tudo que é inválido', () {
      // Se qualquer um destes lançasse, o stream de recepção morreria e o
      // rádio ficaria mudo por causa de UM pacote ruim — justamente o que
      // não pode acontecer numa emergência.
      final lixos = <List<int>>[
        [],
        [0, 1, 2, 255],
        'nem json'.codeUnits,
        '{"json":"sem os campos"}'.codeUnits,
        '{"v":99,"client_id":"c1"}'.codeUnits,
        '[]'.codeUnits,
        '{"v":1,"client_id":"","top_id":"t","autor_id":"a","corpo":"x",'
                '"criada_em":"2026-10-12T10:00:00Z"}'
            .codeUnits,
        '{"v":1,"client_id":"c","top_id":"t","autor_id":"a","corpo":"",'
                '"criada_em":"2026-10-12T10:00:00Z"}'
            .codeUnits,
        '{"v":1,"client_id":"c","top_id":"t","autor_id":"a","corpo":"x",'
                '"criada_em":"data invalida"}'
            .codeUnits,
      ];
      for (final lixo in lixos) {
        expect(
          () => PacoteLocal.deBytes(lixo),
          returnsNormally,
          reason: 'não pode lançar',
        );
        expect(PacoteLocal.deBytes(lixo), isNull);
      }
    });

    test('versão desconhecida é descartada, não adivinhada', () {
      // Aparelho com app mais novo falando com um mais velho é o caso
      // NORMAL numa equipe. Descartar o que não se entende é melhor que
      // interpretar errado.
      final futuro = '{"v":2,"client_id":"c","top_id":"top-1",'
          '"autor_id":"a","corpo":"x","criada_em":"2026-10-12T10:00:00Z"}';
      expect(PacoteLocal.deBytes(futuro.codeUnits), isNull);
    });

    test('sem nome vira "Alguém do Top", nunca um uuid', () {
      final semNome = '{"v":1,"client_id":"c","top_id":"top-1",'
          '"autor_id":"uuid-feio-aqui","corpo":"x",'
          '"criada_em":"2026-10-12T10:00:00Z"}';
      final volta = PacoteLocal.deBytes(semNome.codeUnits)!;
      expect(volta.autorNome, 'Alguém do Top');
      expect(volta.autorNome, isNot(contains('uuid')));
    });
  });

  group('a malha não duplica e não derrete bateria', () {
    late RegrasDaMalha regras;
    final agora = DateTime.utc(2026, 10, 12, 12);

    setUp(() => regras = RegrasDaMalha(meuTopId: 'top-1'));

    test('a primeira vez aceita, a segunda não', () {
      final p = pacote(criadaEm: agora);
      expect(regras.decidir(p, agora: agora), Decisao.aceitar);
      // A malha entrega o mesmo pacote por vários caminhos. Sem isto, a
      // tela piscaria a mesma mensagem três vezes.
      expect(regras.decidir(p, agora: agora), Decisao.jaVisto);
      expect(regras.decidir(p, agora: agora), Decisao.jaVisto);
    });

    test('mensagem de outro Top não entra', () {
      final p = pacote(topId: 'top-2', criadaEm: agora);
      expect(regras.decidir(p, agora: agora), Decisao.deOutroTop);
    });

    test('velha demais não se repassa', () {
      final velha = pacote(criadaEm: agora.subtract(const Duration(hours: 7)));
      expect(regras.decidir(velha, agora: agora), Decisao.velhaDemais);

      final recente = pacote(
        clientId: 'c2',
        criadaEm: agora.subtract(const Duration(hours: 5)),
      );
      expect(regras.decidir(recente, agora: agora), Decisao.aceitar);
    });

    test('relógio adiantado não faz perder mensagem boa', () {
      // Relógio de celular erra. Um aparelho adiantado faria a mensagem
      // parecer vinda do futuro, e sem `abs()` ela seria descartada —
      // perdendo dado bom por causa de um relógio torto.
      final doFuturo = pacote(criadaEm: agora.add(const Duration(minutes: 20)));
      expect(regras.decidir(doFuturo, agora: agora), Decisao.aceitar);

      final futuroDemais = pacote(
        clientId: 'c9',
        criadaEm: agora.add(const Duration(hours: 9)),
      );
      expect(regras.decidir(futuroDemais, agora: agora), Decisao.velhaDemais);
    });

    test('saltos demais param o pacote', () {
      final rodado = pacote(saltos: 5, criadaEm: agora);
      expect(regras.decidir(rodado, agora: agora), Decisao.saltosDemais);
    });

    test('a propagação TERMINA — este é o teste que importa', () {
      // Sem freio, três aparelhos ao alcance mútuo repassam o mesmo
      // pacote para sempre e a bateria de todos acaba por causa de UMA
      // mensagem. Aqui a propagação é simulada até parar sozinha.
      final rede = [
        RegrasDaMalha(meuTopId: 'top-1'),
        RegrasDaMalha(meuTopId: 'top-1'),
        RegrasDaMalha(meuTopId: 'top-1'),
      ];
      var emTransito = [pacote(criadaEm: agora)];
      var entregas = 0;
      var rodadas = 0;

      while (emTransito.isNotEmpty && rodadas < 50) {
        rodadas++;
        final proxima = <PacoteLocal>[];
        for (final p in emTransito) {
          for (final aparelho in rede) {
            final d = aparelho.decidir(p, agora: agora);
            if (d == Decisao.aceitar) entregas++;
            if (aparelho.deveRepassar(d, p)) proxima.add(p.maisUmSalto());
          }
        }
        emTransito = proxima;
      }

      expect(emTransito, isEmpty, reason: 'a propagação tem de terminar');
      expect(rodadas, lessThan(50), reason: 'não pode rodar para sempre');
      // Cada aparelho entrega a mensagem ao usuário UMA vez.
      expect(entregas, 3);
    });

    test('a própria mensagem não volta como novidade', () {
      // Quem escreveu já tem a mensagem na tela e na fila. Aceitá-la de
      // volta pelo rádio a duplicaria.
      final minha = pacote(clientId: 'minha-1', criadaEm: agora);
      regras.jaConheco('minha-1');
      expect(regras.decidir(minha, agora: agora), Decisao.jaVisto);
    });

    test('pacote ilegível é decisão, não exceção', () {
      expect(regras.decidir(null), Decisao.invalido);
    });
  });

  group('a memória de ids não cresce sem fim', () {
    test('o limite poda os mais antigos', () {
      final regras = RegrasDaMalha(meuTopId: 'top-1', lembrarNoMaximo: 10);
      for (var i = 0; i < 25; i++) {
        regras.jaConheco('id-$i');
      }
      expect(regras.quantosVistos, 10);

      // O mais novo continua lembrado; o mais velho foi esquecido.
      final agora = DateTime.utc(2026, 10, 12, 12);
      expect(
        regras.decidir(pacote(clientId: 'id-24', criadaEm: agora), agora: agora),
        Decisao.jaVisto,
      );
      expect(
        regras.decidir(pacote(clientId: 'id-0', criadaEm: agora), agora: agora),
        Decisao.aceitar,
      );
    });
  });
}
