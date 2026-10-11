import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../main.dart';
import '../models/top_alert.dart';
import 'quem_esta_mais_perto.dart';

/// ONDE foi o acidente, num mapa, para quem recebeu o alarme.
///
/// Decisão do dono em 11/10/2026: "se alguma pessoa apertar emergência
/// todos devem ver o lugar via GPS e quem está chamando". A faixa de
/// alarme já recebia `latitude`/`longitude` desde sempre e só oferecia
/// "quem está mais perto" — que responde QUEM vai, não ONDE é. Quem está
/// se deslocando precisa do ponto.
///
/// **Esta tela não depende de `pode_ver_mapa()`, e isso é deliberado.**
/// O ponto vem de `top_alerts.latitude/longitude`, não de
/// `hakuna_positions`: é uma coordenada única, do instante da emergência,
/// publicada por quem pediu socorro. A distinção que o projeto já faz
/// entre alarme e mapa continua de pé — alarme é emergência e é aberto;
/// a trilha contínua de 200 pessoas segue restrita, porque é vigilância.
///
/// Por isso o mapa aqui mostra **um marcador só** e nunca a posição dos
/// outros. Quem tem acesso ao mapa do Top vê os dois pela tela de mapa.
class LugarDoAlarme extends StatelessWidget {
  const LugarDoAlarme({super.key, required this.alarme});

  final TopAlert alarme;

  /// Abre a tela.
  ///
  /// Usa o `Navigator` do app pela chave global, e não o contexto de quem
  /// chamou: o chamador é a faixa de alarme, que vive no
  /// `MaterialApp.builder` — ACIMA do Navigator. `Navigator.of` dali não
  /// acha nada e estouraria com "No Navigator widget found", que foi um
  /// defeito real da v1.0.31.
  static Future<void> abrir(TopAlert alarme) {
    if (!alarme.temPosicao) return Future<void>.value();
    final contexto = navegadorDoApp.currentContext;
    if (contexto == null) return Future<void>.value();
    return Navigator.of(contexto).push(
      MaterialPageRoute<void>(builder: (_) => LugarDoAlarme(alarme: alarme)),
    );
  }

  /// Coordenada em texto, para quem vai digitar num GPS de mão ou ditar
  /// no rádio.
  ///
  /// Seis casas: ~11 cm. Mais que suficiente e menos que o ruído do
  /// próprio GPS de celular, que erra metros.
  String get _coordenada =>
      '${alarme.latitude!.toStringAsFixed(6)}, '
      '${alarme.longitude!.toStringAsFixed(6)}';

  @override
  Widget build(BuildContext context) {
    final ponto = LatLng(alarme.latitude!, alarme.longitude!);
    final quando = alarme.createdAt.toLocal();
    final hora =
        '${quando.hour.toString().padLeft(2, '0')}:'
        '${quando.minute.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.red.shade700,
        foregroundColor: Colors.white,
        title: const Text('Lugar do alarme'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: 'Copiar coordenada',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _coordenada));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Coordenada copiada.')),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Quem chamou e o que disse, acima do mapa: é o que decide se
          // alguém sai correndo ou pega a maca.
          Container(
            width: double.infinity,
            color: Colors.red.shade700,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${alarme.quemChama} · $hora',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                if (!alarme.temNome)
                  const Text(
                    'O nome não veio no alarme. Pergunte no rádio.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                const SizedBox(height: 4),
                Text(
                  alarme.message?.trim().isNotEmpty == true
                      ? alarme.message!
                      : 'Sem descrição.',
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 6),
                Text(
                  _coordenada,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: FlutterMap(
              options: MapOptions(initialCenter: ponto, initialZoom: 16),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.legendarios.hakuna_connect',
                  // Sem internet os tiles não baixam e o fundo fica
                  // cinza, mas o marcador e a coordenada continuam ali —
                  // e a coordenada é o que se dita no rádio. Era o
                  // mínimo que esta tela tinha de garantir no mato.
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: ponto,
                      width: 44,
                      height: 44,
                      child: const Icon(
                        Icons.warning_amber,
                        color: Colors.red,
                        size: 44,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: OutlinedButton.icon(
                onPressed: () => QuemEstaMaisPerto.abrir(
                  topId: alarme.topId,
                  latitude: alarme.latitude!,
                  longitude: alarme.longitude!,
                ),
                icon: const Icon(Icons.near_me),
                label: const Text('Quem está mais perto daqui'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
