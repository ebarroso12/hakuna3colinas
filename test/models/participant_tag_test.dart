import 'package:flutter_test/flutter_test.dart';
import 'package:hakuna_connect/models/participant_tag.dart';

void main() {
  group('geração de token', () {
    test('tem 32 caracteres hex — 128 bits', () {
      final t = TagNdef.novoToken();
      expect(t, matches(RegExp(r'^[0-9a-f]{32}$')));
    });

    test('não repete em 2000 gerações', () {
      final tokens = List.generate(2000, (_) => TagNdef.novoToken()).toSet();
      expect(tokens.length, 2000);
    });

    test('a URL gravada na tag não contém nada além do token', () {
      final t = TagNdef.novoToken();
      final url = TagNdef.urlPara(t);
      expect(url, 'https://legendarios.app/t/$t');
      // Nenhum dado pessoal pode acabar na pulseira.
      expect(url.toLowerCase(), isNot(contains('nome')));
      expect(url.toLowerCase(), isNot(contains('cpf')));
    });
  });

  group('extração do token lido da tag', () {
    final token = TagNdef.novoToken();

    test('lê da URL completa', () {
      expect(TagNdef.tokenDe(TagNdef.urlPara(token)), token);
    });

    test('aceita o token puro, sem URL', () {
      expect(TagNdef.tokenDe(token), token);
    });

    test('tolera host diferente — o que vale é o último segmento', () {
      expect(TagNdef.tokenDe('https://outro.dominio.br/t/$token'), token);
    });

    test('normaliza maiúsculas', () {
      expect(TagNdef.tokenDe(token.toUpperCase()), token);
    });

    test('ignora espaço em volta', () {
      expect(TagNdef.tokenDe('  ${TagNdef.urlPara(token)}  '), token);
    });

    test('tag de outro sistema devolve null em vez de consultar à toa', () {
      expect(TagNdef.tokenDe('https://exemplo.com/qualquer-coisa'), isNull);
      expect(TagNdef.tokenDe('texto solto'), isNull);
      expect(TagNdef.tokenDe(''), isNull);
      expect(TagNdef.tokenDe(null), isNull);
    });

    test('token de tamanho errado é rejeitado', () {
      expect(TagNdef.tokenDe('abc123'), isNull);
      expect(TagNdef.tokenDe('a' * 31), isNull);
      expect(TagNdef.tokenDe('a' * 33), isNull);
    });

    test('caractere não-hex é rejeitado', () {
      expect(TagNdef.tokenDe('z' * 32), isNull);
    });
  });

  group('status da tag', () {
    test('só "ativa" vale', () {
      expect(TagStatus.ativa.valida, isTrue);
      expect(TagStatus.revogada.valida, isFalse);
      expect(TagStatus.substituida.valida, isFalse);
    });

    test('status desconhecido cai em revogada — na dúvida, não libera', () {
      expect(tagStatusFromString('status_novo_qualquer'), TagStatus.revogada);
      expect(tagStatusFromString(null), TagStatus.revogada);
      expect(tagStatusFromString(''), TagStatus.revogada);
    });

    test('os três valores batem com o enum do Postgres', () {
      expect(TagStatus.values.map((s) => s.name).toSet(), {
        'ativa',
        'revogada',
        'substituida',
      });
    });
  });

  group('ParticipantTag.fromMap', () {
    Map<String, dynamic> linha({String status = 'ativa'}) => {
      'id': 'tag-1',
      'token': 'a' * 32,
      'participant_id': 'p1',
      'top_id': 't1',
      'status': status,
      'issued_at': '2026-10-09T12:00:00Z',
    };

    test('tag ativa é válida', () {
      expect(ParticipantTag.fromMap(linha()).valida, isTrue);
    });

    test('tag revogada não é válida', () {
      final t = ParticipantTag.fromMap(linha(status: 'revogada'));
      expect(t.valida, isFalse);
      expect(t.status, TagStatus.revogada);
    });

    test('tag substituída não é válida — a nova é que vale', () {
      expect(
        ParticipantTag.fromMap(linha(status: 'substituida')).valida,
        isFalse,
      );
    });
  });

  group('mensagens ao Hakuna', () {
    test('cada resultado tem mensagem própria e acionável', () {
      for (final r in ResultadoLeitura.values) {
        expect(r.mensagem.trim(), isNotEmpty, reason: r.name);
      }
      // Os dois casos em que o Hakuna precisa cair para a busca por nome
      // dizem isso explicitamente.
      expect(ResultadoLeitura.revogada.mensagem, contains('nome'));
      expect(ResultadoLeitura.semDados.mensagem, contains('nome'));
    });

    test('tag revogada avisa em caixa alta que não vale mais', () {
      expect(ResultadoLeitura.revogada.mensagem, contains('REVOGADA'));
    });
  });
}
