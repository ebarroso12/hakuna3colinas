import 'package:flutter/material.dart';

import '../models/acesso_as_equipes.dart';
import '../models/profile.dart';
import '../models/team.dart';
import '../models/top.dart';
import '../services/supabase_service.dart';
import 'team_chat_screen.dart';
import '../widgets/botao_inicio.dart';
import 'anotacoes_screen.dart';

/// Chats e anotações do Top: o canal geral mais **as 9 equipes, sempre
/// todas as 9**.
///
/// Até 11/10/2026 esta tela listava só as equipes em que o usuário já era
/// membro liberado, e quem não estava em nenhuma via um único cartão
/// dizendo isso. O app é dos 9 TIMES e não mostrava time nenhum — e, como
/// `top_team_members` nasce vazia, esse era o estado de **todo mundo** num
/// Top recém-montado, inclusive do admin.
///
/// Dois motivos para mostrar as 9 e marcar o estado de cada uma:
///
/// 1. **A RLS libera o admin em todas** (`is_admin() or is_team_member(...)`
///    — ver `supabase/anotacoes_das_equipes.sql` e
///    `supabase/admin_ve_todas_as_equipes.sql`). A tela estava fechando uma
///    porta que o banco deixa aberta, o inverso da regra do projeto.
/// 2. Uma equipe ausente da lista não diz nada. Uma equipe listada e
///    fechada diz **por que** está fechada, e é a diferença entre o
///    usuário pedir a coisa certa ao admin e achar que o app está quebrado.
///
/// Equipe fechada não abre o chat: a RLS recusaria e o usuário veria tela
/// vazia ou erro cru. Ao toque ela explica o estado.
///
/// Quem decide tudo isso é [AcessoAsEquipes], num model à parte — regra de
/// acesso precisa de teste direto, e dentro do `State` ela só se
/// verificava montando a árvore e fingindo rede.
class TeamChatsScreen extends StatefulWidget {
  const TeamChatsScreen({super.key, required this.top});

  final Top top;

  @override
  State<TeamChatsScreen> createState() => _TeamChatsScreenState();
}

class _TeamChatsScreenState extends State<TeamChatsScreen> {
  late Future<AcessoAsEquipes> _acesso;

  @override
  void initState() {
    super.initState();
    _acesso = _carregar();
  }

  /// Vínculos e papel, nesta ordem de importância: a falha do perfil é
  /// tolerada, a dos vínculos não.
  ///
  /// Se o perfil falhasse junto, um admin sem rede momentânea veria as 9
  /// fechadas com o motivo errado ("você não está nesta equipe").
  Future<AcessoAsEquipes> _carregar() async {
    final servico = SupabaseService.instance;
    final vinculos = await servico.fetchMyTeams(
      widget.top.id,
      somenteAtivas: false,
    );

    var souAdmin = false;
    var perfilFalhou = false;
    try {
      final perfil = await servico.fetchMyProfile();
      souAdmin = perfil.role == UserRole.admin || perfil.isMasterAdmin;
    } catch (_) {
      perfilFalhou = true;
    }

    return AcessoAsEquipes(
      vinculos: vinculos,
      souAdmin: souAdmin,
      perfilFalhou: perfilFalhou,
    );
  }

  void _recarregar() => setState(() => _acesso = _carregar());

