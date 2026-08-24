import '../models/attendance.dart';

/// Máquina de estados do atendimento — determinística, testável, sem
/// depender de LLM ou de parsing de texto livre. Ver
/// supabase/participants_and_attendance.sql pro enum correspondente.
class AttendanceService {
  AttendanceService._();

  /// Rótulo em português pra cada estado, usado na UI.
  static String statusLabel(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.aberto:
        return 'Aberto';
      case AttendanceStatus.reconhecido:
        return 'Reconhecido';
      case AttendanceStatus.atribuido:
        return 'Atribuído';
      case AttendanceStatus.aCaminho:
        return 'A caminho';
      case AttendanceStatus.noLocal:
        return 'No local';
      case AttendanceStatus.emAndamento:
        return 'Em andamento';
      case AttendanceStatus.escalado:
        return 'Escalado';
      case AttendanceStatus.encerrado:
        return 'Encerrado';
      case AttendanceStatus.cancelado:
        return 'Cancelado';
    }
  }

  static String priorityLabel(AttendancePriority priority) {
    switch (priority) {
      case AttendancePriority.normal:
        return 'Normal';
      case AttendancePriority.atencao:
        return 'Atenção';
      case AttendancePriority.urgencia:
        return 'Urgência';
    }
  }

  /// Próxima transição principal disponível a partir do estado atual — o
  /// botão de ação primária mostrado na tela. Retorna null quando o
  /// atendimento já está encerrado/cancelado (nada mais a fazer).
  static (AttendanceStatus, String)? primaryAction(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.aberto:
        return (AttendanceStatus.atribuido, 'ACEITAR');
      case AttendanceStatus.reconhecido:
        return (AttendanceStatus.atribuido, 'ACEITAR');
      case AttendanceStatus.atribuido:
        return (AttendanceStatus.aCaminho, 'A CAMINHO');
      case AttendanceStatus.aCaminho:
        return (AttendanceStatus.noLocal, 'CHEGUEI');
      case AttendanceStatus.noLocal:
        return (AttendanceStatus.emAndamento, 'INICIAR ATENDIMENTO');
      case AttendanceStatus.emAndamento:
      case AttendanceStatus.escalado:
        return (AttendanceStatus.encerrado, 'FINALIZAR');
      case AttendanceStatus.encerrado:
      case AttendanceStatus.cancelado:
        return null;
    }
  }

  /// Nome da coluna de timestamp que deve ser marcada com now() ao
  /// transicionar PARA o estado indicado — mantém o histórico de cada
  /// etapa sem precisar de uma tabela de eventos separada nesta fase.
  static String? timestampColumnFor(AttendanceStatus status) {
    switch (status) {
      case AttendanceStatus.reconhecido:
        return 'acknowledged_at';
      case AttendanceStatus.atribuido:
        return 'assigned_at';
      case AttendanceStatus.aCaminho:
        return 'en_route_at';
      case AttendanceStatus.noLocal:
        return 'on_scene_at';
      case AttendanceStatus.encerrado:
      case AttendanceStatus.cancelado:
        return 'closed_at';
      default:
        return null;
    }
  }
}
