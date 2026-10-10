/// Os sinais vitais que reclassificam gravidade, isolados do atendimento.
///
/// `Atendimento` é append-only e carrega o relato clínico inteiro. Esta
/// classe é só o recorte que a triagem precisa ler de volta — PA e SpO₂ —
/// e existe porque a lista de participantes precisa da cor atual de 215
/// pessoas sem carregar 215 atendimentos completos.
class Afericao {
  final int? systolicBp;
  final int? diastolicBp;
  final int? spo2;
  final DateTime medidoEm;

  const Afericao({
    required this.medidoEm,
    this.systolicBp,
    this.diastolicBp,
    this.spo2,
  });

  /// Nenhum dos três valores foi aferido — aferição vazia não reclassifica
  /// nada. Um atendimento pode ser só conversa e observação.
  bool get vazia => systolicBp == null && diastolicBp == null && spo2 == null;

  /// "140 x 90". Null quando falta uma das duas — meia pressão não é PA.
  String? get pressaoArterial {
    if (systolicBp == null || diastolicBp == null) return null;
    return '$systolicBp x $diastolicBp';
  }
}
