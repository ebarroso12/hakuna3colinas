// O cadastro tem de MANDAR o que a tela pede.
//
// Em 23/11/2026 o campo "Família" estava na tela de cadastro desde sempre,
// a pessoa preenchia, e o dado era descartado **antes de sair do
// aparelho**: o mapa `ficha:` enviado a `acesso/cadastrar` tinha 18 chaves
// e `familia` não era uma delas. Achado cadastrando num Top sem lista
// prévia, onde esse é o único jeito de a família ser registrada — não há
// planilha de onde ela venha. E é por família que a lista de participantes
// busca e agrupa.
//
// Campo que a tela mostra e o app joga fora é pior que campo ausente: a
// pessoa digita, vê salvar com sucesso e o dado não existe. Ninguém
// descobre até alguém procurar por família e não achar.
//
// Este teste lê o CÓDIGO-FONTE da tela, como `toda_tela_tem_saida_test` e
// `appbar_cabe_no_celular_test` fazem. Teste de widget não pegaria: a tela
// renderiza o campo certo, o defeito está no envio.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final fonte = File(
    'lib/screens/cadastro_legendario_screen.dart',
  ).readAsStringSync();

  /// O trecho entre `ficha: {` e o `}` que o fecha — é só ali que importa.
  String mapaDaFicha() {
    final inicio = fonte.indexOf('ficha: {');
    expect(
      inicio,
      isNot(-1),
      reason: 'não achei o mapa `ficha: {` no cadastro; se ele foi '
          'renomeado, conserte este teste em vez de apagá-lo',
    );
    var nivel = 0;
    for (var i = inicio + 'ficha: '.length; i < fonte.length; i++) {
      if (fonte[i] == '{') nivel++;
      if (fonte[i] == '}') {
        nivel--;
        if (nivel == 0) return fonte.substring(inicio, i + 1);
      }
    }
    fail('o mapa `ficha:` não fecha');
  }

  /// Campos que a tela mostra E a tabela `top_participants` guarda. Cada um
  /// é um dado que a pessoa digita achando que está salvando.
  const obrigatorios = <String, String>{
    'full_name': 'Nome completo',
    'familia': 'Família',
    'nickname': 'Apelido',
    'phone': 'Telefone',
    'birth_date': 'Data de nascimento',
    'cidade': 'Cidade',
    'estado': 'UF',
    'emergency_contact': 'Contato de emergência',
    'height_cm': 'Altura',
    'weight_kg': 'Peso',
    'blood_type': 'Tipo sanguíneo',
    'biotipo': 'Biotipo',
    'cirurgias': 'Cirurgias',
    'atividade_fisica_semanal': 'Atividade física semanal',
    'comorbidades': 'Comorbidades',
    'alergias': 'Alergias',
    'plano_saude': 'Plano de saúde',
    'medicamentos_continuos': 'Medicamentos de uso contínuo',
    'restricoes_fisicas': 'Restrições físicas',
  };

  test('o cadastro envia todos os campos que a tela pede', () {
    final mapa = mapaDaFicha();
    final faltando = <String>[];
    obrigatorios.forEach((chave, rotulo) {
      if (!mapa.contains("'$chave':")) faltando.add('$rotulo (`$chave`)');
    });
    expect(
      faltando,
      isEmpty,
      reason:
          'estes campos aparecem na tela de cadastro e NÃO são enviados — '
          'a pessoa preenche e o dado é descartado antes de sair do '
          'aparelho:\n  ${faltando.join('\n  ')}',
    );
  });

  test('a família entra, e foi ela que faltava', () {
    // Caso específico, com o motivo escrito: num Top sem lista prévia
    // (`tops.aceitar_fora_da_lista`) a ficha nasce do que a pessoa digita,
    // e a família não vem de parte nenhuma além deste campo.
    expect(mapaDaFicha(), contains("'familia':"));
  });

  test('o controlador da família existe na tela', () {
    // Se alguém remover o campo da tela, o teste de cima passaria por
    // vacuidade — o mapa continuaria sem `familia` só porque a tela não
    // pede mais. Esta é a outra metade da guarda.
    expect(fonte, contains('_familia'));
    expect(fonte, contains("labelText: 'Família'"));
  });
}
