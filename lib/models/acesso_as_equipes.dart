import 'team.dart';
import 'team_message.dart';

/// Por que cada uma das 9 equipes está aberta ou fechada para quem está
/// olhando a tela.
///
/// São cinco e não dois porque "fechada" tem três causas com soluções
/// diferentes: não estar na equipe (pedir inclusão), estar sem liberação
/// (pedir liberação) e estar bloqueado — que não é erro, é decisão de
/// alguém. Juntar as três num "sem acesso" manda o usuário procurar o
/// problema no lugar errado, normalmente no app.
enum EstadoDaEquipe {
  /// Membro liberado. O papel na equipe diz o resto.
  membro,

  /// Não é membro, mas é admin do app. Decisão do dono em 11/10/2026:
  /// "como administrador devo ver e ter acesso a todas as equipes".
  acessoDeAdmin,

  /// Está em `top_team_members` com `released = false`. O estado mais
  /// cruel de esconder: `is_team_member` exige `released`, então a pessoa
  /// não tem chat nem anotações **e** não tem como saber o que pedir.
  aguardandoLiberacao,

  /// `blocked = true`. Alguém decidiu isso.
  bloqueado,

  /// Nenhuma linha em `top_team_members`.
  fora,
}

/// Quem vê o quê nas 9 equipes de um Top.
///
/// Mora num model, e não dentro da tela, por um motivo prático: é a regra
/// que decide se o usuário tem acesso, e regra de acesso precisa de teste
/// direto. Dentro do `State` ela só se verificava montando a árvore e
/// fingindo rede.
///
/// **Esta classe não é a fronteira de segurança** — a RLS é. Ela existe
/// para não oferecer porta que o banco vai fechar, nem esconder porta que
/// o banco deixa aberta. O segundo erro foi o que escondeu as 9 equipes
/// do admin até 11/10/2026.
class AcessoAsEquipes {
  const AcessoAsEquipes({
    required this.vinculos,
    required this.souAdmin,
    this.perfilFalhou = false,
  });

  /// **Todos** os vínculos do usuário neste Top, inclusive os inativos —
  /// é deles que sai a distinção entre [EstadoDaEquipe.fora] e
  /// [EstadoDaEquipe.aguardandoLiberacao]. Vem de
  /// `fetchMyTeams(..., somenteAtivas: false)`.
  final List<TeamMembership> vinculos;

  /// `role == admin` ou `is_master_admin`.
  final bool souAdmin;

  /// O perfil não carregou (sem rede, sessão expirada). Não impede a
  /// tela: as equipes de que a pessoa é membro continuam abertas pelo
  /// vínculo. O que se perde é o acesso por papel de admin — e aí a tela
  /// avisa, em vez de dizer "você não está nesta equipe", que seria
  /// mentira.
  final bool perfilFalhou;

  TeamMembership? vinculoDe(TeamKey team) {
    for (final v in vinculos) {
      if (v.team == team) return v;
    }
    return null;
  }

  /// O vínculo manda sobre o papel de admin, e a ordem importa.
  ///
  /// Admin bloqueado numa equipe aparece como **bloqueado**, não como
  /// "acesso de admin": o bloqueio é uma decisão explícita de alguém
  /// sobre aquela pessoa naquela equipe, e tratá-lo como ruído seria a
  /// tela desfazendo pela leitura o que o admin fez pela escrita.
  EstadoDaEquipe estadoDe(TeamKey team) {
    final v = vinculoDe(team);
    if (v != null) {
      if (v.blocked) return EstadoDaEquipe.bloqueado;
      if (!v.released) return EstadoDaEquipe.aguardandoLiberacao;
      return EstadoDaEquipe.membro;
    }
    return souAdmin ? EstadoDaEquipe.acessoDeAdmin : EstadoDaEquipe.fora;
  }

  /// Abre o chat e o bloco de anotações.
  bool aberta(TeamKey team) {
    final e = estadoDe(team);
    return e == EstadoDaEquipe.membro || e == EstadoDaEquipe.acessoDeAdmin;
  }

  /// Pode mandar mensagem destacada para a equipe inteira.
  ///
  /// Admin do app, coordenador e subcoordenador. A RLS de INSERT de
  /// `team_messages` recusa `is_alert = true` de quem não é — e recusa
  /// virando QUARENTENA na fila, então oferecer o controle a quem não
  /// pode não é só feio: perde a mensagem de vista.
  bool podeAlertarEm(TeamKey team) {
    if (!aberta(team)) return false;
    if (souAdmin) return true;
    return vinculoDe(team)?.isTeamAdmin ?? false;
  }

  /// Quantas das 9 estão abertas. Usado no cabeçalho da lista.
  int get quantasAbertas => TeamKeyUi.equipes.where(aberta).length;

  /// O texto do subtítulo do cartão.
  ///
  /// Mora aqui junto da decisão de propósito: o texto **é** a correção.
  /// Uma equipe ausente da lista não diz nada; uma equipe listada e
  /// fechada diz o que fazer, e é a diferença entre o usuário pedir a
  /// coisa certa e achar que o app está quebrado.
  String descricaoDe(TeamKey team) {
    final estado = estadoDe(team);
    switch (estado) {
      case EstadoDaEquipe.membro:
        final papel = vinculoDe(team)!.teamRole;
        // O admin que também é membro comum vê os dois: "Membro" sozinho
        // seria subnotificação, porque ele pode alertar e o cartão tem de
        // dizer de onde vem esse poder.
        return souAdmin && papel == TeamRole.membro
            ? '${papel.label} · acesso de admin'
            : papel.label;
      case EstadoDaEquipe.acessoDeAdmin:
        return 'Aberta porque você é admin do app';
      case EstadoDaEquipe.aguardandoLiberacao:
        return 'Você está na equipe, mas falta ser LIBERADO';
      case EstadoDaEquipe.bloqueado:
        return 'BLOQUEADO nesta equipe';
      case EstadoDaEquipe.fora:
        return 'Você não está nesta equipe';
    }
  }

  /// O que dizer quando a pessoa toca numa equipe fechada.
  ///
  /// Sempre nomeia **quem** resolve. Vazio para equipe aberta, que não
  /// precisa de explicação — precisa de abrir.
  String explicacaoDe(TeamKey team) {
    final label = team.label;
    return switch (estadoDe(team)) {
      EstadoDaEquipe.aguardandoLiberacao =>
        'Você está em $label, mas ainda não foi LIBERADO. '
            'O admin do Top libera em Equipes do Top.',
      EstadoDaEquipe.bloqueado =>
        'Você está BLOQUEADO em $label. Só o admin do Top desbloqueia.',
      EstadoDaEquipe.fora =>
        'Você não está em $label. O admin do Top ou o coordenador da '
            'equipe precisa te incluir e liberar.',
      _ => '',
    };
  }
}
