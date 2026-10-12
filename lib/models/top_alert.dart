/// Um disparo de emergência num Top. Tabela `top_alerts`.
///
/// Decisão do dono em 11/10/2026: "se alguma pessoa apertar emergência
/// todos devem ver o lugar via GPS e quem está chamando". As duas coisas
/// que a emergência tem de responder são [temPosicao] e [quemChama].
class TopAlert {
  /// Id do Postgres. **Null em alarme que chegou pelo rádio**, porque ele
  /// ainda não existe no servidor — e pode nunca existir, se quem disparou
  /// não recuperar sinal.
  final int? id;

  /// Identidade gerada no aparelho de origem.
  ///
  /// É o que permite o alarme por rádio ter identidade antes do servidor,
  /// e é a mesma chave que a fila usa. Quando o mesmo alarme chegar
  /// depois pelo Supabase, os dois têm o mesmo `client_id` e [chave] os
  /// funde em vez de a pessoa receber a emergência duas vezes.
  final String? clientId;

  /// **Falso para tudo que chegou por rádio.**
  ///
  /// Só o servidor confirma autoria: a RLS prende `sender_id` a
  /// `auth.uid()`. No rádio não há autenticação nenhuma, e qualquer
  /// aparelho ao alcance pode afirmar o que quiser em nome de quem
  /// quiser. A faixa **tem de** mostrar essa diferença — esconder isso
  /// seria pior que não ter a funcionalidade.
  final bool confirmado;

  final String topId;
  final String senderId;

  /// Nome de quem disparou, **no momento do disparo**.
  ///
  /// Desnormalizado de propósito, e não por preguiça: `profiles` é fechada
  /// para quem recebe o alarme (`profiles_select_own_or_admin` =
  /// `id = auth.uid() or is_admin()`), o Realtime não passa por RPC, e no
  /// disparo offline não há rede para resolver uuid em nome. Ver
  /// `supabase/alarme_para_todo_o_top.sql`.
  ///
  /// Null em alarme anterior à coluna, ou disparado antes de o perfil ter
  /// carregado alguma vez com sinal.
  final String? senderName;

  final String? message;
  final double? latitude;
  final double? longitude;
  final DateTime createdAt;

  TopAlert({
    this.id,
    this.clientId,
    this.confirmado = true,
    required this.topId,
    required this.senderId,
    this.senderName,
    this.message,
    this.latitude,
    this.longitude,
    required this.createdAt,
  });

  factory TopAlert.fromMap(Map<String, dynamic> map) {
    return TopAlert(
      id: map['id'] as int,
      clientId: map['client_id'] as String?,
      topId: map['top_id'] as String,
      senderId: map['sender_id'] as String,
      senderName: map['sender_name'] as String?,
      message: map['message'] as String?,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  /// Identidade única, sirva o alarme de onde servir.
  ///
  /// Texto e não número porque alarme de rádio não tem id do Postgres. O
  /// `client_id` vem primeiro de propósito: é ele que faz o MESMO alarme,
  /// chegando pelo rádio e depois pelo servidor, contar como um só —
  /// anunciar duas vezes a mesma emergência ensina a equipe a ignorar o
  /// som.
  String get chave {
    final c = clientId?.trim();
    if (c != null && c.isNotEmpty) return c;
    return id != null ? 'srv:$id' : 'sem-chave';
  }

  /// Dá para levar alguém até lá.
  bool get temPosicao => latitude != null && longitude != null;

  /// Quem está chamando, pronto para a tela.
  ///
  /// Nunca devolve uuid. Um uuid na faixa de emergência é pior que nada:
  /// ocupa a linha que deveria dizer um nome e não ajuda ninguém a achar
  /// a pessoa. Sem nome, diz o que é verdade — alguém do Top chamou.
  String get quemChama {
    final nome = senderName?.trim();
    return (nome == null || nome.isEmpty) ? 'Alguém do Top' : nome;
  }

  /// O nome é conhecido de fato (não é o texto de fallback).
  bool get temNome => senderName?.trim().isNotEmpty ?? false;
}
