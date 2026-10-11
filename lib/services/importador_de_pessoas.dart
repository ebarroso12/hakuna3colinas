import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:excel/excel.dart';

import '../models/team.dart';
import '../models/team_message.dart';

/// Uma linha lida do arquivo, já interpretada.
///
/// Nada aqui foi gravado no banco. A tela mostra isto para o admin
/// conferir **antes** — importar direto é o caminho que coloca gente
/// errada numa ficha médica.
class PessoaImportada {
  PessoaImportada({
    required this.linhaNoArquivo,
    this.nome,
    this.numero,
    this.familia,
    this.telefone,
    this.cidade,
    this.estado,
    this.equipe,
    this.cargo,
    this.problemas = const [],
  });

  final int linhaNoArquivo;
  String? nome;
  String? numero;
  String? familia;
  String? telefone;
  String? cidade;
  String? estado;
  TeamKey? equipe;
  TeamRole? cargo;

  /// O que impede ou merece atenção. Lista vazia = linha limpa.
  List<String> problemas;

  /// Só importa linha com nome. Sem nome não há pessoa — e um
  /// `participant_code` órfão é pior que uma linha a menos.
  bool get valida => (nome ?? '').trim().isNotEmpty && problemas.isEmpty;

  /// Marcada para importar. A tela desmarca o que o admin não quer.
  bool selecionada = true;
}

/// O resultado da leitura de um arquivo.
class LeituraDoArquivo {
  const LeituraDoArquivo({
    required this.pessoas,
    required this.cabecalhoReconhecido,
    required this.colunasIgnoradas,
    this.erro,
  });

  final List<PessoaImportada> pessoas;

  /// Coluna do arquivo -> campo do sistema. Serve para a tela mostrar o
  /// que entendeu, e para o admin perceber se leu a coluna errada.
  final Map<String, String> cabecalhoReconhecido;

  /// Colunas que existem no arquivo e o sistema não usa. Mostradas de
  /// propósito: se o nome da pessoa estiver numa delas, o admin vê.
  final List<String> colunasIgnoradas;

  final String? erro;

  bool get vazio => pessoas.isEmpty;
}

/// Lê lista de pessoas de CSV, XLSX e TXT delimitado.
///
/// **Por que PDF não está aqui.** Decisão tomada com o dono do projeto:
/// PDF é para retenção de documento, não para dado. Extrair tabela de PDF
/// não é confiável — se for imagem escaneada precisa de OCR, e OCR erra
/// nome próprio e confunde `0`/`O` e `1`/`l`. Num app que trata gente,
/// número do Legendários errado significa comorbidade e alergia da pessoa
/// errada aparecendo no atendimento.
///
/// **Nada é gravado aqui.** A classe só interpreta; quem grava é a tela,
/// depois de o admin revisar linha por linha.
class ImportadorDePessoas {
  ImportadorDePessoas._();

  /// Sinônimos de cabeçalho, normalizados (minúsculo, sem acento).
  ///
  /// A lista é generosa de propósito: planilha de verdade vem com
  /// "Nº Legendário", "numero", "cod", "matricula". Exigir um cabeçalho
  /// exato faria o admin editar o arquivo antes de importar — e aí ele
  /// edita errado.
  static const _sinonimos = <String, List<String>>{
    'nome': ['nome', 'nome completo', 'nomecompleto', 'participante', 'pessoa'],
    'numero': [
      'numero',
      'numero legendarios',
      'n legendarios',
      'no legendarios',
      'num',
      'codigo',
      'cod',
      'matricula',
      'participant code',
      'participant_code',
    ],
    'familia': ['familia', 'family', 'grupo'],
    'telefone': ['telefone', 'tel', 'celular', 'fone', 'whatsapp', 'phone'],
    'cidade': ['cidade', 'city', 'municipio'],
    'estado': ['estado', 'uf', 'state'],
    'equipe': ['equipe', 'time', 'team', 'setor'],
    'cargo': ['cargo', 'funcao', 'papel', 'posicao', 'role', 'team_role'],
  };

  /// Sinônimos de equipe. Aceita o nome que as pessoas usam, não só a
  /// chave do enum.
  static const _equipes = <String, TeamKey>{
    'adm': TeamKey.adm,
    'administracao': TeamKey.adm,
    'administrativo': TeamKey.adm,
    'logistica': TeamKey.logistica,
    'voz': TeamKey.voz,
    'intercessao': TeamKey.intercessao,
    'producao': TeamKey.producao,
    'midia': TeamKey.midia,
    'media': TeamKey.midia,
    'eventos': TeamKey.eventos,
    'seguranca': TeamKey.seguranca,
    'hakunas': TeamKey.hakunas,
    'hakuna': TeamKey.hakunas,
    'salvamento': TeamKey.hakunas,
    'saude': TeamKey.hakunas,
    'geral': TeamKey.geral,
  };

