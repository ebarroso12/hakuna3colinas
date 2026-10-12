import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:legendario_connect/models/team.dart';
import 'package:legendario_connect/offline/cache_local.dart';
import 'package:legendario_connect/offline/chat_repositorio.dart';
import 'package:legendario_connect/offline/local_db.dart';
import 'package:legendario_connect/offline/tabelas.dart';
import 'package:legendario_connect/offline/transporte_local.dart';
import 'package:legendario_connect/services/malha_service.dart';
import 'package:legendario_connect/services/supabase_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A malha inteira, de ponta a ponta, com um rádio de mentira.
///
/// É isto que a separação entre rádio e regra compra: dá para provar que
/// a mensagem chega, é guardada como NÃO confirmada, não duplica e é
/// repassada — tudo sem Bluetooth, sem Android e sem dois aparelhos.
///
/// O que estes testes **não** provam: que o rádio de verdade conecta. Só
/// dois celulares provam isso.
class _RadioDeMentira implements TransporteLocal {
  final _recebidos = StreamController<List<int>>.broadcast();
  final _vizinhos = StreamController<int>.broadcast();

  /// Tudo que foi mandado para o ar, na ordem.
  final enviados = <List<int>>[];
  bool ligado = false;

  @override
  Stream<List<int>> get recebidos => _recebidos.stream;

  @override
  Stream<int> get vizinhos => _vizinhos.stream;

  @override
  Future<void> ligar({required String meuNome}) async => ligado = true;

  @override
  Future<void> desligar() async => ligado = false;

  @override
  Future<void> enviar(List<int> bytes) async => enviados.add(bytes);

  /// Simula um pacote chegando do ar.
  void chega(List<int> bytes) => _recebidos.add(bytes);

  void vizinhosAgora(int n) => _vizinhos.add(n);

  Future<void> fechar() async {
    await _recebidos.close();
    await _vizinhos.close();
  }
}

