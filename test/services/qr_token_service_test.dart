import 'package:flutter_test/flutter_test.dart';
import 'package:hakuna_connect/models/participant_tag.dart';
import 'package:hakuna_connect/services/qr_token_service.dart';

/// O QR é contingência do NFC e carrega o MESMO token. Estes testes travam
/// essa equivalência: se um dia alguém introduzir um formato próprio para o
/// QR, aqui quebra.
void main() {
  group('QR com token do sistema', () {
    test('URL completa da pulseira', () {
      final r = QrTokenService.interpretar(
        'https://legendarios.app/t/0123456789abcdef0123456789abcdef',
      );
      expect(r, isA<QrComToken>());
      expect(
        (r as QrComToken).token,
        '0123456789abcdef0123456789abcdef',
      );
    });

    test('token cru, sem URL', () {
      final r = QrTokenService.interpretar(
        '0123456789ABCDEF0123456789ABCDEF',
      );
      // Normaliza para minúsculo: o mesmo token em caixa diferente tem de
      // resolver para a mesma pulseira.
      expect((r as QrComToken).token, '0123456789abcdef0123456789abcdef');
    });

    test('espaço em volta não quebra', () {
      final r = QrTokenService.interpretar(
        '  https://legendarios.app/t/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa  ',
      );
      expect(r, isA<QrComToken>());
    });
  });

  group('QR que não é da pulseira', () {
    test('link qualquer', () {
      final r = QrTokenService.interpretar('https://exemplo.com/promo');
      expect(r, isA<QrDeOutroSistema>());
      expect((r as QrDeOutroSistema).amostra, 'https://exemplo.com/promo');
    });

    test('QR de wi-fi', () {
      final r = QrTokenService.interpretar('WIFI:S:Alojamento;T:WPA;P:1234;;');
      expect(r, isA<QrDeOutroSistema>());
    });

    test('token com tamanho errado não passa', () {
      // 31 caracteres. Um token truncado não pode virar consulta.
      final r = QrTokenService.interpretar('0123456789abcdef0123456789abcde');
      expect(r, isA<QrDeOutroSistema>());
    });

    test('hex com caractere inválido não passa', () {
      final r = QrTokenService.interpretar('0123456789abcdef0123456789abcdeZ');
      expect(r, isA<QrDeOutroSistema>());
    });

    test('vazio e null caem em outro sistema, não em exceção', () {
      expect(QrTokenService.interpretar(null), isA<QrDeOutroSistema>());
      expect(QrTokenService.interpretar('   '), isA<QrDeOutroSistema>());
    });

    test('amostra longa é truncada para caber na tela', () {
      final r =
          QrTokenService.interpretar('x' * 200) as QrDeOutroSistema;
      expect(r.amostra.length, lessThanOrEqualTo(41));
      expect(r.amostra, endsWith('…'));
    });
  });

  group('equivalência com o NDEF', () {
    test('o conteúdo do QR é idêntico ao gravado na pulseira', () {
      final token = TagNdef.novoToken();
      expect(QrTokenService.conteudoPara(token), TagNdef.urlPara(token));
    });

    test('ida e volta: gera, codifica e volta ao mesmo token', () {
      for (var i = 0; i < 50; i++) {
        final token = TagNdef.novoToken();
        final lido = QrTokenService.interpretar(
          QrTokenService.conteudoPara(token),
        );
        expect((lido as QrComToken).token, token);
      }
    });
  });
}
