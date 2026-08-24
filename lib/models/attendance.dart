/// Estados do fluxo de atendimento — enum public.atendimento_status no banco.
/// Nomes em português pra bater com o enum já existente em produção
/// (supabase/atendimentos.sql), só estendido (ver
/// supabase/participants_and_attendance.sql).
enum AttendanceStatus {
  aberto, // NEW
  reconhecido, // ACKNOWLEDGED
  atribuido, // ASSIGNED
  aCaminho, // EN_ROUTE
  noLocal, // ON_SCENE
  emAndamento, // IN_PROGRESS
  escalado, // ESCALATED
  encerrado, // RESOLVED
  cancelado, // CANCELLED
}

AttendanceStatus attendanceStatusFromString(String value) {
  switch (value) {
    case 'a_caminho':
      return AttendanceStatus.aCaminho;
    case 'no_local':
      return AttendanceStatus.noLocal;
    case 'em_andamento':
      return AttendanceStatus.emAndamento;
    default:
      return AttendanceStatus.values.firstWhere(
        (s) => s.name == value,
        orElse: () => AttendanceStatus.aberto,
      );
  }
}

String attendanceStatusToString(AttendanceStatus status) {
  switch (status) {
    case AttendanceStatus.aCaminho:
      return 'a_caminho';
    case AttendanceStatus.noLocal:
      return 'no_local';
    case AttendanceStatus.emAndamento:
      return 'em_andamento';
    default:
      return status.name;
  }
}

enum AttendancePriority { normal, atencao, urgencia }

AttendancePriority attendancePriorityFromString(String value) {
  return AttendancePriority.values.firstWhere(
    (p) => p.name == value,
    orElse: () => AttendancePriority.normal,
  );
}

class Attendance {
  final String id;
  final String topId;
  final String openedBy;
  final String? senderistaId; // Senderista com conta própria, quando aplicável
  final String?
  participantId; // cadastro rápido de participante, quando aplicável
  final String? assignedTo;
  final String? notes;
  final AttendanceStatus status;
  final AttendancePriority priority;
  final double latitude;
  final double longitude;
  final DateTime openedAt;
  final DateTime? acknowledgedAt;
  final DateTime? assignedAt;
  final DateTime? enRouteAt;
  final DateTime? onSceneAt;
  final DateTime? closedAt;

  Attendance({
    required this.id,
    required this.topId,
    required this.openedBy,
    this.senderistaId,
    this.participantId,
    this.assignedTo,
    this.notes,
    required this.status,
    this.priority = AttendancePriority.normal,
    required this.latitude,
    required this.longitude,
    required this.openedAt,
    this.acknowledgedAt,
    this.assignedAt,
    this.enRouteAt,
    this.onSceneAt,
    this.closedAt,
  });

  factory Attendance.fromMap(Map<String, dynamic> map) {
    return Attendance(
      id: map['id'] as String,
      topId: map['top_id'] as String,
      openedBy: map['opened_by'] as String,
      senderistaId: map['senderista_id'] as String?,
      participantId: map['participant_id'] as String?,
      assignedTo: map['assigned_to'] as String?,
      notes: map['notes'] as String?,
      status: attendanceStatusFromString(map['status'] as String),
      priority: attendancePriorityFromString(
        map['priority'] as String? ?? 'normal',
      ),
      latitude: (map['latitude'] as num).toDouble(),
      longitude: (map['longitude'] as num).toDouble(),
      openedAt: DateTime.parse(map['opened_at'] as String),
      acknowledgedAt: map['acknowledged_at'] != null
          ? DateTime.parse(map['acknowledged_at'] as String)
          : null,
      assignedAt: map['assigned_at'] != null
          ? DateTime.parse(map['assigned_at'] as String)
          : null,
      enRouteAt: map['en_route_at'] != null
          ? DateTime.parse(map['en_route_at'] as String)
          : null,
      onSceneAt: map['on_scene_at'] != null
          ? DateTime.parse(map['on_scene_at'] as String)
          : null,
      closedAt: map['closed_at'] != null
          ? DateTime.parse(map['closed_at'] as String)
          : null,
    );
  }

  bool get isOpen =>
      status != AttendanceStatus.encerrado &&
      status != AttendanceStatus.cancelado;
}