  static const _cargos = <String, TeamRole>{
    'coordenador': TeamRole.coordenador,
    'coordenadora': TeamRole.coordenador,
    'coord': TeamRole.coordenador,
    'subcoordenador': TeamRole.subcoordenador,
    'subcoordenadora': TeamRole.subcoordenador,
    'sub': TeamRole.subcoordenador,
    'subcoord': TeamRole.subcoordenador,
    'membro': TeamRole.membro,
    'membra': TeamRole.membro,
    'equipe': TeamRole.membro,
    'senderista': TeamRole.membro,
    'legendario': TeamRole.membro,
  };

  /// Tira acento, espaço duplo e caixa. É o que torna "Nº LEGENDÁRIO" e
  /// "numero legendarios" o mesmo cabeçalho.
  static String normalizar(String bruto) {
    const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
    const para = 'aaaaaeeeeiiiiooooouuuucn';
    var t = bruto.toLowerCase().trim();
    for (var i = 0; i < de.length; i++) {
      t = t.replaceAll(de[i], para[i]);
    }
    // 'nº' e 'n°' viram 'n'; o resto que não é letra/dígito vira espaço.
    t = t.replaceAll(RegExp('[º°]'), '');
    t = t.replaceAll(RegExp('[^a-z0-9]+'), ' ');
    return t.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static String? _campoDe(String cabecalho) {
    final n = normalizar(cabecalho);
    if (n.isEmpty) return null;
    for (final e in _sinonimos.entries) {
      if (e.value.contains(n)) return e.key;
    }
    // Casamento por prefixo, para "nome do participante" cair em nome.
    for (final e in _sinonimos.entries) {
      for (final s in e.value) {
        if (n.startsWith(s) || s.startsWith(n)) return e.key;
      }
    }
    return null;
  }

  /// Descobre o separador de um CSV/TXT.
  ///
  /// Planilha brasileira sai com `;` porque a vírgula é o separador
  /// decimal. Assumir `,` leria a linha inteira numa coluna só — e o
  /// admin veria 216 linhas "válidas" com o nome errado. Conta qual
  /// aparece mais na primeira linha não vazia.
  static String detectarSeparador(String texto) {
    final primeira = texto
        .split(RegExp(r'\r?\n'))
        .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '');
    var melhor = ',';
    var maior = 0;
    for (final sep in [';', ',', '\t', '|']) {
      final n = primeira.split(sep).length;
      if (n > maior) {
        maior = n;
        melhor = sep;
      }
    }
    return melhor;
  }

  /// Lê CSV ou TXT delimitado.
  static LeituraDoArquivo lerCsv(Uint8List bytes) {
    try {
      // `allowMalformed` para não estourar em arquivo salvo em Latin-1
      // com acento — comum em export de sistema antigo. O caractere sai
      // trocado, e o admin vê isso na revisão.
      final texto = utf8.decode(bytes, allowMalformed: true);
      if (texto.trim().isEmpty) {
        return const LeituraDoArquivo(
          pessoas: [],
          cabecalhoReconhecido: {},
          colunasIgnoradas: [],
          erro: 'O arquivo está vazio.',
        );
      }
      // `fieldDelimiter` explícito em vez da autodetecção da lib: o
      // detector daqui está coberto por teste e eu sei o que ele faz com
      // planilha brasileira (`;`). Confiar na detecção da dependência
      // deixaria o caso que mais importa fora do meu controle.
      //
      // `dynamicTyping: false`: número do Legendários é **texto**. Com
      // conversão automática, "007" viraria 7 e deixaria de casar com a
      // lista do Top.
      final linhas = CsvDecoder(
        fieldDelimiter: detectarSeparador(texto),
        dynamicTyping: false,
      ).convert(texto.replaceAll('\r\n', '\n'));
      return _interpretar(linhas);
    } catch (e) {
      return LeituraDoArquivo(
        pessoas: const [],
        cabecalhoReconhecido: const {},
        colunasIgnoradas: const [],
        erro: 'Não foi possível ler o arquivo: $e',
      );
    }
  }

  /// Lê XLSX. **Não lê .xls** (binário do Excel 97-2003).
  static LeituraDoArquivo lerXlsx(Uint8List bytes) {
    try {
      final planilha = Excel.decodeBytes(bytes);
      if (planilha.tables.isEmpty) {
        return const LeituraDoArquivo(
          pessoas: [],
          cabecalhoReconhecido: {},
          colunasIgnoradas: [],
          erro: 'A planilha não tem nenhuma aba.',
        );
      }
      // A PRIMEIRA aba. Se a lista estiver em outra, o admin vê que não
      // achou os nomes e troca a aba de lugar — melhor que varrer todas
      // e misturar dado de abas diferentes.
      final aba = planilha.tables.values.first;
      final linhas = aba.rows
          .map((l) => l.map((c) => c?.value?.toString() ?? '').toList())
          .toList();
      return _interpretar(linhas);
    } catch (e) {
      return LeituraDoArquivo(
        pessoas: const [],
        cabecalhoReconhecido: const {},
        colunasIgnoradas: const [],
        erro:
            'Não foi possível ler a planilha. Se for .xls antigo, '
            'salve como .xlsx e tente de novo. ($e)',
      );
    }
  }

