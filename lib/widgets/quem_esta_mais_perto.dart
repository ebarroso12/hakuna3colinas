import 'package:flutter/material.dart';

import '../models/hakuna_position.dart';
import '../models/profile.dart';
import '../services/proximidade_service.dart';
import '../services/supabase_service.dart';

/// Lista os Hakunas ordenados pela distância até um ponto.
///
/// Abre a partir do alarme: alguém disparou com coordenada e a pergunta
/// imediata é quem vai. Antes essa pergunta não tinha resposta no app —
/// GPS de um lado, coordenada do alarme do outro, nada cruzando os dois.
///
/// Mostra **distância e idade da posição juntas**, de propósito. Em linha
/// reta e com um ponto de 40 minutos atrás, "250 m" é ficção: a pessoa
/// pode ter andado 2 km desde então. Quem decide precisa dos dois números
/// para não mandar o Hakuna errado.
class QuemEstaMaisPerto extends StatelessWidget {
  const QuemEstaMaisPerto({
    super.key,
    required this.topId,
    required this.latitude,
    required this.longitude,
  });

  final String topId;
  final double latitude;
  final double longitude;

  static Future<void> abrir(
    BuildContext context, {
    required String topId,
    required double latitude,
    required double longitude,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => QuemEstaMaisPerto(
        topId: topId,
        latitude: latitude,
        longitude: longitude,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Quem está mais perto',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              'Distância em linha reta, não de caminhada — a trilha é '
              'sempre mais longa. Confira a hora da posição.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Flexible(
              child: FutureBuilder<Map<String, Profile>>(
                future: SupabaseService.instance.fetchHakunaProfiles(topId),
                builder: (context, perfis) {
                  return StreamBuilder<List<HakunaPosition>>(
                    stream: SupabaseService.instance.watchTopPositions(topId),
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final proximos = ProximidadeService.maisProximos(
                        latitude: latitude,
                        longitude: longitude,
                        posicoes: snap.data ?? const [],
                      );
                      if (proximos.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                            'Nenhum Hakuna com posição recente (últimas 2 '
                            'horas). Sem rede, ou ninguém com o '
                            'rastreamento ligado.',
                            textAlign: TextAlign.center,
                          ),
                        );
                      }
                      return ListView.builder(
                        shrinkWrap: true,
                        itemCount: proximos.length,
                        itemBuilder: (context, i) {
                          final p = proximos[i];
                          final nome =
                              perfis.data?[p.profileId]?.displayLabel ??
                              'Hakuna';
                          return ListTile(
                            leading: CircleAvatar(child: Text('${i + 1}')),
                            title: Text(nome),
                            subtitle: Text(
                              'posição de ${p.idadeFormatada}',
                            ),
                            trailing: Text(
                              p.distanciaFormatada,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
