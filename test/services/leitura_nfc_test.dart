import 'package:flutter_test/flutter_test.dart';
import 'package:legendario_connect/services/nfc_service.dart';

/// O que uma aproximação de tag diz quando NÃO identifica ninguém.
///
/// A troca de `nfc_manager` para `flutter_nfc_kit`, em 11/10/2026, existiu
/// por isto: o caminho antigo só sabia ler NDEF, e tudo que não fosse NDEF
/// voltava como `null`. Cartão em branco, cartão de outro sistema e MIFARE
/// Classic que o chipset não formata eram indistinguíveis de "nenhuma tag
/// foi encostada" — e quem está em campo precisa saber a diferença para
/// decidir entre trocar a pulseira e insistir no celular.
///
/// A leitura do chip em si só se verifica em aparelho físico com tag na
/// mão. O que se pode travar em teste é o que a tela mostra a partir dela,
/// e é isso que está aqui.
void main() {
  LeituraNfc chip({
    String uid = '',
    String tipo = 'unknown',
    String padrao = 'unknown',
    bool temNdef = false,
    bool gravavel = false,
    String? conteudo,
  }) => LeituraNfc(
    uid: uid,
    tipo: tipo,
    padrao: padrao,
    temNdef: temNdef,
    gravavel: gravavel,
    conteudo: conteudo,
  );

  group('uidLegivel — hex em pares, como se lê num cartão', () {
    test('UID de 4 bytes (MIFARE Classic, NTAG antigo)', () {
      expect(chip(uid: '04a2b3c4').uidLegivel, '04:A2:B3:C4');
    });

    test('UID de 7 bytes (NTAG21x)', () {
      expect(
        chip(uid: '04a1b2c3d4e5f6').uidLegivel,
        '04:A1:B2:C3:D4:E5:F6',
      );
    });

    test('sem UID devolve vazio, não "::"', () {
      expect(chip().uidLegivel, '');
    });

    test('hex de tamanho ímpar não estoura — o chip pode mentir', () {
      // Nenhum UID real tem número ímpar de dígitos hex, mas o valor vem
      // de um canal nativo e não vale travar a tela de leitura por causa
      // de um byte a menos. O último dígito solto é descartado.
      expect(chip(uid: '04a2b').uidLegivel, '04:A2');
    });
  });

  group('vazia — a aproximação completou ou não', () {
    test('cartão em branco NÃO é vazio: o UID identifica o cartão', () {
      final c = chip(uid: '04a2b3c4', tipo: 'mifareClassic');
      expect(c.vazia, isFalse);
      expect(c.temNdef, isFalse);
    });

    test('pulseira nossa, com token gravado', () {
      final c = chip(
        uid: '04a1b2c3d4e5f6',
        tipo: 'mifareUltralight',
        temNdef: true,
        gravavel: true,
        conteudo: 'https://legendarios.app/t/abc123',
      );
      expect(c.vazia, isFalse);
      expect(c.conteudo, contains('/t/'));
    });

    test('nada em nada é vazio — a tag saiu de perto antes de responder', () {
      expect(chip().vazia, isTrue);
    });

    test('conteúdo em branco com UID ainda não é vazio', () {
      expect(chip(uid: '04a2b3c4', conteudo: '').vazia, isFalse);
    });
  });

  group('DisponibilidadeNfc', () {
    test('os três estados são distintos e nenhum é "mais ou menos"', () {
      // "Sem leitor" e "desligado" exigem telas diferentes: a primeira
      // manda para o QR, a segunda manda para as Configurações. Tratar as
      // duas como "sem NFC" mandava o usuário comprar outro celular
      // quando bastava ligar o NFC.
      expect(DisponibilidadeNfc.values, hasLength(3));
      expect(
        DisponibilidadeNfc.values.toSet(),
        {
          DisponibilidadeNfc.semLeitor,
          DisponibilidadeNfc.desligado,
          DisponibilidadeNfc.pronto,
        },
      );
    });
  });
}