  static LeituraDoArquivo _interpretar(List<List<dynamic>> linhas) {
    // Pula linhas vazias no topo — planilha com título antes do cabeçalho
    // é comum.
    var i = 0;
    while (i < linhas.length &&
        linhas[i].every((c) => c.toString().trim().isEmpty)) {
      i++;
    }
    if (i >= linhas.length) {
      return const LeituraDoArquivo(
        pessoas: [],
        cabecalhoReconhecido: {},
        colunasIgnoradas: [],
        erro: 'O arquivo não tem linhas com conteúdo.',
      );
    }

    final cabecalho = linhas[i].map((c) => c.toString()).toList();
    final campoDaColuna = <int, String>{};
    final reconhecido = <String, String>{};
    final ignoradas = <String>[];

    for (var c = 0; c < cabecalho.length; c++) {
      final campo = _campoDe(cabecalho[c]);
      final titulo = cabecalho[c].trim();
      if (campo != null && !campoDaColuna.containsValue(campo)) {
        campoDaColuna[c] = campo;
        reconhecido[titulo.isEmpty ? 'coluna ${c + 1}' : titulo] = campo;
      } else if (titulo.isNotEmpty) {
        ignoradas.add(titulo);
      }
    }

    if (!campoDaColuna.containsValue('nome')) {
      return LeituraDoArquivo(
        pessoas: const [],
        cabecalhoReconhecido: reconhecido,
        colunasIgnoradas: ignoradas,
        erro:
            'Não achei a coluna de NOME. A primeira linha com conteúdo '
            'tem de ser o cabeçalho, com uma coluna chamada "Nome" '
            '(ou "Nome completo", "Participante").',
      );
    }

    final pessoas = <PessoaImportada>[];
    final numerosVistos = <String, int>{};

    for (var l = i + 1; l < linhas.length; l++) {
      final linha = linhas[l];
      if (linha.every((c) => c.toString().trim().isEmpty)) continue;

      String? valor(String campo) {
        for (final e in campoDaColuna.entries) {
          if (e.value == campo && e.key < linha.length) {
            final v = linha[e.key].toString().trim();
            return v.isEmpty ? null : v;
          }
        }
        return null;
      }

      final p = PessoaImportada(
        linhaNoArquivo: l + 1,
        nome: valor('nome')?.toUpperCase(),
        numero: valor('numero'),
        familia: valor('familia')?.toUpperCase(),
        telefone: valor('telefone'),
        cidade: valor('cidade'),
        estado: valor('estado')?.toUpperCase(),
      );

      final problemas = <String>[];

      if ((p.nome ?? '').isEmpty) {
        problemas.add('sem nome');
      }

      // Número: só dígito, 1 a 12 — a MESMA regra de
      // `AcessoService.regexNumero` e da Edge Function. Divergir faria o
      // importador aceitar o que o autocadastro depois recusa.
      final numero = p.numero;
      if (numero != null) {
        final limpo = numero.replaceAll(RegExp(r'[^0-9]'), '');
        if (limpo.isEmpty) {
          problemas.add('número sem dígito: "$numero"');
          p.numero = null;
        } else if (limpo.length > 12) {
          problemas.add('número com mais de 12 dígitos');
          p.numero = null;
        } else {
          p.numero = limpo;
          final antes = numerosVistos[limpo];
          if (antes != null) {
            problemas.add('número repetido (igual ao da linha $antes)');
          } else {
            numerosVistos[limpo] = l + 1;
          }
        }
      }

      final equipeBruta = valor('equipe');
      if (equipeBruta != null) {
        final e = _equipes[normalizar(equipeBruta).replaceAll(' ', '')];
        if (e == null) {
          problemas.add('equipe não reconhecida: "$equipeBruta"');
        } else {
          p.equipe = e;
        }
      }

      final cargoBruto = valor('cargo');
      if (cargoBruto != null) {
        final c = _cargos[normalizar(cargoBruto).replaceAll(' ', '')];
        if (c == null) {
          problemas.add('cargo não reconhecido: "$cargoBruto"');
        } else {
          p.cargo = c;
        }
      }

      // Cargo sem equipe não tem onde ser aplicado.
      if (p.cargo != null && p.equipe == null) {
        problemas.add('cargo informado sem equipe');
      }

      // UF de 2 letras. Não bloqueia: é dado de cadastro, não de
      // identidade — e bloquear a linha inteira por causa disso faria o
      // admin perder a pessoa.
      final uf = p.estado;
      if (uf != null && uf.length != 2) {
        p.estado = null;
      }

      p.problemas = problemas;
      p.selecionada = p.valida;
      pessoas.add(p);
    }

    return LeituraDoArquivo(
      pessoas: pessoas,
      cabecalhoReconhecido: reconhecido,
      colunasIgnoradas: ignoradas,
    );
  }
}
