import 'package:flutter/material.dart';

import '../models/top_alert.dart';
import '../services/alarme_service.dart';
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
                  Text(
                    'ALARME — $hora',
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
                  if (alarme.latitude != null && alarme.longitude != null)
                    // Toque abre quem está mais perto do ponto do alarme.
                    // É a pergunta que vem logo depois de "houve um
                    // alarme" e que o app não respondia.
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => QuemEstaMaisPerto.abrir(
                        topId: alarme.topId,
                        latitude: alarme.latitude!,
                        longitude: alarme.longitude!,
                      ),
                      icon: const Icon(Icons.near_me, size: 16),
                      label: const Text('Quem está mais perto'),
                    ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, color: Colors.white),
              tooltip: 'Dispensar',
              onPressed: () => AlarmeService.instance.descartar(alarme.id),
            ),
          ],
        ),
      ),
    );
  }
}