void main() {
  late _RadioDeMentira radio;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    LocalDb.overridePathForTests = inMemoryDatabasePath;
    await LocalDb.instance.close();
    SupabaseService.idDeUsuarioParaTestes = 'perfil-eu';
    radio = _RadioDeMentira();
    MalhaService.instance.transporteParaTestes = radio;
    await CacheLocal.instance.guardarEstado(
      ColunasEstado.meuNome,
      'Edson Barroso',
    );
  });

  tearDown(() async {
    await MalhaService.instance.desligar();
    MalhaService.instance.transporteParaTestes = null;
    SupabaseService.idDeUsuarioParaTestes = null;
    await radio.fechar();
    await LocalDb.instance.close();
  });

  PacoteLocal pacoteDeOutro({
    String clientId = 'c1',
    String corpo = 'queda no km 4',
    int saltos = 0,
    String topId = 'top-1',
  }) => PacoteLocal(
    clientId: clientId,
    topId: topId,
    team: TeamKey.seguranca,
    autorId: 'perfil-outro',
    autorNome: 'Maria da Logística',
    corpo: corpo,
    criadaEm: DateTime.now().toUtc(),
    saltos: saltos,
  );

  Future<List<Map<String, Object?>>> noDisco() =>
      CacheLocal.instance.lerMensagens(
        entidade: ChatRepositorio.entityTeam,
        topId: 'top-1',
        team: 'seguranca',
      );

  group('ligar e desligar', () {
    test('liga, conta vizinhos e desliga', () async {
      expect(await MalhaService.instance.ligar(topId: 'top-1'), isTrue);
      expect(MalhaService.instance.ligada, isTrue);
      expect(radio.ligado, isTrue);

      radio.vizinhosAgora(3);
      await Future<void>.delayed(Duration.zero);
      expect(MalhaService.instance.vizinhos, 3);

      await MalhaService.instance.desligar();
      expect(MalhaService.instance.ligada, isFalse);
      expect(radio.ligado, isFalse);
      // Sem rádio não há vizinho — a tela não pode continuar dizendo 3.
      expect(MalhaService.instance.vizinhos, 0);
    });

    test('ligar duas vezes não duplica nada', () async {
      await MalhaService.instance.ligar(topId: 'top-1');
      expect(await MalhaService.instance.ligar(topId: 'top-1'), isTrue);
      expect(MalhaService.instance.ligada, isTrue);
    });
  });

  group('recebendo pelo rádio', () {
    test('a mensagem chega ao disco como NÃO confirmada', () async {
      await MalhaService.instance.ligar(topId: 'top-1');

      radio.chega(pacoteDeOutro().paraBytes());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final lidas = await noDisco();
      expect(lidas, hasLength(1));
      expect(lidas.first['body'], 'queda no km 4');
      // O ponto de tudo: rádio não autentica ninguém.
      expect(lidas.first['confirmada'], isFalse);
      expect(lidas.first['sender_name'], 'Maria da Logística');
      expect(MalhaService.instance.mensagensRecebidas, 1);
    });

    test('o mesmo pacote duas vezes não duplica', () async {
      await MalhaService.instance.ligar(topId: 'top-1');
      final bytes = pacoteDeOutro(clientId: 'repetido').paraBytes();

      radio.chega(bytes);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      radio.chega(bytes);
      radio.chega(bytes);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(await noDisco(), hasLength(1));
      expect(MalhaService.instance.mensagensRecebidas, 1);
    });

    test('pacote de OUTRO Top não entra', () async {
      await MalhaService.instance.ligar(topId: 'top-1');
      radio.chega(pacoteDeOutro(topId: 'top-2').paraBytes());
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(await noDisco(), isEmpty);
    });

    test('lixo no ar não derruba a escuta', () async {
      await MalhaService.instance.ligar(topId: 'top-1');

      radio.chega([0, 1, 2, 255]);
      radio.chega('nem json'.codeUnits);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      // E depois do lixo a malha continua funcionando — é isto que
      // importa. Um pacote ruim não pode calar o rádio numa emergência.
      radio.chega(pacoteDeOutro(clientId: 'depois').paraBytes());
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(await noDisco(), hasLength(1));
    });
  });

  group('repasse', () {
    test('o que foi aceito é repassado com um salto a mais', () async {
      await MalhaService.instance.ligar(topId: 'top-1');

      radio.chega(pacoteDeOutro(saltos: 0).paraBytes());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(radio.enviados, hasLength(1));
      final repassado = PacoteLocal.deBytes(radio.enviados.single)!;
      expect(repassado.saltos, 1);
      expect(repassado.clientId, 'c1');
      expect(MalhaService.instance.mensagensRepassadas, 1);
    });

    test('pacote no limite de saltos NÃO é repassado', () async {
      await MalhaService.instance.ligar(topId: 'top-1');
      radio.chega(pacoteDeOutro(saltos: 5).paraBytes());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Nem aceito, nem repassado: é o freio que impede a malha de
      // repassar o mesmo pacote para sempre e acabar com a bateria de
      // todo mundo por causa de uma mensagem.
      expect(await noDisco(), isEmpty);
      expect(radio.enviados, isEmpty);
    });
  });

  group('espalhando o que eu escrevi', () {
    test('sai no ar com o meu nome e o meu id', () async {
      await MalhaService.instance.ligar(topId: 'top-1');

      await MalhaService.instance.espalhar(
        clientId: 'minha-1',
        team: TeamKey.seguranca,
        corpo: 'estou no km 6',
        criadaEm: DateTime.now().toUtc(),
      );

      expect(radio.enviados, hasLength(1));
      final p = PacoteLocal.deBytes(radio.enviados.single)!;
      expect(p.corpo, 'estou no km 6');
      expect(p.autorId, 'perfil-eu');
      expect(p.autorNome, 'Edson Barroso');
      expect(p.saltos, 0);
    });

    test('a minha mensagem NÃO volta da malha como novidade', () async {
      await MalhaService.instance.ligar(topId: 'top-1');
      await MalhaService.instance.espalhar(
        clientId: 'minha-2',
        team: TeamKey.seguranca,
        corpo: 'minha mensagem',
        criadaEm: DateTime.now().toUtc(),
      );

      // Um vizinho repassa de volta o que eu mandei. Sem o `jaConheco`,
      // eu guardaria a minha própria mensagem como se fosse de outro — e
      // ela apareceria duas vezes, uma delas marcada "não confirmada".
      final devolta = PacoteLocal.deBytes(radio.enviados.single)!;
      radio.chega(devolta.maisUmSalto().paraBytes());
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(await noDisco(), isEmpty);
      expect(MalhaService.instance.mensagensRecebidas, 0);
    });

    test('espalhar com a malha desligada não estoura', () async {
      await MalhaService.instance.espalhar(
        clientId: 'x',
        team: TeamKey.midia,
        corpo: 'sem malha ligada',
        criadaEm: DateTime.now().toUtc(),
      );
      expect(radio.enviados, isEmpty);
    });
  });
}
