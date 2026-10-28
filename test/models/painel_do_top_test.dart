import 'package:flutter_test/flutter_test.dart';
import 'package:legendario_connect/models/painel_do_top.dart';
import 'package:legendario_connect/models/team.dart';

/// Resposta REAL de `painel_do_top` para o Top 1782, chamada como admin
/// em 28/10/2026. Se a função mudar uma chave, este teste é o que avisa —
/// o `fromMap` devolveria zero calado e o painel mentiria.
const _producao = {
  'fichas': 216,
  'alarmes': 2,
  'equipes': <Object>[],
  'afericoes': 0,
  'gerado_em': '2026-10-28T00:32:22.308707+00:00',
  'alarmes_24h': 0,
  'atendimentos': 0,
  'fichas_teste': 1,
  'mensagens_24h': 0,
  'ultimo_alarme': {
    'em': '2026-10-12T14:07:50.177424+00:00',
    'nome': 'João vitor',
    'mensagem': 'oi',
  },
  'mensagens_total': 0,
  'atendimentos_24h': 0,
  'chat_clinico_24h': 0,
  'fichas_com_conta': 1,
  'contas_aguardando': 0,
  'fichas_sem_numero': 144,
  'hakunas_liberados': 2,
  'pedidos_pendentes': 0,
  'atendimentos_abertos': 0,
  'fichas_sem_nascimento': 1,
  'pessoas_com_vital_critico': 0,
  'com_posicao_na_ultima_hora': 0,
  'compartilhando_posicao_agora': 0,
};

void main() {
  test('lê a resposta real do banco sem perder nenhum número', () {
    final p = PainelDoTop.fromMap(_producao);
    expect(p.fichas, 216);
    expect(p.fichasComConta, 1);
    expect(p.fichasSemConta, 215);
    expect(p.fichasSemNumero, 144);
    expect(p.hakunasLiberados, 2);
    expect(p.alarmes, 2);
    expect(p.ultimoAlarmeNome, 'João vitor');
    expect(p.ultimoAlarmeEm, isNotNull);
    expect(p.equipes, isEmpty);
  });

  test('Top sem fichas não divide por zero', () {
    final p = PainelDoTop.fromMap({
      ..._producao,
      'fichas': 0,
      'fichas_com_conta': 0,
    });
    expect(p.adesao, 0);
  });

  test('sem alarme nenhum, o último alarme é nulo — não "Alguém do Top"', () {
    final p = PainelDoTop.fromMap({..._producao, 'ultimo_alarme': null});
    expect(p.ultimoAlarmeEm, isNull);
    expect(p.ultimoAlarmeNome, isNull);
  });

  test('equipe: conta quem falta liberar e reconhece a chave do enum', () {
    final p = PainelDoTop.fromMap({
      ..._producao,
      'equipes': [
        {
          'equipe': 'seguranca',
          'membros': 5,
          'liberados': 3,
          'coordenacao': 1,
          'mensagens_24h': 12,
        },
      ],
    });
    final e = p.equipes.single;
    expect(e.equipe, TeamKey.seguranca);
    expect(e.faltaLiberar, 2);
    expect(e.mensagens24h, 12);
  });

  test('número que chega como texto ainda é lido', () {
    final p = PainelDoTop.fromMap({..._producao, 'fichas': '216'});
    expect(p.fichas, 216);
  });
}
