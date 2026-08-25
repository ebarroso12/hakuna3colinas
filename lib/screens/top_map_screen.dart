import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../models/attendance.dart';
import '../models/hakuna_position.dart';
import '../models/profile.dart';
import '../models/top.dart';
import '../services/supabase_service.dart';
import '../widgets/app_logo.dart';
import 'attendance_detail_screen.dart';

/// Mapa operacional do Top: Hakunas (última posição) + atendimentos
/// abertos. OpenStreetMap via flutter_map — sem chave de API nem
/// cobrança por uso (ver decisão na Fase 4 do plano).
class TopMapScreen extends StatefulWidget {
  const TopMapScreen({
    super.key,
    required this.top,
    this.hakunaProfiles = const {},
  });

  final Top top;
  final Map<String, Profile> hakunaProfiles;

  @override
  State<TopMapScreen> createState() => _TopMapScreenState();
}

class _TopMapScreenState extends State<TopMapScreen> {
  final _mapController = MapController();
  bool _centered = false;

  /// Verde enquanto a posição for recente — acima disso o Hakuna pode ter
  /// perdido conexão ou parado de compartilhar; não temos um evento
  /// explícito de "ficou offline", só a idade da última posição recebida.
  Color _recencyColor(DateTime recordedAt) {
    final age = DateTime.now().difference(recordedAt);
    if (age < const Duration(minutes: 5)) return Colors.green;
    if (age < const Duration(minutes: 20)) return Colors.orange;
    return Colors.grey;
  }

  Color _priorityColor(AttendancePriority priority) {
    switch (priority) {
      case AttendancePriority.urgencia:
        return Colors.red;
      case AttendancePriority.atencao:
        return Colors.orange;
      case AttendancePriority.normal:
        return Colors.blue;
    }
  }

  void _maybeCenterOn(List<HakunaPosition> positions) {
    if (_centered || positions.isEmpty) return;
    _centered = true;
    final avgLat =
        positions.map((p) => p.latitude).reduce((a, b) => a + b) /
        positions.length;
    final avgLng =
        positions.map((p) => p.longitude).reduce((a, b) => a + b) /
        positions.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mapController.move(ll.LatLng(avgLat, avgLng), 14);
    });
  }

  String _hakunaLabel(String profileId) =>
      widget.hakunaProfiles[profileId]?.displayLabel ?? profileId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AppBarLogoTitle(title: Text('Mapa · ${widget.top.name}')),
      ),
      body: StreamBuilder<List<HakunaPosition>>(
        stream: SupabaseService.instance.watchTopPositions(widget.top.id),
        builder: (context, positionSnapshot) {
          final positions = positionSnapshot.data ?? const [];
          _maybeCenterOn(positions);

          return StreamBuilder<List<Attendance>>(
            stream: SupabaseService.instance.watchTopAttendances(widget.top.id),
            builder: (context, attendanceSnapshot) {
              final openAttendances = (attendanceSnapshot.data ?? const [])
                  .where((a) => a.isOpen)
                  .toList();

              if (positions.isEmpty && openAttendances.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Nenhuma posição de Hakuna nem atendimento ativo ainda.\n'
                      'O mapa aparece assim que alguém compartilhar a posição.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }

              return FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: positions.isNotEmpty
                      ? ll.LatLng(
                          positions.first.latitude,
                          positions.first.longitude,
                        )
                      : ll.LatLng(
                          openAttendances.first.latitude,
                          openAttendances.first.longitude,
                        ),
                  initialZoom: 14,
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.legendarios.hakuna_connect',
                  ),
                  MarkerLayer(
                    markers: [
                      ...positions.map(
                        (p) => Marker(
                          point: ll.LatLng(p.latitude, p.longitude),
                          width: 40,
                          height: 40,
                          child: Tooltip(
                            message:
                                '${_hakunaLabel(p.profileId)}\n${p.recordedAt.toLocal()}',
                            child: Icon(
                              Icons.medical_services,
                              color: _recencyColor(p.recordedAt),
                              size: 32,
                            ),
                          ),
                        ),
                      ),
                      ...openAttendances.map(
                        (a) => Marker(
                          point: ll.LatLng(a.latitude, a.longitude),
                          width: 44,
                          height: 44,
                          child: GestureDetector(
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => AttendanceDetailScreen(
                                  attendance: a,
                                  hakunaProfiles: widget.hakunaProfiles,
                                ),
                              ),
                            ),
                            child: Icon(
                              Icons.warning_amber,
                              color: _priorityColor(a.priority),
                              size: 36,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}
