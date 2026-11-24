// `Top.colunasSelect` tem de cobrir TODA chave que `Top.fromMap` lê, e
// nenhuma consulta em `tops` pode voltar a usar `select()` pelado.
//
// Por que isto é teste e não convenção, achado na revisão de 24/11/2026:
//
// 1. **`select()` sem lista é `select *`**, e `*` arrastava
//    `access_code_hash` — o hash da senha do Top — para o aparelho de toda
//    conta aprovada. Era o defeito crítico do dia. `fetchMyTops` ganhou
//    lista explícita; `AdminService.createTop` ficou com `select()` pelado e
//    só não quebrou porque o `revoke` daquela coluna ainda não entrou. Duas
//    consultas na mesma tabela divergiram em um dia.
//
// 2. **Esquecer uma coluna nova na lista falha ABERTO.** `fromMap` usa
//    `map['autocadastro_liberado'] as bool? ?? true` — o default é `true`
//    de propósito (consulta antiga não deve FECHAR um Top que está aberto).
//    A consequência é que uma coluna fora da lista faz o app afirmar que o
//    cadastro está aberto sem ter perguntado ao servidor. Silencioso.
//
// O teste lê o CÓDIGO-FONTE, no estilo de
// `test/cadastro_manda_a_ficha_inteira_test.dart`: teste de comportamento
// não pegaria nenhum dos dois, porque os dois produzem um objeto `Top`
// perfeitamente válido — só com um campo mentindo.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:legendario_connect/models/top.dart';

void main() {
  final raizDoProjeto = Directory.current.path;
  String fonte(String caminho) =>
      File('$raizDoProjeto/$caminho').readAsStringSync();

  test('colunasSelect cobre toda chave que fromMap lê', () {
    final modelo = fonte('lib/models/top.dart');

    // Só o corpo de `fromMap`: a constante `colunasSelect` está no mesmo
    // arquivo e casaria com o próprio padrão de busca.
    final inicio = modelo.indexOf('factory Top.fromMap');
    expect(inicio, greaterThan(0), reason: 'fromMap mudou de nome?');
    final corpo = modelo.substring(inicio);

    final lidas = RegExp(r"map\['([a-z_]+)'\]")
        .allMatches(corpo)
        .map((m) => m.group(1)!)
        .toSet();

    expect(
      lidas,
      isNotEmpty,
      reason: 'o teste não achou nenhuma chave — o padrão de busca quebrou, '
          'e um teste que não mede nada é pior que nenhum teste',
    );

    final naLista = Top.colunasSelect
        .split(',')
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toSet();

    final faltando = lidas.difference(naLista);
    expect(
      faltando,
      isEmpty,
      reason: 'fromMap lê ${faltando.join(', ')} e colunasSelect não pede. '
          'O PostgREST não devolve a coluna, fromMap cai no default — e o '
          'default de autocadastro_liberado é TRUE, ou seja, falha aberta',
    );
  });

  test('colunasSelect não pede coluna que fromMap não lê', () {
    // A outra metade: lista inflada traz dado que ninguém usa, e foi
    // exatamente assim que o hash da senha viajou para 216 aparelhos.
    final modelo = fonte('lib/models/top.dart');
    final corpo = modelo.substring(modelo.indexOf('factory Top.fromMap'));
    final lidas = RegExp(r"map\['([a-z_]+)'\]")
        .allMatches(corpo)
        .map((m) => m.group(1)!)
        .toSet();
    final naLista = Top.colunasSelect
        .split(',')
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toSet();

    expect(
      naLista.difference(lidas),
      isEmpty,
      reason: 'colunasSelect pede ${naLista.difference(lidas).join(', ')} '
          'que fromMap não lê',
    );
  });

  test('o hash da senha do Top NUNCA está na lista', () {
    // Trava explícita, e não só consequência do teste acima: se alguém
    // acrescentar o campo ao model, os dois primeiros testes passariam.
    for (final proibida in const [
      'access_code_hash',
      'access_code_set_at',
      'access_code_set_by',
    ]) {
      expect(
        Top.colunasSelect.contains(proibida),
        isFalse,
        reason: '$proibida vive em `top_access_codes` desde 24/11/2026, '
            'fora de `tops`, porque `tops` é legível por toda conta '
            'aprovada e RLS é por LINHA, não por coluna',
      );
    }
  });

  test('nenhuma consulta em tops usa select() pelado', () {
    // Varre os services. `from('tops')` seguido de `.select()` sem
    // argumento é `select *` — o caminho pelo qual o hash vazava, e o que
    // vai quebrar a criação de Top quando o `revoke` da coluna entrar.
    final arquivos = Directory('$raizDoProjeto/lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));

    final culpados = <String>[];
    for (final f in arquivos) {
      final texto = f.readAsStringSync();
      for (final m in RegExp(r"from\('tops'\)").allMatches(texto)) {
        // Olha a janela depois da chamada, até o `;` que fecha a expressão.
        final fim = texto.indexOf(';', m.end);
        final trecho = texto.substring(m.end, fim == -1 ? texto.length : fim);
        if (trecho.contains('.select()')) {
          final linha = texto.substring(0, m.start).split('\n').length;
          culpados.add('${f.path.split('hakuna3colinas').last}:$linha');
        }
      }
    }

    expect(
      culpados,
      isEmpty,
      reason: 'select() pelado em tops: ${culpados.join(', ')}. '
          'Use Top.colunasSelect',
    );
  });

  test('o próprio varredor funciona', () {
    // Auto-teste: o `CLAUDE.md` registra que "guarda que não é verificada é
    // pior que guarda nenhuma" — foi um varredor que media zero que deixou
    // uma oitava ação passar batida na AppBar.
    const comDefeito = "final r = await _c.from('tops').select().order('x');";
    final fim = comDefeito.indexOf(
      ';',
      comDefeito.indexOf("from('tops')") + "from('tops')".length,
    );
    expect(
      comDefeito
          .substring(
            comDefeito.indexOf("from('tops')") + "from('tops')".length,
            fim,
          )
          .contains('.select()'),
      isTrue,
      reason: 'o varredor não reconhece o caso que existia de verdade',
    );
  });
}
