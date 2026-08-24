import 'package:flutter/material.dart';

import '../models/attendance.dart';
import '../models/profile.dart';
import '../services/attendance_service.dart';
import '../services/supabase_service.dart';
import '../widgets/app_logo.dart';

/// Tela operacional de um atendimento — botões grandes pro fluxo:
/// ACEITAR -> A CAMINHO -> CHEGUEI -> INICIAR ATENDIMENTO -> FINALIZAR,
/// mais PEDIR APOIO e URGÊNCIA, que não avançam o status por si só.
class AttendanceDetailScreen extends StatefulWidget {
  const AttendanceDetailScreen({
    super.key,
    required this.attendance,
    this.hakunaProfiles = const {},
  });

  final Attendance attendance;
  final Map<String, Profile> hakunaProfiles;

  @override
  State<AttendanceDetailScreen> createState() => _AttendanceDetailScreenState();
}

class _AttendanceDetailScreenState extends State<AttendanceDetailScreen> {
  bool _busy = false;

  String _profileLabel(String id) =>
      widget.hakunaProfiles[id]?.displayLabel ?? id;

  String get _myLabel {
    final id = SupabaseService.instance.currentUser?.id;
    return widget.hakunaProfiles[id]?.displayLabel ?? 'Um Hakuna';
  }

  void _postSystem(String topId, String body) {
    SupabaseService.instance
        .sendTopMessage(topId: topId, body: body, isSystem: true)
        .catchError((_) {});
  }

  Future<void> _runAction(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Não foi possível: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _accept(Attendance current) async {
    setState(() => _busy = true);
    try {
      final accepted = await SupabaseService.instance.acceptAttendance(
        current.id,
      );
      if (!mounted) return;
      if (!accepted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Outro Hakuna já aceitou este atendimento.'),
          ),
        );
      } else {
        _postSystem(current.topId, '$_myLabel aceitou o atendimento.');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Não foi possível aceitar: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _advance(Attendance current, AttendanceStatus next) {
    return _runAction(() async {
      await SupabaseService.instance.updateAttendanceStatus(
        attendanceId: current.id,
        newStatus: attendanceStatusToString(next),
        timestampColumn: AttendanceService.timestampColumnFor(next),
      );
      _postSystem(
        current.topId,
        '$_myLabel marcou "${AttendanceService.statusLabel(next)}".',
      );
    });
  }

  Future<void> _finish(Attendance current) {
    return _runAction(() async {
      await SupabaseService.instance.updateAttendanceStatus(
        attendanceId: current.id,
        newStatus: attendanceStatusToString(AttendanceStatus.encerrado),
        timestampColumn: 'closed_at',
      );
      _postSystem(current.topId, '$_myLabel finalizou o atendimento.');
    });
  }

  Future<void> _requestSupport(Attendance current) {
    return _runAction(() async {
      await SupabaseService.instance.joinAttendanceSupport(current.id);
      _postSystem(current.topId, '$_myLabel está apoiando o atendimento.');
    });
  }

  Future<void> _escalate(Attendance current) {
    return _runAction(() async {
      await SupabaseService.instance.escalateAttendance(current.id);
      _postSystem(
        current.topId,
        '🔴 URGÊNCIA acionada por $_myLabel no atendimento.',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppLogoAppBarLeading(),
        title: const Text('Atendimento'),
      ),
      body: StreamBuilder<List<Attendance>>(
        stream: SupabaseService.instance.watchTopAttendances(
          widget.attendance.topId,
        ),
        initialData: [widget.attendance],
        builder: (context, snapshot) {
          final current = (snapshot.data ?? const [])
              .cast<Attendance?>()
              .firstWhere(
                (a) => a?.id == widget.attendance.id,
                orElse: () => widget.attendance,
              )!;
          final action = AttendanceService.primaryAction(current.status);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Chip(
                    label: Text(AttendanceService.statusLabel(current.status)),
                  ),
                  const SizedBox(width: 8),
                  Chip(
                    label: Text(
                      AttendanceService.priorityLabel(current.priority),
                    ),
                    backgroundColor:
                        current.priority == AttendancePriority.urgencia
                        ? Colors.red.shade100
                        : current.priority == AttendancePriority.atencao
                        ? Colors.orange.shade100
                        : null,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Aberto às ${current.openedAt.toLocal()}'),
              Text(
                'Local: ${current.latitude.toStringAsFixed(5)}, ${current.longitude.toStringAsFixed(5)}',
              ),
              if (current.assignedTo != null)
                Text('Responsável: ${_profileLabel(current.assignedTo!)}'),
              if (current.notes != null) ...[
                const SizedBox(height: 8),
                Text(current.notes!),
              ],
              const SizedBox(height: 24),
              if (current.isOpen) ...[
                if (current.status == AttendanceStatus.aberto ||
                    current.status == AttendanceStatus.reconhecido)
                  FilledButton(
                    onPressed: _busy ? null : () => _accept(current),
                    child: const Text('ACEITAR'),
                  )
                else if (action != null)
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () => _advance(current, action.$1),
                    child: Text(action.$2),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _requestSupport(current),
                        icon: const Icon(Icons.group_add),
                        label: const Text('PEDIR / DAR APOIO'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        onPressed: _busy ? null : () => _escalate(current),
                        icon: const Icon(Icons.priority_high),
                        label: const Text('URGÊNCIA'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _busy ? null : () => _finish(current),
                  child: const Text('FINALIZAR'),
                ),
              ],
              const SizedBox(height: 24),
              const Text(
                'Apoio',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              StreamBuilder<List<String>>(
                stream: SupabaseService.instance.watchAttendanceMemberIds(
                  current.id,
                ),
                builder: (context, memberSnapshot) {
                  final members = memberSnapshot.data ?? const [];
                  if (members.isEmpty) {
                    return const Text('Ninguém apoiando ainda.');
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: members
                        .map((id) => Text('• ${_profileLabel(id)}'))
                        .toList(),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
