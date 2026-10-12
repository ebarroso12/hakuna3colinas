import 'package:flutter/material.dart';

import '../models/top_alert.dart';
import '../services/alarme_service.dart';
import 'lugar_do_alarme.dart';
import 'quem_esta_mais_perto.dart';

/// Faixa vermelha de alarme, por cima de qualquer tela do app.
///
/// Entra em `MaterialApp.builder`, acima do `Navigator`, e por isso
/// aparece onde o Hakuna estiver — lista de participantes, chat, ficha,
/// formulário de atendimento. Antes a faixa morava dentro da tela de
/// detalhe do Top, e quem não estivesse exatamente nela não recebia nada.
///
/// Fica abaixo de diálogos e do teclado por desenho: um alarme não deve
/// cobrir o campo que alguém está preenchendo no meio de um atendimento.
/// Ele chega com som e vibração (ver [AlarmeService]), então não depende
/// de estar visível para ser notado.
class FaixaDeAlarme extends StatelessWidget {
  const FaixaDeAlarme({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            // `IgnorePointer` não serve: a faixa tem botão de fechar.
            child: ListenableBuilder(
              listenable: AlarmeService.instance,
              builder: (context, _) {
                final alarmes = AlarmeService.instance.ativos;
                if (alarmes.isEmpty) return const SizedBox.shrink();
                return Column(
                  children: alarmes.map(_CartaoDeAlarme.new).toList(),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Estilo compartilhado dos botões da faixa — compacto, porque a faixa
/// cobre a tela de quem pode estar no meio de um atendimento.
final _estiloDoBotao = TextButton.styleFrom(
  padding: EdgeInsets.zero,
  minimumSize: const Size(0, 32),
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
  foregroundColor: Colors.white,
);

class _CartaoDeAlarme extends StatelessWidget {
  const _CartaoDeAlarme(this.alarme);

  final TopAlert alarme;

  @override
  Widget build(BuildContext context) {
    final quando = TimeOfDay.fromDateTime(alarme.createdAt.toLocal());
    final hora =
        '${quando.hour.toString().padLeft(2, '0')}:'
        '${quando.minute.toString().padLeft(2, '0')}';

    return Material(
      // `Material` explícito: a faixa vive acima do Navigator, onde não
      // existe Scaffold para dar superfície, e sem isto o texto sai sem
      // estilo e o InkWell não pinta.
      color: Colors.red.shade700,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.warning_amber, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // QUEM ESTÁ CHAMANDO vem na primeira linha, junto da
                  // hora. Decisão do dono em 11/10/2026. Antes a faixa
                  // dizia só "ALARME — 14:32": numa trilha com 200
                  // pessoas, saber que houve emergência sem saber de quem
                  // não diz a quem correr. O nome viaja dentro do alarme
                  // porque `profiles` é fechada para quem recebe.
                  Text(
                    'ALARME — ${alarme.quemChama} · $hora',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    alarme.message?.trim().isNotEmpty == true
                        ? alarme.message!
                        : 'Sem descrição. Procure quem disparou.',
                    style: const TextStyle(color: Colors.white),
                  ),
                  // ALARME QUE CHEGOU PELO RADIO NÃO TEM AUTORIA.
                  //
                  // Veio de aparelho ao alcance, sem passar por servidor
                  // nenhum, e no rádio não há autenticação: qualquer
                  // aparelho pode afirmar o que quiser em nome de quem
                  // quiser. Esconder essa diferença seria pior que não ter
                  // a funcionalidade — um alarme forjado move 200 pessoas.
                  //
                  // O texto não manda ignorar: é pedido de socorro, e
                  // socorro falso custa menos que socorro perdido. Manda
                  // CONFERIR, que é a ação certa.
                  if (!alarme.confirmado)
                    const Padding(
                      padding: EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Icon(
                            Icons.wifi_tethering,
                            size: 14,
                            color: Colors.white70,
                          ),
                          SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Chegou por rádio, de um aparelho perto — remetente NÃO confirmado. Confirme por voz.',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (alarme.temPosicao)
                    // Duas perguntas diferentes, dois botões.
                    //
                    // "Ver o lugar" responde ONDE — é o GPS do acidente, o
                    // que o dono pediu, e o único que serve a quem vai se
                    // deslocar. "Quem está mais perto" responde QUEM pode
                    // chegar primeiro, e depende de haver gente publicando
                    // posição.
                    //
                    // `Wrap` e não `Row`: em 320 dp os dois rótulos não
                    // cabem na mesma linha, e `Row` estoura cortando o
                    // segundo botão em silêncio.
                    Wrap(
                      spacing: 4,
                      children: [
                        TextButton.icon(
                          style: _estiloDoBotao,
                          onPressed: () => LugarDoAlarme.abrir(alarme),
                          icon: const Icon(Icons.place, size: 16),
                          label: const Text('Ver o lugar'),
                        ),
                        TextButton.icon(
                          style: _estiloDoBotao,
                          onPressed: () => QuemEstaMaisPerto.abrir(
                            topId: alarme.topId,
                            latitude: alarme.latitude!,
                            longitude: alarme.longitude!,
                          ),
                          icon: const Icon(Icons.near_me, size: 16),
                          label: const Text('Quem está mais perto'),
                        ),
                      ],
                    )
                  else
                    // Alarme sem GPS não é raro: o disparo segue mesmo se
                    // o `getCurrentPosition` falhar, e falha bastante
                    // debaixo de mata fechada. Dizer isso é melhor que
                    // deixar a pessoa procurando o botão que não existe.
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Text(
                        'Sem posição de GPS neste alarme — use o rádio.',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: 'Dispensar',
              onPressed: () =>
                  AlarmeService.instance.descartar(alarme.chave),
            ),
          ],
        ),
      ),
    );
  }
}
