import 'package:flutter/material.dart';

import '../models/team.dart';
import '../models/team_message.dart';
import '../models/top.dart';
import '../services/supabase_service.dart';
import 'team_chat_screen.dart';

/// Lista os chats disponíveis no Top: o geral, aberto a todo participante
/// aprovado, mais um por equipe em que o usuário esteja liberado.
class TeamChatsScreen extends StatefulWidget {
  const TeamChatsScreen({super.key, required this.top});

  final Top top;

  @override
  State<TeamChatsScreen> createState() => _TeamChatsScreenState();
}

class _TeamChatsScreenState extends State<TeamChatsScreen> {
  late Future<List<TeamMembership>> _minhasEquipes;

  @override
  void initState() {
    super.initState();
    _minhasEquipes = SupabaseService.instance.fetchMyTeams(widget.top.id);
  }

  void _abrir(TeamKey team, {bool isTeamAdmin = false}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TeamChatScreen(
          top: widget.top,
          team: team,
          isTeamAdmin: isTeamAdmin,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Chats'),
            Text(
              widget.top.name,
              style: Theme.of(context).textTheme.labelSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: FutureBuilder<List<TeamMembership>>(
        future: _minhasEquipes,
        builder: (context, snapshot) {
          // O chat geral não depende de vínculo com equipe, então ele é
          // mostrado mesmo enquanto a lista de equipes carrega ou falha.
          final geral = Card(
            child: ListTile(
              leading: Icon(TeamKey.geral.icon),
              title: const Text('Chat geral'),
              subtitle: const Text('Todos os participantes deste Top'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _abrir(TeamKey.geral),
            ),
          );

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

          final equipes =
              (snapshot.data ?? const <TeamMembership>[])
                  .where((m) => !m.team.isGeral)
                  .toList()
                ..sort((a, b) => a.team.label.compareTo(b.team.label));

          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              geral,
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Minhas equipes',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: 8),
              if (snapshot.hasError)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.error_outline),
                    title: const Text('Não foi possível carregar suas equipes'),
                    subtitle: Text('${snapshot.error}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: () => setState(() {
                        _minhasEquipes = SupabaseService.instance.fetchMyTeams(
                          widget.top.id,
                        );
                      }),
                    ),
                  ),
                )
              else if (equipes.isEmpty)
                const Card(
                  child: ListTile(
                    leading: Icon(Icons.groups_outlined),
                    title: Text('Você ainda não está em nenhuma equipe'),
                    subtitle: Text(
                      'O admin do Top precisa te incluir e liberar numa '
                      'equipe para o chat dela aparecer aqui.',
                    ),
                  ),
                )
              else
                ...equipes.map(
                  (m) => Card(
                    child: ListTile(
                      leading: Icon(m.team.icon),
                      title: Text(m.team.label),
                      subtitle: Text(
                        m.isTeamAdmin
                            ? 'Você é admin desta equipe'
                            : 'Membro da equipe',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _abrir(m.team, isTeamAdmin: m.isTeamAdmin),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
