import 'package:flutter_test/flutter_test.dart';
import 'package:legendario_connect/models/top.dart';
import 'package:legendario_connect/services/lista_de_tops.dart';
import 'package:legendario_connect/services/supabase_service.dart';

/// O que a tela inicial mostra combinando o disco e a rede.
///
/// Motivo: com o servidor fora, quem entrava pelo `AuthGate` caía em
/// "Erro ao carregar tops: ClientException ... Failed host lookup" e não
/// tinha como chegar ao botão EMERGÊNCIA. A regra mora fora da tela para
/// ser testada sem montar a árvore nem fingir o Supabase.
void main() {
  final guardado = [
    Top(id: 'disco', name: 'Do disco', status: TopStatus.active),
  ];
  final doServidor = [
    Top(id: 'rede', name: 'Da rede', status: TopStatus.active),
  ];
  final redeFora = Exception(
    'ClientException with SocketException: Failed host lookup: '
    'jitfbambhmfnqiatwoud.supabase.co',
  );
  final outraFalha = Exception('PostgrestException(message: boom, code: 500)');

  /// Nenhuma frase da tela pode carregar o texto cru da exceção.
  void semTextoCru(TelaDeTops t) {
    final a = t.aviso ?? '';
    for (final cru in [
      'Exception',
      'Failed host lookup',
      'boom',
      'supabase.co',
    ]) {
      expect(a, isNot(contains(cru)), reason: 'aviso vazou "$cru": $a');
    }
  }

  test('rede respondeu: vale a lista do servidor, sem aviso', () {
    final t = telaDeTops(doDisco: guardado, daRede: doServidor);
    expect(t.tops.map((e) => e.id), ['rede']);
    expect(t.aviso, isNull);
    expect(t.carregando, isFalse);
  });

  test('rede respondeu com lista vazia: vazia, mesmo com disco', () {
    // O servidor é quem diz a que Tops a pessoa pertence; se ele diz
    // "nenhum", o disco antigo não pode desmenti-lo.
    final t = telaDeTops(doDisco: guardado, daRede: const []);
    expect(t.tops, isEmpty);
    expect(t.aviso, isNull);
  });

  test('sem rede e com disco: mostra o disco e avisa, curto', () {
    final t = telaDeTops(doDisco: guardado, erroDaRede: redeFora);
    expect(t.tops.map((e) => e.id), ['disco']);
    expect(t.aviso, isNotNull);
    expect(t.aviso, isNot(avisoServidorFora));
    expect(t.aviso, contains('aparelho'));
    semTextoCru(t);
  });

  test('sem rede e sem disco: aviso de servidor fora', () {
    final t = telaDeTops(doDisco: const [], erroDaRede: redeFora);
    expect(t.tops, isEmpty);
    expect(t.aviso, avisoServidorFora);
    semTextoCru(t);
  });

  test('falha que não é de rede, sem disco: frase própria, sem texto cru', () {
    final t = telaDeTops(doDisco: const [], erroDaRede: outraFalha);
    expect(t.tops, isEmpty);
    expect(t.aviso, isNotNull);
    expect(t.aviso, isNot(avisoServidorFora));
    semTextoCru(t);
  });

  test('falha que não é de rede, com disco: disco e aviso, sem texto cru', () {
    final t = telaDeTops(doDisco: guardado, erroDaRede: outraFalha);
    expect(t.tops.map((e) => e.id), ['disco']);
    expect(t.aviso, isNotNull);
    semTextoCru(t);
  });

  test('esperando a rede com disco: já mostra o disco, sem roda', () {
    final t = telaDeTops(doDisco: guardado);
    expect(t.tops.map((e) => e.id), ['disco']);
    expect(t.carregando, isFalse);
    expect(t.aviso, isNull);
  });

  test('esperando a rede sem disco (ou disco ainda lendo): roda', () {
    expect(telaDeTops(doDisco: const []).carregando, isTrue);
    expect(telaDeTops(doDisco: null).carregando, isTrue);
  });
}