  /// Abre o bloco de anotações da equipe.
  ///
  /// Fica ao lado do chat porque são coisas vizinhas e diferentes: o chat
  /// é conversa, a anotação é registro. Quem precisa saber o que ficou
  /// pendente no turno anterior não vai rolar 200 mensagens.
  void _abrirAnotacoes(TeamKey team) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AnotacoesScreen(top: widget.top, team: team),
      ),
    );
  }

  void _abrir(TeamKey team, {bool isTeamAdmin = false}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TeamChatScreen(
          top: widget.top,
          team: team,
          isTeamAdmin: isTeamAdmin,
        ),
      ),
    );
  }

  /// Explica por que a equipe está fechada, nomeando quem resolve.
  void _explicar(AcessoAsEquipes acesso, TeamKey team) {
    final texto = acesso.explicacaoDe(team);
    if (texto.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(texto), duration: const Duration(seconds: 5)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: [
          const BotaoInicio(),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recarregar',
            onPressed: _recarregar,
          ),
        ],
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Chats e anotações'),
            Text(
              widget.top.name,
              style: Theme.of(context).textTheme.labelSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: FutureBuilder<AcessoAsEquipes>(
        future: _acesso,
        builder: (context, snapshot) {
          // O chat geral não depende de vínculo com equipe, então ele é
          // mostrado mesmo enquanto a lista de equipes carrega ou falha.
          final geral = _cartaoGeral();

          if (snapshot.connectionState == ConnectionState.waiting) {
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                geral,
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ],
            );
          }

          // Sem os vínculos não há como dizer o estado de nenhuma equipe.
          // Listar as 9 todas fechadas aqui seria afirmar o que não se
          // sabe, então o erro aparece e o geral continua acessível.
          if (snapshot.hasError || snapshot.data == null) {
            return ListView(
              padding: const EdgeInsets.all(12),
              children: [
                geral,
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.error_outline),
                    title: const Text('Não foi possível carregar as equipes'),
                    subtitle: Text('${snapshot.error}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: _recarregar,
                    ),
                  ),
                ),
              ],
            );
          }

          final acesso = snapshot.data!;
          final equipes = TeamKeyUi.equipes;
          final abertas = acesso.quantasAbertas;

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              geral,
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  // Derivado, nunca escrito: um rótulo "As 9 equipes" com
                  // 8 na lista embaixo é a tela mentindo.
                  'As ${equipes.length} equipes'
                  '${abertas > 0 ? ' · $abertas liberada(s) para você' : ''}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (acesso.perfilFalhou)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 6,
                  ),
                  child: Text(
                    'Não deu para confirmar seu perfil. Se você é admin, '
                    'toque em recarregar — sem ele as equipes aparecem só '
                    'pelo seu vínculo.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 8),
              ...equipes.map((t) => _cartaoEquipe(t, acesso)),
            ],
          );
        },
      ),
    );
  }

  Widget _cartaoGeral() {
    return Card(
      child: ListTile(
        leading: Icon(TeamKey.geral.icon, color: TeamKey.geral.cor),
        title: const Text('Chat geral'),
        subtitle: const Text('Todos os participantes deste Top'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_note),
              tooltip: 'Anotações',
              onPressed: () => _abrirAnotacoes(TeamKey.geral),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => _abrir(TeamKey.geral),
      ),
    );
  }

  Widget _cartaoEquipe(TeamKey team, AcessoAsEquipes acesso) {
    final estado = acesso.estadoDe(team);
    final aberta = acesso.aberta(team);
    final cores = Theme.of(context).colorScheme;

    final selo = switch (estado) {
      EstadoDaEquipe.membro ||
      EstadoDaEquipe.acessoDeAdmin => Icons.chevron_right,
      EstadoDaEquipe.aguardandoLiberacao => Icons.hourglass_empty,
      EstadoDaEquipe.bloqueado => Icons.block,
      EstadoDaEquipe.fora => Icons.lock_outline,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        // Ícone operacional, não o genérico: é o que a equipe FAZ, e com 9
        // na mesma lista a cor e o desenho são o que separa de relance.
        leading: Icon(
          team.iconeOperacional,
          // Fechada fica apagada, aberta na cor da equipe. A diferença tem
          // de ser visível antes de ler o texto.
          color: aberta ? team.cor : cores.outline,
        ),
        title: Text(
          team.label,
          style: TextStyle(
            fontWeight: aberta ? FontWeight.bold : FontWeight.normal,
            color: aberta ? null : cores.onSurfaceVariant,
          ),
        ),
        subtitle: Text(
          acesso.descricaoDe(team),
          style: TextStyle(
            color: estado == EstadoDaEquipe.bloqueado ? cores.error : null,
            fontWeight: estado == EstadoDaEquipe.bloqueado
                ? FontWeight.bold
                : null,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (aberta)
              IconButton(
                icon: const Icon(Icons.edit_note),
                tooltip: 'Anotações da equipe',
                onPressed: () => _abrirAnotacoes(team),
              ),
            Icon(selo, color: aberta ? null : cores.outline),
          ],
        ),
        // Fechada responde ao toque explicando, em vez de abrir um chat
        // que a RLS esvazia. `onTap: null` daria um cartão morto, e cartão
        // morto parece defeito da tela.
        onTap: aberta
            ? () => _abrir(team, isTeamAdmin: acesso.podeAlertarEm(team))
            : () => _explicar(acesso, team),
      ),
    );
  }
}
