import 'package:flutter_test/flutter_test.dart';
import 'package:legendario_connect/models/top_alert.dart';
import 'package:legendario_connect/offline/local_db.dart';
import 'package:legendario_connect/offline/outbox.dart';
import 'package:legendario_connect/offline/sync_service.dart';
import 'package:legendario_connect/offline/transporte_local.dart';
import 'package:legendario_connect/services/alarme_service.dart';
import 'package:legendario_connect/services/supabase_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// O buraco que estes testes fecham foi achado em teste de campo real, em
/// 12/10/2026, com dois Android na mão.
///
/// A malha por rádio funcionava — mensagem de chat ia de um aparelho ao
/// outro em modo avião, comprovado na tela. Mas o **alarme não usava a
/// malha**: `AlarmeService.disparar` só enfileirava, e `espalhar` era
/// chamado unicamente pelo chat. Em modo avião, apertar EMERGÊNCIA
/// guardava o alarme no próprio celular e **não avisava ninguém** — nem
/// quem estava a dois metros.
///
/// Ou seja: a função mais crítica do app era a única que não usava o
/// caminho sem rede que o app já tinha pronto e funcionando.
///
/// Estes testes provam a regra, não o rádio. O rádio só se prova com dois
/// aparelhos — ver o relatório da v1.0.43.
void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    AlarmeService.anunciarLigado = false;
  });

  setUp(() async {
    LocalDb.overridePathForTests = inMemoryDatabasePath;
    await LocalDb.instance.close();
    SyncService.instance.resetForTests();
    SupabaseService.idDeUsuarioParaTestes = 'hakuna-1';
    AlarmeService.instance.limparParaTestes();
  });

  tearDown(() async {
    SupabaseService.idDeUsuarioParaTestes = null;
    AlarmeService.instance.espalharPeloRadio = null;
    await LocalDb.instance.close();
  });

  TopAlert doRadio({
    required String clientId,
    String de = 'hakuna-2',
    String? nome,
    double? lat,
    double? lng,
    Duration atras = Duration.zero,
  }) => TopAlert(
    clientId: clientId,
    confirmado: false,
    topId: 'top-1',
    senderId: de,
    senderName: nome,
    message: 'EMERGÊNCIA',
    latitude: lat,
    longitude: lng,
    createdAt: DateTime.now().toUtc().subtract(atras),
  );

  group('o pacote de rádio carrega alarme', () {
    test('ida e volta preserva tipo e coordenada', () {
      final p = PacoteLocal(
        clientId: 'c1',
        topId: 'top-1',
        tipo: TipoDePacote.alarme,
        team: null,
        autorId: 'a1',
        autorNome: 'Edson',
        corpo: 'EMERGÊNCIA — Edson — -19.912998,-43.940933',
        criadaEm: DateTime.utc(2026, 10, 12, 13, 40),
        latitude: -19.912998,
        longitude: -43.940933,
      );

      final lido = PacoteLocal.deBytes(p.paraBytes())!;
      expect(lido.tipo, TipoDePacote.alarme);
      expect(lido.latitude, closeTo(-19.912998, 1e-9));
      expect(lido.longitude, closeTo(-43.940933, 1e-9));
      expect(lido.clientId, 'c1');
      // Nunca verdadeiro para o que vem do rádio.
      expect(lido.confirmada, isFalse);
    });

    test(
      'pacote de CHAT continua byte a byte igual ao da v1.0.41',
      () {
        // Este é o teste de compatibilidade. A equipe vai atualizar aos
        // poucos, e durante dias haverá aparelho velho e novo na mesma
        // malha. Se o pacote de chat mudasse, a conversa entre eles
        // morreria em silêncio.
        final chat = PacoteLocal(
          clientId: 'c2',
          topId: 'top-1',
          team: null,
          autorId: 'a1',
          autorNome: 'Edson',
          corpo: 'oi',
          criadaEm: DateTime.utc(2026, 10, 12, 13, 40),
        );
        final mapa = chat.paraMapa();
        expect(mapa.containsKey('tipo'), isFalse);
        expect(mapa.containsKey('lat'), isFalse);
        expect(mapa.containsKey('lng'), isFalse);
        expect(mapa['v'], 1);
      },
    );

    test(
      'alarme vai com v:1 para o aparelho velho NÃO o descartar',
      () {
        // `deBytes` rejeita versão desconhecida. Se o alarme subisse para
        // v:2, todo aparelho com a v1.0.41/42 jogaria o pedido de socorro
        // fora sem avisar ninguém — o pior resultado possível.
        //
        // Com v:1 ele é lido como mensagem de chat e o texto aparece no
        // chat geral. Não toca nem vibra, mas aparece.
        final alarme = PacoteLocal(
          clientId: 'c3',
          topId: 'top-1',
          tipo: TipoDePacote.alarme,
          team: null,
          autorId: 'a1',
          autorNome: 'Edson',
          corpo: 'EMERGÊNCIA — Edson — sem posição',
          criadaEm: DateTime.utc(2026, 10, 12, 13, 40),
        );
        expect(alarme.paraMapa()['v'], 1);
        expect(alarme.corpo, contains('EMERGÊNCIA'));
      },
    );

    test('meia coordenada não vira coordenada', () {
      final bytes = PacoteLocal(
        clientId: 'c4',
        topId: 'top-1',
        tipo: TipoDePacote.alarme,
        team: null,
        autorId: 'a1',
        autorNome: 'x',
        corpo: 'EMERGÊNCIA',
        criadaEm: DateTime.utc(2026, 10, 12),
        latitude: -19.9,
      ).paraBytes();

      final lido = PacoteLocal.deBytes(bytes)!;
      // Só latitude foi serializada; sem as duas, nenhuma vale. Aceitar
      // metade poria o marcador em cima do meridiano de Greenwich.
      expect(lido.latitude, isNull);
      expect(lido.longitude, isNull);
    });

    test('0,0 é coordenada VÁLIDA e tem de sobreviver', () {
      final lido = PacoteLocal.deBytes(
        PacoteLocal(
          clientId: 'c5',
          topId: 'top-1',
          tipo: TipoDePacote.alarme,
          team: null,
          autorId: 'a1',
          autorNome: 'x',
          corpo: 'EMERGÊNCIA',
          criadaEm: DateTime.utc(2026, 10, 12),
          latitude: 0,
          longitude: 0,
        ).paraBytes(),
      )!;
      expect(lido.latitude, 0);
      expect(lido.longitude, 0);
    });

    test('alarme é repassado adiante como qualquer pacote', () {
      // Multissalto: quem recebe repassa, e é isso que leva o alarme além
      // do alcance direto de quem disparou.
      final regras = RegrasDaMalha(meuTopId: 'top-1');
      final p = PacoteLocal(
        clientId: 'c6',
        topId: 'top-1',
        tipo: TipoDePacote.alarme,
        team: null,
        autorId: 'a1',
        autorNome: 'x',
        corpo: 'EMERGÊNCIA',
        criadaEm: DateTime.now().toUtc(),
      );
      final d = regras.decidir(p);
      expect(d, Decisao.aceitar);
      expect(regras.deveRepassar(d, p), isTrue);
      // E o salto preserva o tipo: sem isto o alarme viraria chat no
      // segundo salto e pararia de tocar.
      expect(p.maisUmSalto().tipo, TipoDePacote.alarme);
    });
  });

  group('a linha legível que viaja no rádio', () {
    test('tem quem, onde e o quê', () {
      final l = AlarmeService.linhaDeEmergencia(
        nome: 'Edson Barroso',
        mensagem: 'queda na trilha',
        latitude: -19.912998,
        longitude: -43.940933,
      );
      expect(l, startsWith('EMERGÊNCIA — Edson Barroso — '));
      expect(l, contains('-19.912998'));
      expect(l, contains('queda na trilha'));
    });

    test('sem GPS diz "sem posição" e NÃO inventa 0,0', () {
      final l = AlarmeService.linhaDeEmergencia(nome: 'Edson');
      expect(l, contains('sem posição'));
      expect(l, isNot(contains('0.000000')));
    });

    test('sem nome diz "Alguém do Top", nunca um uuid', () {
      final l = AlarmeService.linhaDeEmergencia(nome: '   ');
      expect(l, contains('Alguém do Top'));
    });
  });

  group('disparar usa o rádio quando a malha está ligada', () {
    test('manda pelo rádio E enfileira — são caminhos paralelos', () async {
      String? corpoEnviado;
      String? idEnviado;
      double? latEnviada;
      AlarmeService.instance.espalharPeloRadio =
          ({
            required String clientId,
            required String corpo,
            required DateTime criadaEm,
            double? latitude,
            double? longitude,
          }) async {
            idEnviado = clientId;
            corpoEnviado = corpo;
            latEnviada = latitude;
            return 2;
          };

      final r = await AlarmeService.instance.disparar(
        topId: 'top-1',
        mensagem: 'queda',
        latitude: -19.9,
        longitude: -43.9,
      );

      expect(r.tentadoPorRadio, isTrue);
      expect(r.vizinhosAoAlcance, 2);
      expect(idEnviado, r.clientId);
      expect(corpoEnviado, contains('EMERGÊNCIA'));
      expect(latEnviada, -19.9);

      // A fila continua sendo o caminho para quem está longe.
      expect(
        await Outbox.instance.pendingCount(entity: AlarmeService.entidade),
        1,
      );
    });

    test('o mesmo client_id vai para o rádio e para a fila', () async {
      // É isso que impede a pessoa de receber a MESMA emergência duas
      // vezes quando a rede voltar.
      String? peloRadio;
      AlarmeService.instance.espalharPeloRadio =
          ({
            required String clientId,
            required String corpo,
            required DateTime criadaEm,
            double? latitude,
            double? longitude,
          }) async {
            peloRadio = clientId;
            return 1;
          };

      final r = await AlarmeService.instance.disparar(topId: 'top-1');
      final naFila = await Outbox.instance.pending(limit: 10);
      expect(peloRadio, r.clientId);
      expect(naFila.single.payload['client_id'], r.clientId);
    });

    test('rádio quebrado NÃO desfaz o alarme', () async {
      AlarmeService.instance.espalharPeloRadio =
          ({
            required String clientId,
            required String corpo,
            required DateTime criadaEm,
            double? latitude,
            double? longitude,
          }) async {
            throw Exception('rádio morreu');
          };

      final r = await AlarmeService.instance.disparar(topId: 'top-1');
      expect(r.vizinhosAoAlcance, 0);
      expect(
        await Outbox.instance.pendingCount(entity: AlarmeService.entidade),
        1,
      );
    });
  });

  group('o texto nunca promete entrega', () {
    test('malha desligada: manda ligar o rádio', () async {
      final r = await AlarmeService.instance.disparar(topId: 'top-1');
      // `disparar` tenta sincronizar sem esperar. Sem esta costura o
      // envio toca o banco depois do tearDown e o teste quebra com
      // `database_closed` — ruído que não tem nada a ver com a regra.
      await AlarmeService.instance.envioEmAndamento;
      expect(r.tentadoPorRadio, isFalse);
      expect(r.resumo, contains('DESLIGADO'));
      expect(r.resumo, isNot(contains('avisado')));
    });

    test('zero vizinhos: diz que NINGUÉM foi avisado', () async {
      AlarmeService.instance.espalharPeloRadio =
          ({
            required String clientId,
            required String corpo,
            required DateTime criadaEm,
            double? latitude,
            double? longitude,
          }) async => 0;

      final r = await AlarmeService.instance.disparar(topId: 'top-1');
      await AlarmeService.instance.envioEmAndamento;
      expect(r.resumo, contains('NENHUM aparelho'));
      expect(r.resumo, contains('Ninguém por perto foi avisado'));
    });

    test(
      'com vizinhos: fala em APARELHOS ao alcance, não em pessoas avisadas',
      () async {
        AlarmeService.instance.espalharPeloRadio =
            ({
              required String clientId,
              required String corpo,
              required DateTime criadaEm,
              double? latitude,
              double? longitude,
            }) async => 3;

        final r = await AlarmeService.instance.disparar(topId: 'top-1');
        await AlarmeService.instance.envioEmAndamento;
        expect(r.resumo, contains('3 aparelhos ao alcance'));
        // A frase não pode afirmar recebimento: broadcast não tem ACK.
        expect(r.resumo, contains('NÃO confirma recebimento'));
        expect(r.resumo, isNot(contains('pessoas foram avisadas')));
      },
    );
  });

  group('receber alarme pelo rádio', () {
    test('entra na lista de ativos, marcado como não confirmado', () {
      AlarmeService.instance.receberAlarmeDoRadio(doRadio(clientId: 'c1'));
      final ativos = AlarmeService.instance.ativos;
      expect(ativos, hasLength(1));
      expect(ativos.single.confirmado, isFalse);
      expect(ativos.single.chave, 'c1');
    });

    test('o mesmo pacote duas vezes conta uma só', () {
      AlarmeService.instance
        ..receberAlarmeDoRadio(doRadio(clientId: 'c1'))
        ..receberAlarmeDoRadio(doRadio(clientId: 'c1'));
      expect(AlarmeService.instance.ativos, hasLength(1));
    });

    test('alarme velho (fora da janela de 1h) não aparece', () {
      AlarmeService.instance.receberAlarmeDoRadio(
        doRadio(clientId: 'c1', atras: const Duration(hours: 3)),
      );
      expect(AlarmeService.instance.ativos, isEmpty);
    });

    test('dá para dispensar um alarme que veio do rádio', () {
      AlarmeService.instance.receberAlarmeDoRadio(doRadio(clientId: 'c1'));
      AlarmeService.instance.descartar('c1');
      expect(AlarmeService.instance.ativos, isEmpty);
    });

    test('sem nome, mostra "Alguém do Top" e temNome é falso', () {
      AlarmeService.instance.receberAlarmeDoRadio(doRadio(clientId: 'c1'));
      final a = AlarmeService.instance.ativos.single;
      expect(a.quemChama, 'Alguém do Top');
      expect(a.temNome, isFalse);
    });

    test('com nome declarado, mostra o nome — ainda não confirmado', () {
      AlarmeService.instance.receberAlarmeDoRadio(
        doRadio(clientId: 'c1', nome: 'João Vitor'),
      );
      final a = AlarmeService.instance.ativos.single;
      expect(a.quemChama, 'João Vitor');
      expect(a.temNome, isTrue);
      // Nome declarado NÃO é identidade verificada.
      expect(a.confirmado, isFalse);
    });
  });

  group('rádio e servidor são o MESMO alarme, não dois', () {
    test(
      'chegando pelos dois caminhos, aparece uma vez e vale o do servidor',
      () {
        // Cenário real: o alarme chega por rádio em modo avião; horas
        // depois a rede volta e o mesmo alarme chega pelo Supabase. Sem
        // fundir pelo `client_id`, a equipe veria a mesma emergência duas
        // vezes — e aprenderia a ignorar o alarme.
        AlarmeService.instance.receberAlarmeDoRadio(
          doRadio(clientId: 'abc', nome: 'João'),
        );
        AlarmeService.instance.receberParaTestes([
          TopAlert(
            id: 42,
            clientId: 'abc',
            topId: 'top-1',
            senderId: 'hakuna-2',
            senderName: 'João Vitor',
            createdAt: DateTime.now().toUtc(),
          ),
        ]);

        final ativos = AlarmeService.instance.ativos;
        expect(ativos, hasLength(1));
        // O do servidor ganha: tem autoria confirmada.
        expect(ativos.single.confirmado, isTrue);
        expect(ativos.single.id, 42);
      },
    );

    test('alarme só do servidor continua funcionando como antes', () {
      AlarmeService.instance.receberParaTestes([
        TopAlert(
          id: 7,
          topId: 'top-1',
          senderId: 'hakuna-2',
          createdAt: DateTime.now().toUtc(),
        ),
      ]);
      final a = AlarmeService.instance.ativos.single;
      expect(a.confirmado, isTrue);
      expect(a.chave, 'srv:7');
    });
  });
}
