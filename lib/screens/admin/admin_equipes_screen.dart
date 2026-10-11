import 'package:flutter/material.dart';

import '../../models/profile.dart';
import '../../models/team.dart';
import '../../models/team_message.dart';
import '../../models/top.dart';
import '../../services/admin_service.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/botao_inicio.dart';
import '../../widgets/emblemas.dart';

/// Monta as equipes de um Top: quem está em qual, e quem coordena.
///
/// Sem esta tela, `top_team_members` fica vazia e os chats de equipe não
/// aparecem para ninguém.
///
/// Quem pode o quê é decidido pela RLS, não aqui:
///   - **admin** (master ou geral): tudo, inclusive promover a
///     coordenador e subcoordenador;
///   - **coordenador**: inclui e remove membros da própria equipe;
///   - **subcoordenador**: só inclui — a policy de DELETE o recusa.
///
/// A tela esconde o que a pessoa não pode fazer por cortesia; se ela
/// burlasse a UI, o banco recusaria do mesmo jeito.
class AdminEquipesScreen extends StatefulWidget {
  const AdminEquipesScreen({
    super.key,
    required this.top,
    this.souAdmin = false,
  });

  final Top top;
  final bool souAdmin;

  @override
  State<AdminEquipesScreen> createState() => _AdminEquipesScreenState();
}

