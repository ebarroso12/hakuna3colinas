import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/attendance.dart';
import '../models/participant.dart';
import '../models/profile.dart';
import '../models/top.dart';
import '../services/attendance_service.dart';
import '../services/supabase_service.dart';
import '../widgets/app_logo.dart';
import 'attendance_detail_screen.dart';

/// Lista os atendimentos do Top em tempo real — abertos primeiro. Ver
/// supabase/participants_and_attendance.sql pro fluxo de estados.
class AttendanceListScreen extends StatefulWidget {
  const AttendanceListScreen({
    super.key,
    required this.top,
    this.hakunaProfiles = const {},
  });

  final Top top;
  final Map<String, Profile> hakunaProfiles;

  @override
  State<AttendanceListScreen> createState() => _AttendanceListScreenState();
}

class _AttendanceListScreenState extends State<AttendanceListScreen> {
  bool _opening = false;

  String get _myLabel {
    final id = SupabaseService.instance.currentUser?.id;
    return widget.hakunaProfiles[id]?.displayLabel ?? 'Um Hakuna';
  }

  Future<void> _openNewAttendance() async {
    final participant = await _pickParticipant();
    if (participant == null && !mounted) return;

    setState(() => _opening = true);
    try {
      final position = await Geolocator.getCurrentPosition();
      final attendance = await SupabaseService.instance.openAttendance(
        topId: widget.top.id,
        latitude: position.latitude,
        longitude: position.longitude,
        participantId: participant?.id,
      );
      final participantLabel = participant?.displayLabel;
      final messageBody = participantLabel == null
          ? '$_myLabel abriu um novo atendimento.'
          : '$_myLabel abriu um atendimento para $participantLabel.';
      unawaited(
        SupabaseService.instance
            .sendTopMessage(
              topId: widget.top.id,
              body: messageBody,
              isSystem: true,
            )
            .catchError((_) {}),
      );
      unawaited(
        SupabaseService.instance
            .createNotification(
              topId: widget.top.id,
              type: 'atendimento',
              title: 'Novo atendimento',
              body: messageBody,
              relatedAttendanceId: attendance.id,
            )
            .catchError((_) {}),
      );
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AttendanceDetailScreen(
            attendance: attendance,
            hakunaProfiles: widget.hakunaProfiles,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível abrir o atendimento: $e')),
      );
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  /// Deixa escolher quem está sendo atendido (opcional — o atendimento pode
  /// ser aberto sem participante identificado, ex: turista não cadastrado).
  Future<Participant?> _pickParticipant() async {
    final participants = await SupabaseService.instance.fetchTopParticipants(
      widget.top.id,
    );
    if (!mounted || participants.isEmpty) return null;
    return showModalBottomSheet<Participant?>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Sem participante identificado'),
              onTap: () => Navigator.of(context).pop(null),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: participants.length,
                itemBuilder: (context, index) {
                  final p = participants[index];
                  return ListTile(
                    title: Text(p.displayLabel),
                    onTap: () => Navigator.of(context).pop(p),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AppBarLogoTitle(
          title: Text('Atendimentos · ${widget.top.name}'),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _opening ? null : _openNewAttendance,
        icon: _opening
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.add_alert),
        label: const Text('Novo atendimento'),
      ),
      body: StreamBuilder<List<Attendance>>(
        stream: SupabaseService.instance.watchTopAttendances(widget.top.id),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final all = snapshot.data!;
          final open = all.where((a) => a.isOpen).toList();
          final closed = all.where((a) => !a.isOpen).toList();
          if (all.isEmpty) {
            return const Center(
              child: Text('Nenhum atendimento neste Top ainda.'),
            );
          }
          return ListView(
            children: [
              if (open.isNotEmpty)
                ...open.map(
                  (a) => _AttendanceTile(
                    attendance: a,
                    hakunaProfiles: widget.hakunaProfiles,
                  ),
                ),
              if (closed.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    'Encerrados',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ...closed.map(
                  (a) => _AttendanceTile(
                    attendance: a,
                    hakunaProfiles: widget.hakunaProfiles,
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _AttendanceTile extends StatelessWidget {
  const _AttendanceTile({
    required this.attendance,
    this.hakunaProfiles = const {},
  });

  final Attendance attendance;
  final Map<String, Profile> hakunaProfiles;

  Color get _priorityColor {
    switch (attendance.priority) {
      case AttendancePriority.urgencia:
        return Colors.red;
      case AttendancePriority.atencao:
        return Colors.orange;
      case AttendancePriority.normal:
        return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: _priorityColor,
        child: const Icon(Icons.medical_services, color: Colors.white),
      ),
      title: Text(AttendanceService.statusLabel(attendance.status)),
      subtitle: Text(
        '${AttendanceService.priorityLabel(attendance.priority)} · aberto às ${attendance.openedAt.toLocal()}',
      ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => AttendanceDetailScreen(
            attendance: attendance,
            hakunaProfiles: hakunaProfiles,
          ),
        ),
      ),
    );
  }
}
