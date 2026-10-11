import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:legendario_connect/models/team.dart';
import 'package:legendario_connect/models/team_message.dart';
import 'package:legendario_connect/services/importador_de_pessoas.dart';

/// O importador é onde um erro vira **pessoa errada numa ficha médica**:
/// número trocado significa comorbidade e alergia de outro aparecendo no
/// atendimento. Daí o tamanho deste arquivo.
///
/// PDF não entra aqui por decisão: é para retenção de documento, não para
/// dado. Extrair tabela de PDF não é confiável — imagem escaneada precisa
/// de OCR, e OCR confunde `0`/`O` e `1`/`l` em número e erra nome próprio.
void main() {
  group('detectar separador', () {
    test('planilha brasileira sai com ; e tem de ser reconhecida', () {
      // É o caso que mais importa: a vírgula é o separador decimal no
      // Brasil, então o Excel em pt-BR exporta com `;`. Assumir `,` leria
      // a linha inteira numa coluna só, e o admin veria 216 linhas
      // "válidas" com o nome errado.
      expect(
        ImportadorDePessoas.detectarSeparador('Nome;Numero;Familia'),
        ';',
      );
    });

    test('vírgula, tabulação e pipe também', () {
      expect(ImportadorDePessoas.detectarSeparador('Nome,Numero'), ',');
      expect(ImportadorDePessoas.detectarSeparador('Nome\tNumero'), '\t');
      expect(ImportadorDePessoas.detectarSeparador('Nome|Numero'), '|');
    });

    test('ignora linhas vazias no topo', () {
      expect(
        ImportadorDePessoas.detectarSeparador('\n\n  \nNome;Numero;UF'),
        ';',
      );
    });
  });

  group('normalizar cabeçalho', () {
    test('tira acento, caixa e símbolo de número', () {
      // Planilha de verdade vem com "Nº Legendário", não com
      // "numero_legendarios".
      expect(ImportadorDePessoas.normalizar('Nº Legendário'), 'n legendario');
      expect(ImportadorDePessoas.normalizar('NOME COMPLETO'), 'nome completo');
      expect(ImportadorDePessoas.normalizar('  Família  '), 'familia');
      expect(ImportadorDePessoas.normalizar('Intercessão'), 'intercessao');
    });
  });

  Uint8List bytesDe(String s) => Uint8List.fromList(utf8.encode(s));

  group('ler CSV', () {
    test('lê nome, número, família e UF', () {
      final r = ImportadorDePessoas.lerCsv(
        bytesDe(
          'Nome;Nº Legendário;Família;UF\n'
          'joão da silva;203460;Águia;SP\n'
          'maria souza;1782;Leão;MG\n',
        ),
      );

      expect(r.erro, isNull);
      expect(r.pessoas.length, 2);
      // Nome em caixa alta: é como a lista do app mostra, e misturar
      // caixas na mesma lista atrapalha a busca visual do Hakuna.
      expect(r.pessoas[0].nome, 'JOÃO DA SILVA');
      expect(r.pessoas[0].numero, '203460');
      expect(r.pessoas[0].familia, 'ÁGUIA');
      expect(r.pessoas[0].estado, 'SP');
      expect(r.pessoas.every((p) => p.valida), isTrue);
    });

    test('número é TEXTO: "007" não vira 7', () {
      // Com conversão automática de número, "007" viraria 7 e deixaria de
      // casar com a lista do Top — a pessoa não conseguiria se cadastrar.
      final r = ImportadorDePessoas.lerCsv(
        bytesDe('Nome;Numero\nZERO ZERO SETE;007\n'),
      );
      expect(r.pessoas.single.numero, '007');
    });

    test('limpa pontuação do número e mantém só dígito', () {
      final r = ImportadorDePessoas.lerCsv(
        bytesDe('Nome;Numero\nA;20.34-60\nB; 1782 \n'),
      );
      expect(r.pessoas[0].numero, '203460');
      expect(r.pessoas[1].numero, '1782');
    });

    test('acusa número repetido, apontando a linha', () {
      // Dois senderistas com o mesmo número é o erro que faz um atender
      // pelo prontuário do outro. A mensagem diz QUAL linha colide.
      final r = ImportadorDePessoas.lerCsv(
        bytesDe('Nome;Numero\nA;100\nB;200\nC;100\n'),
      );
      expect(r.pessoas[0].problemas, isEmpty);
      expect(r.pessoas[2].problemas.single, contains('repetido'));
      expect(r.pessoas[2].problemas.single, contains('linha 2'));
      expect(r.pessoas[2].valida, isFalse);
    });

    test('acusa número com mais de 12 dígitos', () {
      // A MESMA regra de `AcessoService.regexNumero` e da Edge Function.
      // Divergir faria o importador aceitar o que o autocadastro recusa.
      final r = ImportadorDePessoas.lerCsv(
        bytesDe('Nome;Numero\nA;1234567890123\n'),
      );
      expect(r.pessoas.single.problemas.single, contains('12 dígitos'));
      expect(r.pessoas.single.numero, isNull);
    });

    test('número sem nenhum dígito é recusado, não gravado como lixo', () {
      final r = ImportadorDePessoas.lerCsv(
        bytesDe('Nome;Numero\nA;sem numero\n'),
      );
      expect(r.pessoas.single.problemas.single, contains('sem dígito'));
      expect(r.pessoas.single.numero, isNull);
    });

    test('linha sem nome é marcada inválida', () {
      // Sem nome não há pessoa — e um `participant_code` órfão é pior que
      // uma linha a menos.
      final r = ImportadorDePessoas.lerCsv(
        bytesDe('Nome;Numero\n;999\nB;888\n'),
      );
      expect(r.pessoas[0].valida, isFalse);
      expect(r.pessoas[0].problemas, contains('sem nome'));
      expect(r.pessoas[0].selecionada, isFalse);
      expect(r.pessoas[1].valida, isTrue);
    });

    test('sem coluna de NOME, recusa o arquivo inteiro', () {
      // Melhor recusar que importar 216 linhas com o campo errado.
      final r = ImportadorDePessoas.lerCsv(
        bytesDe('Numero;Familia\n100;Águia\n'),
      );
      expect(r.erro, contains('NOME'));
      expect(r.pessoas, isEmpty);
    });

    test('arquivo vazio e só-linhas-vazias dão erro claro', () {
      expect(ImportadorDePessoas.lerCsv(bytesDe('')).erro, isNotNull);
      expect(
        ImportadorDePessoas.lerCsv(bytesDe('\n\n  \n')).erro,
        isNotNull,
      );
    });

    test('pula linhas vazias antes do cabeçalho', () {
      final r = ImportadorDePessoas.lerCsv(
        bytesDe('\n\nNome;Numero\nA;1\n'),
      );
      expect(r.erro, isNull);
      expect(r.pessoas.single.nome, 'A');
    });

    test('arquivo em Latin-1 não derruba a leitura', () {
      // Export de sistema antigo vem assim. O acento sai trocado e o
      // admin vê isso na revisão — melhor que a importação estourar.
      final bytes = Uint8List.fromList([
        ...utf8.encode('Nome;Numero\n'),
        0x4A, 0x4F, 0xC3, // "JOÃ" truncado: byte inválido em UTF-8
        ...utf8.encode('O;100\n'),
      ]);
      final r = ImportadorDePessoas.lerCsv(bytes);
      expect(r.erro, isNull);
      expect(r.pessoas, isNotEmpty);
    });
  });

  group('equipe e cargo', () {
    test('reconhece as 9 equipes pelo nome que as pessoas usam', () {
      final r = ImportadorDePessoas.lerCsv(
        bytesDe(
          'Nome;Equipe\n'
          'A;Logística\n'
          'B;Intercessão\n'
          'C;Segurança\n'
          'D;HAKUNAS\n'
          'E;salvamento\n'
          'F;Administração\n',
        ),
      );
      expect(r.pessoas[0].equipe, TeamKey.logistica);
      expect(r.pessoas[1].equipe, TeamKey.intercessao);
      expect(r.pessoas[2].equipe, TeamKey.seguranca);
      // "salvamento" e "hakunas" são a mesma equipe: é o nome que o
      // movimento usa, e exigir a chave do enum faria o admin editar a
      // planilha — e aí ele edita errado.
      expect(r.pessoas[3].equipe, TeamKey.hakunas);
      expect(r.pessoas[4].equipe, TeamKey.hakunas);
      expect(r.pessoas[5].equipe, TeamKey.adm);
      expect(r.pessoas.every((p) => p.problemas.isEmpty), isTrue);
    });

    test('equipe desconhecida vira problema, não silêncio', () {
      final r = ImportadorDePessoas.lerCsv(
        bytesDe('Nome;Equipe\nA;Cozinha\n'),
      );
      expect(r.pessoas.single.problemas.single, contains('Cozinha'));
      expect(r.pessoas.single.equipe, isNull);
      expect(r.pessoas.single.valida, isFalse);
    });

    test('reconhece cargo, inclusive abreviado', () {
      final r = ImportadorDePessoas.lerCsv(
        bytesDe(
          'Nome;Equipe;Cargo\n'
          'A;midia;Coordenador\n'
          'B;midia;sub\n'
          'C;midia;membro\n'
          'D;midia;senderista\n',
        ),
      );
      expect(r.pessoas[0].cargo, TeamRole.coordenador);
      expect(r.pessoas[1].cargo, TeamRole.subcoordenador);
      expect(r.pessoas[2].cargo, TeamRole.membro);
      expect(r.pessoas[3].cargo, TeamRole.membro);
    });

    test('cargo SEM equipe é problema: não há onde aplicar', () {
      final r = ImportadorDePessoas.lerCsv(
        bytesDe('Nome;Cargo\nA;coordenador\n'),
      );
      expect(
        r.pessoas.single.problemas,
        contains('cargo informado sem equipe'),
      );
    });

    test('cargo desconhecido vira problema', () {
      final r = ImportadorDePessoas.lerCsv(
        bytesDe('Nome;Equipe;Cargo\nA;voz;Chefe Supremo\n'),
      );
      expect(r.pessoas.single.problemas.first, contains('Chefe Supremo'));
    });
  });

  group('o que a tela precisa mostrar', () {
    test('diz qual coluna virou qual campo', () {
      // Serve para o admin perceber se o sistema leu a coluna errada —
      // antes de gravar, não depois.
      final r = ImportadorDePessoas.lerCsv(
        bytesDe('Nome Completo;Nº Legendário;Celular\nA;1;99\n'),
      );
      expect(r.cabecalhoReconhecido['Nome Completo'], 'nome');
      expect(r.cabecalhoReconhecido['Nº Legendário'], 'numero');
      expect(r.cabecalhoReconhecido['Celular'], 'telefone');
    });

    test('lista as colunas IGNORADAS', () {
      // Se o nome da pessoa estiver numa coluna ignorada, o admin vê.
      final r = ImportadorDePessoas.lerCsv(
        bytesDe('Nome;Camiseta;Pagou\nA;M;sim\n'),
      );
      expect(r.colunasIgnoradas, containsAll(['Camiseta', 'Pagou']));
    });

    test('guarda o número da linha no arquivo', () {
      // "linha 4 está errada" é acionável; "uma linha está errada" não.
      final r = ImportadorDePessoas.lerCsv(
        bytesDe('Nome;Numero\nA;1\nB;2\n'),
      );
      expect(r.pessoas[0].linhaNoArquivo, 2);
      expect(r.pessoas[1].linhaNoArquivo, 3);
    });

    test('UF inválida é descartada sem invalidar a pessoa', () {
      // Dado de cadastro, não de identidade: perder a pessoa por causa da
      // UF seria desproporcional.
      final r = ImportadorDePessoas.lerCsv(
        bytesDe('Nome;UF\nA;São Paulo\n'),
      );
      expect(r.pessoas.single.estado, isNull);
      expect(r.pessoas.single.valida, isTrue);
    });
  });

  group('ler XLSX', () {
    test('arquivo que não é planilha dá erro explicando o .xls', () {
      // `.xls` antigo é binário e a lib não lê. A mensagem manda salvar
      // como `.xlsx` em vez de dizer "falha ao ler".
      final r = ImportadorDePessoas.lerXlsx(
        Uint8List.fromList(utf8.encode('isto nao e um xlsx')),
      );
      expect(r.erro, isNotNull);
      expect(r.erro, contains('.xls'));
      expect(r.pessoas, isEmpty);
    });
  });
}
