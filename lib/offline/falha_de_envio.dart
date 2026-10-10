/// Falha de envio que **não melhora com o tempo**.
///
/// A distinção existe por um problema concreto: o [SyncService] para no
/// primeiro erro — o que é certo para queda de rede, porque insistir nas
/// outras 199 entradas só queima bateria. Mas se a entrada da frente for
/// recusada de forma definitiva, parar significa **bloquear a fila
/// inteira para sempre**: atendimento, GPS, foto e auditoria ficam presos
/// atrás dela.
///
/// Isso não é hipótese. Casos reais hoje:
///
///  - a RLS de `team_messages` recusa mensagem no chat geral enquanto o
///    Top estiver em `draft` — e o Top 1782 está em draft;
///  - `atendimentos_insert_self` exige o Hakuna com `released = true`;
///    liberação revogada entre o registro e o sync vira recusa definitiva;
///  - `is_alert = true` de quem deixou de coordenar a equipe;
///  - troca de usuário no aparelho antes do sync (`sender_id` /
///    `lida_por` / `actor_id` presos a `auth.uid()`).
///
/// Quem classifica é a camada que fala com o Supabase, não o
/// [SyncService]: é lá que os tipos do Postgrest já estão importados, e
/// manter a sincronização sem essa dependência é o que a deixa testável
/// sem subir o Supabase.
class FalhaPermanente implements Exception {
  /// Explicação em português, para aparecer na tela de quem vai resolver.
  final String motivo;

  /// A exceção original, para o log.
  final Object causa;

  const FalhaPermanente(this.motivo, this.causa);

  @override
  String toString() => 'FalhaPermanente: $motivo ($causa)';
}
