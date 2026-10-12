import 'package:flutter/material.dart';

import '../models/top.dart';
import '../services/malha_service.dart';

/// Liga e desliga a troca de mensagens por rádio entre aparelhos perto.
///
/// Fica na tela do chat de equipe, não na barra do Top: é ali que a
/// pessoa percebe que a mensagem não está saindo e é ali que ligar faz
/// sentido.
///
/// ## Por que mostra números, e não só "ligado"
///
/// "Ligado" sem mais nada não diz se está funcionando. Quem está no mato
/// precisa saber **quantos aparelhos estão ao alcance** — zero vizinhos é
/// informação legítima (não tem ninguém perto), e é diferente de estar
/// com o rádio desligado. Sem esse número, os dois estados parecem o
/// mesmo defeito.
class BotaoDaMalha extends StatefulWidget {
  const BotaoDaMalha({super.key, required this.top});

  final Top top;

  @override
  State<BotaoDaMalha> createState() => _BotaoDaMalhaState();
}

class _BotaoDaMalhaState extends State<BotaoDaMalha> {
  bool _mudando = false;

  Future<void> _alternar() async {
    setState(() => _mudando = true);
    final malha = MalhaService.instance;
    if (malha.ligada) {
      await malha.desligar();
    } else {
      await malha.ligar(topId: widget.top.id);
    }
    if (mounted) setState(() => _mudando = false);
  }

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: MalhaService.instance,
      builder: (context, _) {
        final malha = MalhaService.instance;

        if (!malha.disponivelNesteAparelho) {
          // Dizer o motivo em vez de oferecer um botão morto. A pessoa
          // num iPhone precisa saber que o APP funciona — só a malha por
          // rádio não existe ali.
          return const SizedBox.shrink();
        }

        final ligada = malha.ligada;

        return Card(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          color: ligada ? cores.secondaryContainer : null,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      ligada ? Icons.wifi_tethering : Icons.wifi_tethering_off,
                      color: ligada ? cores.primary : cores.outline,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ligada
                                ? 'Rádio entre aparelhos LIGADO'
                                : 'Rádio entre aparelhos',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            ligada
                                // Zero vizinhos NÃO é falha: é não ter
                                // ninguém por perto. Dizer isso evita
                                // que a pessoa fique mexendo achando que
                                // quebrou.
                                ? malha.vizinhos == 0
                                      ? 'Procurando… ninguém por perto ainda'
                                      : '${malha.vizinhos} aparelho(s) ao '
                                            'alcance · '
                                            '${malha.mensagensRecebidas} '
                                            'recebida(s)'
                                : 'Troca mensagens com quem está por perto, '
                                      'sem internet. Gasta bateria.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (_mudando)
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else
                      Switch(
                        value: ligada,
                        onChanged: (_) => _alternar(),
                      ),
                  ],
                ),
                if (malha.erro != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      malha.erro!,
                      style: TextStyle(color: cores.error, fontSize: 12),
                    ),
                  ),
                if (ligada)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      // O aviso que não pode sumir: o que chega por aqui
                      // não passou por autenticação nenhuma.
                      'O que chegar por rádio vem marcado como remetente '
                      'NÃO confirmado — vale como aviso, não como ordem.',
                      style: TextStyle(
                        fontSize: 11,
                        color: cores.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
