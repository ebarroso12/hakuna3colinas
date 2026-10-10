import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/hakuna_position.dart';
import '../models/profile.dart';
import '../models/top.dart';
import '../services/supabase_service.dart';
import '../widgets/app_logo.dart';

/// Mapa com a posição dos Hakunas do Top, em tempo real.
///
/// Era a maior lacuna do app: o GPS já gravava posições e o StatsService já
/// calculava distância, mas **nada desenhava ninguém num mapa** — justo o
/// que o README vende como funcionalidade principal.
///
/// Usa OpenStreetMap via `flutter_map` em vez do Google Maps de propósito:
/// não exige chave de API nem conta de faturamento, e numa trilha o que
/// importa é ver o ponto, não a riqueza do mapa.
class MapaTopScreen extends StatefulWidget {
  const MapaTopScreen({
    super.key,
    required this.top,
    this.hakunaProfiles = const {},
  });

  final Top top;
  final Map<String, Profile> hakunaProfiles;

  @override
  State<MapaTopScreen> createState() => _MapaTopScreenState();
}

class _MapaTopScreenState extends State<MapaTopScreen> {
  final _mapController = MapController();

  StreamSubscription<List<HakunaPosition>>? _sub;
  List<HakunaPosition> _posicoes = [];
  bool _primeiraCarga = true;
  String? _erro;

  /// Quando ligado, o mapa reenquadra sozinho a cada atualização. Desliga
  /// assim que o usuário arrasta — senão o mapa "pula" de volta enquanto
  /// ele tenta olhar outro ponto.
  bool _seguirTodos = true;

  @override
  void initState() {
    super.initState();
    _ouvirPosicoes();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _ouvirPosicoes() {
    _sub = SupabaseService.instance
        .watchTopPositions(widget.top.id)
        .listen(
          (lista) {
            if (!mounted) return;
            setState(() {
              _posicoes = _ultimaDeCada(lista);
              _primeiraCarga = false;
              _erro = null;
            });
            if (_seguirTodos) _enquadrarTodos();
          },
          onError: (Object e) {
            if (!mounted) return;
            setState(() {
              _erro = '$e';
              _primeiraCarga = false;
            });
          },
        );
  }

  /// Só a posição mais recente de cada Hakuna.
  ///
  /// A tabela guarda a trilha inteira; desenhar todos os pontos encheria o
  /// mapa de rastro e esconderia onde cada um está AGORA, que é o que
  /// importa num atendimento.
  List<HakunaPosition> _ultimaDeCada(List<HakunaPosition> todas) {
    final porPessoa = <String, HakunaPosition>{};
    for (final p in todas) {
      final atual = porPessoa[p.profileId];
      if (atual == null || p.recordedAt.isAfter(atual.recordedAt)) {
        porPessoa[p.profileId] = p;
      }
    }
    return porPessoa.values.toList();
  }

  void _enquadrarTodos() {
    if (_posicoes.isEmpty) return;
    if (_posicoes.length == 1) {
      _mapController.move(
        LatLng(_posicoes.first.latitude, _posicoes.first.longitude),
        15,
      );
      return;
    }
    final pontos = _posicoes
        .map((p) => LatLng(p.latitude, p.longitude))
        .toList();
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: pontos,
        padding: const EdgeInsets.all(60),
        maxZoom: 16,
      ),
    );
  }

  String _nomeDe(String profileId) =>
      widget.hakunaProfiles[profileId]?.fullName ??
      'Hakuna ${profileId.substring(0, 6)}';

  /// Há quanto tempo a posição foi registrada. Em campo isso importa mais
  /// que a hora exata: um ponto de 40 minutos atrás não diz onde a pessoa
  /// está agora.
  String _idade(DateTime quando) {
    final minutos = DateTime.now().difference(quando).inMinutes;
    if (minutos < 1) return 'agora';
    if (minutos < 60) return 'há $minutos min';
    final horas = minutos ~/ 60;
    return 'há ${horas}h';
  }

  bool _desatualizada(DateTime quando) =>
      DateTime.now().difference(quando).inMinutes > 15;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Mapa'),
            Text(
              '${_posicoes.length} Hakuna(s) com posição',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _seguirTodos ? Icons.my_location : Icons.location_searching,
            ),
            tooltip: _seguirTodos
                ? 'Enquadrando todos automaticamente'
                : 'Enquadrar todos agora',
            onPressed: () {
              setState(() => _seguirTodos = true);
              _enquadrarTodos();
            },
          ),
          const AppLogoTrailing(),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _posicoes.isEmpty
                  ? const LatLng(-20.5386, -47.4006) // Franca-SP
                  : LatLng(_posicoes.first.latitude, _posicoes.first.longitude),
              initialZoom: 13,
              // Arrastar o mapa desliga o reenquadramento automático.
              onPositionChanged: (_, temGesto) {
                if (temGesto && _seguirTodos) {
                  setState(() => _seguirTodos = false);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.legendarios.hakuna_connect',
                // Sem internet os tiles não baixam, mas os marcadores
                // continuam desenhados sobre o fundo vazio — a posição
                // relativa entre as pessoas ainda é legível.
              ),
              MarkerLayer(
                markers: [
                  for (final p in _posicoes)
                    Marker(
                      point: LatLng(p.latitude, p.longitude),
                      width: 120,
                      height: 64,
                      child: _MarcadorHakuna(
                        nome: _nomeDe(p.profileId),
                        idade: _idade(p.recordedAt),
                        desatualizada: _desatualizada(p.recordedAt),
                      ),
                    ),
                ],
              ),
            ],
          ),
          if (_primeiraCarga) const Center(child: CircularProgressIndicator()),
          if (!_primeiraCarga && _posicoes.isEmpty && _erro == null)
            _Aviso(
              icone: Icons.person_search,
              texto:
                  'Nenhum Hakuna compartilhando posição agora.\n'
                  'Peça para ativarem "Compartilhar minha posição" no Top.',
            ),
          if (_erro != null)
            _Aviso(
              icone: Icons.wifi_off,
              texto:
                  'Sem conexão com o tempo real.\n'
                  'As posições param de atualizar até o sinal voltar.',
            ),
          // Atribuição do OpenStreetMap é exigida pela licença de uso.
          const Positioned(bottom: 4, right: 6, child: _Atribuicao()),
        ],
      ),
    );
  }
}

class _MarcadorHakuna extends StatelessWidget {
  const _MarcadorHakuna({
    required this.nome,
    required this.idade,
    required this.desatualizada,
  });

  final String nome;
  final String idade;

  /// Posição antiga fica acinzentada. Marcador vivo e marcador parado há
  /// uma hora não podem parecer a mesma coisa.
  final bool desatualizada;

  @override
  Widget build(BuildContext context) {
    final cor = desatualizada ? Colors.grey : const Color(0xFFD84315);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: cor),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                nome.split(' ').first,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: cor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(idade, style: TextStyle(fontSize: 9, color: cor)),
            ],
          ),
        ),
        Icon(Icons.location_on, color: cor, size: 32),
      ],
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.icone, required this.texto});

  final IconData icone;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        margin: const EdgeInsets.all(32),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icone, size: 40),
              const SizedBox(height: 12),
              Text(texto, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class _Atribuicao extends StatelessWidget {
  const _Atribuicao();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      color: Colors.white70,
      child: const Text('© OpenStreetMap', style: TextStyle(fontSize: 10)),
    );
  }
}