class _AdminEquipesScreenState extends State<AdminEquipesScreen> {
  List<TeamMembership> _vinculos = [];
  List<Profile> _perfis = [];
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final vinculos = await AdminService.instance.fetchTeamMembers(
        widget.top.id,
      );
      final perfis = await AdminService.instance.fetchAllProfiles();
      if (!mounted) return;
      setState(() {
        _vinculos = vinculos;
        _perfis = perfis;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = '$e';
        _carregando = false;
      });
    }
  }

  Profile? _perfilDe(String id) {
    for (final p in _perfis) {
      if (p.id == id) return p;
    }
    return null;
  }

  List<TeamMembership> _daEquipe(TeamKey team) =>
      _vinculos.where((v) => v.team == team).toList()
        ..sort((a, b) => a.teamRole.index.compareTo(b.teamRole.index));

  Future<void> _adicionar(TeamKey team) async {
    // Só quem ainda não está nesta equipe.
    final jaNaEquipe = _daEquipe(team).map((v) => v.profileId).toSet();
    final disponiveis = _perfis
        .where((p) => !jaNaEquipe.contains(p.id))
        .toList();

    if (disponiveis.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Todos já estão nesta equipe.')),
      );
      return;
    }

    final escolhido = await showDialog<Profile>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('Incluir em ${team.label}'),
        children: disponiveis
            .map(
              (p) => SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext).pop(p),
                child: ListTile(
                  dense: true,
                  leading: Icon(team.iconeOperacional, color: team.cor),
                  title: Text(p.fullName),
                  subtitle: Text('#${p.legendariosNumber} · ${p.role.name}'),
                ),
              ),
            )
            .toList(),
      ),
    );
    if (escolhido == null) return;

    try {
      await AdminService.instance.addTeamMember(
        topId: widget.top.id,
        team: team,
        profileId: escolhido.id,
      );
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Não foi possível incluir: $e')));
    }
  }

  /// Executa uma mudança de equipe e DIZ se ela falhou.
  ///
  /// Antes era `.then((_) => _carregar())` sem `await` e sem
  /// `catchError`: recusa da RLS ou queda de rede virava um erro de future
  /// não tratado, a lista se redesenhava igual, e o admin via o botão
  /// "LIBERAR" simplesmente não fazer nada. Liberação silenciosamente
  /// perdida é grave: `is_team_member` exige `released`, então a pessoa
  /// fica sem chat e sem bloco de anotações achando que foi liberada.
  /// Achado por revisão em 11/10/2026.
  Future<void> _aplicar(Future<void> Function() acao, String oQue) async {
    try {
      await acao();
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Não foi possível $oQue: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _mudarPapel(TeamMembership v, TeamRole novo) async {
    try {
      await AdminService.instance.setTeamRole(membershipId: v.id, papel: novo);
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'O banco recusou a mudança de papel. '
            'Só admin promove a coordenador.\n$e',
          ),
        ),
      );
    }
  }

  Future<void> _remover(TeamMembership v) async {
    final nome = _perfilDe(v.profileId)?.fullName ?? v.profileId;
    final confirma = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remover da equipe?'),
        content: Text(
          '$nome sai de ${v.team.label} e perde o chat desta equipe.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (!(confirma ?? false)) return;

    try {
      await AdminService.instance.removeTeamMember(v.id);
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'O banco recusou a remoção. Subcoordenador não remove.\n$e',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Equipes'),
            Text(
              widget.top.topNumber != null
                  ? 'TOP# ${widget.top.topNumber}'
                  : widget.top.name,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          const BotaoInicio(),
          IconButton(icon: const Icon(Icons.refresh), onPressed: _carregar),
          const AppLogoTrailing(),
        ],
      ),
      body: _corpo(),
    );
  }

  Widget _corpo() {
    if (_carregando) return const Center(child: CircularProgressIndicator());
    if (_erro != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Erro ao carregar: $_erro', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _carregar,
                child: const Text('Tentar de novo'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Coordenador inclui e remove. Subcoordenador só inclui. '
              'Promover a coordenador ou subcoordenador é só do admin.',
            ),
          ),
        ),
        const SizedBox(height: 8),
        ...TeamKeyUi.equipes.map(_cartaoEquipe),
      ],
    );
  }

  Widget _cartaoEquipe(TeamKey team) {
    final membros = _daEquipe(team);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ExpansionTile(
        leading: Icon(team.iconeOperacional, color: team.cor),
        title: Text(
          team.label,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          membros.isEmpty
              ? 'Ninguém nesta equipe'
              : '${membros.length} integrante(s)',
        ),
        children: [
          ...membros.map(_linhaMembro),
          Padding(
            padding: const EdgeInsets.all(8),
            child: OutlinedButton.icon(
              onPressed: () => _adicionar(team),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Incluir alguém'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _linhaMembro(TeamMembership v) {
    final perfil = _perfilDe(v.profileId);
    final coordena = v.teamRole != TeamRole.membro;

    return ListTile(
      leading: coordena
          ? EmblemaCoordenador(
              subcoordenador: v.teamRole == TeamRole.subcoordenador,
              size: 34,
            )
          : const EmblemaLegendario(size: 30),
      title: Text(perfil?.fullName ?? v.profileId),
      subtitle: Text(
        [
          v.teamRole.label,
          if (!v.released) 'não liberado',
          if (v.blocked) 'BLOQUEADO',
        ].join(' · '),
        style: TextStyle(
          color: v.blocked ? Theme.of(context).colorScheme.error : null,
          fontWeight: v.blocked ? FontWeight.bold : null,
        ),
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (acao) {
          switch (acao) {
            case 'coordenador':
              _mudarPapel(v, TeamRole.coordenador);
            case 'subcoordenador':
              _mudarPapel(v, TeamRole.subcoordenador);
            case 'membro':
              _mudarPapel(v, TeamRole.membro);
            case 'liberar':
              // `setTeamReleased` existia no serviço e NENHUMA tela a
              // chamava: a lista mostrava "não liberado" e não oferecia
              // liberar. Como `is_team_member` exige `released = true`,
              // quem caísse nesse estado ficava sem chat e sem bloco de
              // anotações, sem caminho de saída pelo app.
              _aplicar(
                () => AdminService.instance.setTeamReleased(
                  membershipId: v.id,
                  released: !v.released,
                ),
                v.released ? 'retirar a liberação' : 'liberar',
              );
            case 'bloquear':
              _aplicar(
                () => AdminService.instance.setTeamBlocked(
                  membershipId: v.id,
                  blocked: !v.blocked,
                ),
                v.blocked ? 'desbloquear' : 'bloquear',
              );
            case 'remover':
              _remover(v);
          }
        },
        itemBuilder: (context) => [
          // Promover só aparece para admin — é o que a RLS permite.
          if (widget.souAdmin) ...[
            const PopupMenuItem(
              value: 'coordenador',
              child: Text('Tornar coordenador'),
            ),
            const PopupMenuItem(
              value: 'subcoordenador',
              child: Text('Tornar subcoordenador'),
            ),
            const PopupMenuItem(
              value: 'membro',
              child: Text('Tornar membro comum'),
            ),
            const PopupMenuDivider(),
          ],
          PopupMenuItem(
            value: 'liberar',
            child: Text(v.released ? 'Suspender (tirar acesso)' : 'LIBERAR'),
          ),
          PopupMenuItem(
            value: 'bloquear',
            child: Text(v.blocked ? 'Desbloquear' : 'Bloquear'),
          ),
          const PopupMenuItem(
            value: 'remover',
            child: Text('Remover da equipe'),
          ),
        ],
      ),
    );
  }
}
