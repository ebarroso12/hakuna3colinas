/// Um disparo de emergência num Top. Tabela `top_alerts`.
///
/// Decisão do dono em 11/10/2026: "se alguma pessoa apertar emergência
/// todos devem ver o lugar via GPS e quem está chamando". As duas coisas
/// que a emergência tem de responder são [temPosicao] e [quemChama].
class TopAlert {
  final int id;
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
    required this.id,
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
      topId: map['top_id'] as String,
      senderId: map['sender_id'] as String,
      senderName: map['sender_name'] as String?,
      message: map['message'] as String?,
      latitude: (map['latitude'] as num?)?.toDouble(),
      longitude: (map['longitude'] as num?)?.toDouble(),
      createdAt: DateTime.parse(map['created_at'] as String),
    );
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
