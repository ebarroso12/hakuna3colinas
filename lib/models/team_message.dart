import 'team.dart';

/// Mensagem de um chat de equipe (ou do chat geral, que é a equipe
/// [TeamKey.geral]). Tabela `team_messages`.
class TeamMessage {
  /// Null enquanto a mensagem só existe na fila do aparelho — o id é
  /// atribuído pelo Postgres no insert. Ver [pendente].
  final int? id;

  /// Gerado no aparelho antes de existir no servidor. É o que torna o
  /// reenvio idempotente (`upsert onConflict: client_id`) e o que permite
  /// casar a mensagem pendente na tela com a que volta pelo realtime.
  ///
  /// Null nas mensagens enviadas antes da v1.0.18, que não tinham a coluna.
  final String? clientId;

  final String topId;
  final TeamKey team;
  final String senderId;
  final String body;
  final DateTime createdAt;

  /// Marcado só por admin da equipe ou admin geral — a RLS de INSERT
  /// rejeita `is_alert = true` de qualquer outro remetente.
  final bool isAlert;

  /// Preenchido quando a mensagem foi editada depois de enviada. Null em
  /// mensagem nunca editada.
  final DateTime? editedAt;

  /// Nome de quem escreveu, quando a mensagem chegou pelo RÁDIO local.
  ///
  /// `profiles` é fechada para quem recebe, e sem rede não há como
  /// resolver uuid em nome. Null nas que vieram do servidor, onde a tela
  /// já tem o perfil.
  final String? senderName;

  /// O servidor confirmou a autoria.
  ///
  /// **Falso = chegou por rádio local, sem autenticação nenhuma.**
  /// Qualquer aparelho ao alcance pode afirmar "fulano disse X" — a RLS
  /// impede isso no servidor, o rádio não impede nada.
  ///
  /// Numa emergência a diferença é séria: "o coordenador mandou descer"
  /// forjado move 200 pessoas. A tela mostra o aviso; esconder seria pior
  /// que não ter a funcionalidade. Ver `lib/offline/transporte_local.dart`.
  ///
  /// `true` por padrão porque toda mensagem do Supabase é autenticada —
  /// só o rádio grava `false`, e grava explicitamente.
  final bool confirmada;

  TeamMessage({
    required this.topId,
    required this.team,
    required this.senderId,
    required this.body,
    required this.createdAt,
    required this.isAlert,
    this.id,
    this.clientId,
    this.editedAt,
    this.senderName,
    this.confirmada = true,
  });

  /// Chegou pelo rádio e ninguém confirmou quem escreveu.
  bool get semAutoriaConfirmada => !confirmada;

  /// Ainda não chegou ao servidor: está na fila do aparelho.
  ///
  /// A tela usa isto para mostrar o relógio em vez do horário — no mato o
  /// Hakuna precisa saber que a mensagem **não foi entregue ainda**, senão
  /// ele acredita que avisou a equipe e ninguém recebeu.
  bool get pendente => id == null;

  factory TeamMessage.fromMap(Map<String, dynamic> map) {
    return TeamMessage(
      id: map['id'] as int?,
      clientId: map['client_id'] as String?,
      topId: map['top_id'] as String,
      // Um valor de `team` que o app não conhece (equipe nova criada no
      // banco antes de o app ser atualizado) cai em geral em vez de
      // estourar — mensagem fora de lugar é melhor que tela quebrada.
      team: teamKeyFromString(map['team'] as String?) ?? TeamKey.geral,
      senderId: map['sender_id'] as String,
      body: map['body'] as String,
      createdAt: DateTime.parse(map['created_at'] as String),
      isAlert: map['is_alert'] as bool? ?? false,
      editedAt: map['edited_at'] != null
          ? DateTime.parse(map['edited_at'] as String)
          : null,
      senderName: map['sender_name'] as String?,
      // Ausente = veio do Supabase, onde a RLS garante a autoria. Só o
      // cache local grava `false`, e grava explicitamente.
      confirmada: map['confirmada'] as bool? ?? true,
    );
  }
}

/// Papel de uma pessoa dentro de uma equipe. Espelha o enum `team_role`
/// do Postgres.
///
/// A diferença entre os dois primeiros é imposta pela RLS, não pela UI:
/// coordenador adiciona E remove; subcoordenador só adiciona. Promover
/// alguém a coordenador ou subcoordenador é exclusivo do admin.
enum TeamRole { coordenador, subcoordenador, membro }

TeamRole teamRoleFromString(String? value) {
  for (final r in TeamRole.values) {
    if (r.name == value) return r;
  }
  // Papel desconhecido cai no nível mais baixo — na dúvida, menos poder.
  return TeamRole.membro;
}

extension TeamRoleUi on TeamRole {
  String get label => switch (this) {
    TeamRole.coordenador => 'Coordenador',
    TeamRole.subcoordenador => 'Subcoordenador',
    TeamRole.membro => 'Membro',
  };

  /// Coordenador e subcoordenador podem incluir gente na equipe.
  bool get podeAdicionar => this != TeamRole.membro;

  /// Só o coordenador remove. Subcoordenador não.
  bool get podeRemover => this == TeamRole.coordenador;

  /// Quem coordena a equipe também pode mandar mensagem como alerta.
  bool get podeAlertar => this != TeamRole.membro;
}

/// Vínculo de um perfil com uma equipe dentro de um Top. Tabela
/// `top_team_members`.
class TeamMembership {
  final int id;
  final String topId;
  final TeamKey team;
  final String profileId;
  final TeamRole teamRole;

  /// Liberado para atuar na equipe naquele Top. Um membro não liberado
  /// ainda não aparece para os outros membros (ver a policy de SELECT).
  final bool released;
  final bool blocked;

  TeamMembership({
    required this.id,
    required this.topId,
    required this.team,
    required this.profileId,
    required this.teamRole,
    required this.released,
    required this.blocked,
  });

  factory TeamMembership.fromMap(Map<String, dynamic> map) {
    return TeamMembership(
      id: map['id'] as int,
      topId: map['top_id'] as String,
      team: teamKeyFromString(map['team'] as String?) ?? TeamKey.geral,
      profileId: map['profile_id'] as String,
      teamRole: teamRoleFromString(map['team_role'] as String?),
      released: map['released'] as bool? ?? false,
      blocked: map['blocked'] as bool? ?? false,
    );
  }

  /// Só quem está liberado e não bloqueado participa de fato da equipe.
  bool get isActive => released && !blocked;

  /// Coordena a equipe (coordenador ou subcoordenador). Equivale ao
  /// `is_team_admin` do banco, que hoje é coluna derivada de `team_role`.
  bool get isTeamAdmin => isActive && teamRole.podeAdicionar;

  bool get podeAdicionarMembros => isActive && teamRole.podeAdicionar;
  bool get podeRemoverMembros => isActive && teamRole.podeRemover;
}
