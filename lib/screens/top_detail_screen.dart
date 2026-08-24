import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/hakuna_position.dart';
import '../models/profile.dart';
import '../models/top.dart';
import '../models/top_alert.dart';
import '../services/location_service.dart';
import '../services/nfc_service.dart';
import '../services/stats_service.dart';
import '../services/supabase_service.dart';
import '../widgets/app_logo.dart';
import 'participants_screen.dart';
import 'top_chat_screen.dart';
import 'top_senderistas_screen.dart';

class TopDetailScreen extends StatefulWidget {
  const TopDetailScreen({super.key, required this.top});

  final Top top;

  @override
  State<TopDetailScreen> createState() => _TopDetailScreenState();
}

class _TopDetailScreenState extends State<TopDetailScreen> {
  Profile? _myProfile;
  Map<String, Profile> _hakunaProfiles = {};
  bool _tracking = false;
  String? _nfcMessage;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadHakunaProfiles();
  }

  bool _profileLoadFailed = false;

  Future<void> _loadProfile() async {
    try {
      final profile = await SupabaseService.instance.fetchMyProfile();
      if (mounted) setState(() => _myProfile = profile);
    } catch (_) {
      if (mounted) setState(() => _profileLoadFailed = true);
    }
  }

  /// Nomes + número do Legendários dos Hakunas do Top, pra identificar quem
  /// é quem na lista de posições. Falha aqui não é crítica — a lista de
  /// posições cai de volta pro id cru, então só tenta uma vez.
  Future<void> _loadHakunaProfiles() async {
    try {
      final profiles = await SupabaseService.instance.fetchHakunaProfiles(
        widget.top.id,
      );
      if (mounted) setState(() => _hakunaProfiles = profiles);
    } catch (_) {
      // segue sem os nomes; a lista mostra o id cru como fallback
    }
  }

  Future<void> _toggleTracking() async {
    if (_tracking) {
      await LocationService.instance.stopTracking();
      if (!mounted) return;
      setState(() => _tracking = false);
      return;
    }
    try {
      await LocationService.instance.startTracking(
        widget.top.id,
        // Erros que chegam DEPOIS que o rastreamento já começou (GPS
        // desligado, permissão revogada, sessão expirada) caem aqui, não
        // no catch abaixo — o LocationService já para o rastreamento.
        onError: (error) {
          if (!mounted) return;
          setState(() => _tracking = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Rastreamento interrompido: $error')),
          );
        },
      );
      if (!mounted) return;
      setState(() => _tracking = true);
    } catch (e) {
      // Duas causas bem diferentes pro mesmo erro: GPS desligado no sistema
      // (resolve em Configurações > Localização) ou permissão do app negada
      // (resolve em Configurações > Apps > Hakuna Connect). Cada uma abre
      // uma tela do Android diferente — misturar as duas confunde o usuário.
      final serviceDisabled = await LocationService.instance
          .isLocationServiceDisabled();
      if (!mounted) return;
      if (serviceDisabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Localização (GPS) está desligada no aparelho. Ative para compartilhar sua posição.',
            ),
            action: SnackBarAction(
              label: 'Abrir',
              onPressed: Geolocator.openLocationSettings,
            ),
          ),
        );
        return;
      }
      final deniedForever = await LocationService.instance
          .isPermissionDeniedForever();
      if (!mounted) return;
      if (deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Permissão de localização negada. Abra as Configurações do app para liberar.',
            ),
            action: SnackBarAction(
              label: 'Abrir',
              onPressed: Geolocator.openAppSettings,
            ),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível iniciar o rastreamento: $e')),
      );
    }
  }

  /// Dispara o sinal de alarme (acidente/atendimento crítico) pro Top. Pede
  /// confirmação — é uma ação séria que avisa todos os Hakunas liberados —
  /// e anexa a posição atual quando disponível, pra ajudar a localizar
  /// quem precisa de ajuda.
  Future<void> _sendAlert() async {
    final messageController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Disparar sinal de alarme?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Avisa todos os Hakunas liberados neste Top agora. Use só em acidente ou atendimento crítico.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: messageController,
              decoration: const InputDecoration(
                labelText: 'O que está acontecendo? (opcional)',
              ),
              minLines: 1,
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Disparar alarme'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    double? lat;
    double? lng;
    try {
      final position = await Geolocator.getCurrentPosition();
      lat = position.latitude;
      lng = position.longitude;
    } catch (_) {
      // segue sem posição — o alarme em si é mais importante que a localização
    }

    try {
      await SupabaseService.instance.sendTopAlert(
        topId: widget.top.id,
        message: messageController.text.trim().isEmpty
            ? null
            : messageController.text.trim(),
        latitude: lat,
        longitude: lng,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível disparar o alarme: $e')),
      );
    }
  }

  Future<void> _readNfc() async {
    setState(() => _nfcMessage = 'Aproxime a tag...');
    try {
      final text = await NfcService.instance.readTagText();
      if (!mounted) return;
      setState(() => _nfcMessage = text ?? 'Tag sem texto NDEF legível.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _nfcMessage = 'Erro na leitura: $e');
    }
  }

  @override
  void dispose() {
    // Checa o estado real do serviço (LocationService.instance.isTracking),
    // não a flag local: se a tela for fechada enquanto startTracking()
    // ainda está em andamento, _tracking pode estar false mesmo com o
    // rastreamento já ativo no serviço.
    if (LocationService.instance.isTracking) {
      LocationService.instance.stopTracking();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isHakuna =
        _myProfile?.role == UserRole.hakuna ||
        _myProfile?.role == UserRole.admin;

    return Scaffold(
      appBar: AppBar(
        leading: const AppLogoAppBarLeading(),
        title: Text(widget.top.name),
      ),
      body: Column(
        children: [
          if (isHakuna)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ParticipantsScreen(top: widget.top),
                      ),
                    ),
                    icon: const Icon(Icons.groups),
                    label: const Text('Participantes'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TopSenderistasScreen(top: widget.top),
                      ),
                    ),
                    icon: const Icon(Icons.monitor_heart),
                    label: const Text('Sinais vitais'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TopChatScreen(
                          top: widget.top,
                          hakunaProfiles: _hakunaProfiles,
                        ),
                      ),
                    ),
                    icon: const Icon(Icons.chat),
                    label: const Text('Chat'),
                  ),
                ],
              ),
            ),
          if (_profileLoadFailed)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Não foi possível carregar seu perfil. Verifique a internet.',
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() => _profileLoadFailed = false);
                      _loadProfile();
                    },
                    child: const Text('Tentar de novo'),
                  ),
                ],
              ),
            ),
          if (isHakuna)
            _AlertBanner(topId: widget.top.id, hakunaProfiles: _hakunaProfiles),
          if (isHakuna)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: _sendAlert,
                icon: const Icon(Icons.warning_amber),
                label: const Text(
                  'EMERGÊNCIA — acidente / atendimento crítico',
                ),
              ),
            ),
          if (isHakuna)
            Padding(
              padding: const EdgeInsets.all(12),
              child: FilledButton.icon(
                onPressed: widget.top.status.name == 'active'
                    ? _toggleTracking
                    : null,
                icon: Icon(_tracking ? Icons.location_off : Icons.location_on),
                label: Text(
                  _tracking
                      ? 'Parar de compartilhar posição'
                      : 'Compartilhar minha posição',
                ),
              ),
            ),
          if (isHakuna)
            _MyStatsCard(topId: widget.top.id, weightKg: _myProfile?.weightKg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _readNfc,
                    icon: const Icon(Icons.nfc),
                    label: const Text('Ler tag NFC'),
                  ),
                ),
              ],
            ),
          ),
          if (_nfcMessage != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_nfcMessage!),
            ),
          const Divider(),
          Expanded(
            child: StreamBuilder<List<HakunaPosition>>(
              stream: SupabaseService.instance.watchTopPositions(widget.top.id),
              builder: (context, snapshot) {
                final positions = snapshot.data ?? [];
                if (positions.isEmpty) {
                  return const Center(
                    child: Text('Nenhuma posição de Hakuna disponível ainda.'),
                  );
                }
                return ListView.builder(
                  itemCount: positions.length,
                  itemBuilder: (context, index) {
                    final p = positions[index];
                    final label =
                        _hakunaProfiles[p.profileId]?.displayLabel ??
                        p.profileId;
                    return ListTile(
                      leading: const Icon(Icons.medical_services),
                      title: Text(label),
                      subtitle: Text(
                        'lat: ${p.latitude.toStringAsFixed(5)}, lng: ${p.longitude.toStringAsFixed(5)}\n'
                        'atualizado às ${p.recordedAt.toLocal()}',
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Distância percorrida, velocidade média e gasto calórico estimado do
/// próprio Hakuna no Top, calculados localmente a partir da trilha de GPS
/// já salva em hakuna_positions — sem nenhuma API externa.
class _MyStatsCard extends StatelessWidget {
  const _MyStatsCard({required this.topId, required this.weightKg});

  final String topId;
  final double? weightKg;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<HakunaPosition>>(
      stream: SupabaseService.instance.watchMyPositionHistory(topId),
      builder: (context, snapshot) {
        final positions = snapshot.data ?? [];
        final stats = StatsService.compute(positions, weightKg: weightKg);
        if (positions.length < 2) return const SizedBox.shrink();

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _StatItem(
                      icon: Icons.route,
                      label: 'Distância',
                      value: '${stats.distanceKm.toStringAsFixed(2)} km',
                    ),
                    _StatItem(
                      icon: Icons.speed,
                      label: 'Vel. média',
                      value: '${stats.avgSpeedKmh.toStringAsFixed(1)} km/h',
                    ),
                    _StatItem(
                      icon: Icons.local_fire_department,
                      label: 'Calorias*',
                      value: '${stats.calories.round()} kcal',
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  stats.caloriesIsEstimate
                      ? '* estimativa aproximada (informe seu peso no perfil pra ficar mais precisa)'
                      : '* estimativa aproximada',
                  style: Theme.of(context).textTheme.labelSmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Mostra os alarmes recentes (última hora) do Top que ainda não foram
/// dispensados nesta sessão. Só aparece enquanto a tela do Top estiver
/// aberta — não há push notification neste momento.
class _AlertBanner extends StatefulWidget {
  const _AlertBanner({required this.topId, required this.hakunaProfiles});

  final String topId;
  final Map<String, Profile> hakunaProfiles;

  @override
  State<_AlertBanner> createState() => _AlertBannerState();
}

class _AlertBannerState extends State<_AlertBanner> {
  final Set<int> _dismissed = {};

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TopAlert>>(
      stream: SupabaseService.instance.watchTopAlerts(widget.topId),
      builder: (context, snapshot) {
        final cutoff = DateTime.now().subtract(const Duration(hours: 1));
        final alerts = (snapshot.data ?? [])
            .where(
              (a) => !_dismissed.contains(a.id) && a.createdAt.isAfter(cutoff),
            )
            .toList();
        if (alerts.isEmpty) return const SizedBox.shrink();

        return Column(
          children: alerts.map((alert) {
            final senderLabel =
                widget.hakunaProfiles[alert.senderId]?.displayLabel ?? 'Hakuna';
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade700,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, color: Colors.white),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Alarme — $senderLabel',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (alert.message != null)
                          Text(
                            alert.message!,
                            style: const TextStyle(color: Colors.white),
                          ),
                        Text(
                          alert.createdAt.toLocal().toString(),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => setState(() => _dismissed.add(alert.id)),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}
