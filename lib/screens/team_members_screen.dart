import 'package:flutter/material.dart';

import '../models/member_name.dart';
import '../models/team.dart';
import '../models/team_membership.dart';
import '../models/top.dart';
import '../services/supabase_service.dart';
import '../widgets/app_logo.dart';

/// Gestão de membros de uma equipe — só quem administra essa equipe (ou o
/// admin global do app) chega aqui; o RLS de top_team_members garante isso
/// mesmo que a navegação falhe em esconder o botão.
class TeamMembersScreen extends StatefulWidget {
  const TeamMembersScreen({super.key, required this.top, required this.team});

  final Top top;
  final Team team;

  @override
  State<TeamMembersScreen> createState() => _TeamMembersScreenState();
}

class _TeamMembersScreenState extends State<TeamMembersScreen> {
  final _searchController = TextEditingController();
  List<MemberName>? _searchResults;
  bool _searching = false;

  Future<void> _search(String query) async {
    setState(() => _searching = true);
    try {
      final results = await SupabaseService.instance.searchProfilesForTeam(
        topId: widget.top.id,
        team: widget.team,
        query: query.trim(),
      );
      if (mounted) setState(() => _searchResults = results);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Não foi possível buscar: $e')));
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _release(String profileId, bool released) async {
    try {
      await SupabaseService.instance.setTeamMemberReleased(
        topId: widget.top.id,
        team: widget.team,
        profileId: profileId,
        released: released,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível atualizar: $e')),
        );
      }
    }
  }

  Future<void> _toggleAdmin(String profileId, bool isTeamAdmin) async {
    try {
      await SupabaseService.instance.setTeamMemberAdmin(
        topId: widget.top.id,
        team: widget.team,
        profileId: profileId,
        isTeamAdmin: isTeamAdmin,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível atualizar: $e')),
        );
      }
    }
  }

  Future<void> _remove(String profileId) async {
    try {
      await SupabaseService.instance.removeTeamMember(
        topId: widget.top.id,
        team: widget.team,
        profileId: profileId,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Não foi possível remover: $e')));
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppLogoAppBarLeading(),
        title: Text('Membros · ${widget.team.label}'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: 'Buscar por nome ou número do Legendários',
                border: const OutlineInputBorder(),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.search),
                        onPressed: () => _search(_searchController.text),
                      ),
              ),
              onSubmitted: _search,
            ),
          ),
          if (_searchResults != null)
            _SearchResultsList(
              results: _searchResults!,
              onAdd: (id) async {
                await _release(id, true);
                setState(() => _searchResults = null);
                _searchController.clear();
              },
            ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<List<TeamMembership>>(
              stream: SupabaseService.instance.watchTeamRoster(
                topId: widget.top.id,
                team: widget.team,
              ),
              builder: (context, snapshot) {
                final roster = snapshot.data ?? [];
                if (roster.isEmpty) {
                  return const Center(
                    child: Text(
                      'Ninguém nesta equipe ainda. Busque acima pra adicionar.',
                    ),
                  );
                }
                return FutureBuilder<Map<String, MemberName>>(
                  future: SupabaseService.instance.fetchMemberNames(
                    topId: widget.top.id,
                    team: widget.team,
                    profileIds: roster.map((m) => m.profileId).toList(),
                  ),
                  builder: (context, namesSnapshot) {
                    final names = namesSnapshot.data ?? {};
                    return ListView.builder(
                      itemCount: roster.length,
                      itemBuilder: (context, index) {
                        final m = roster[index];
                        final label =
                            names[m.profileId]?.displayLabel ?? m.profileId;
                        return ListTile(
                          title: Text(label),
                          subtitle: Text(
                            m.isTeamAdmin ? 'Admin da equipe' : 'Membro',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Column(
                                children: [
                                  const Text(
                                    'Liberado',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  Switch(
                                    value: m.released,
                                    onChanged: (v) => _release(m.profileId, v),
                                  ),
                                ],
                              ),
                              const SizedBox(width: 4),
                              Column(
                                children: [
                                  const Text(
                                    'Admin',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  Switch(
                                    value: m.isTeamAdmin,
                                    onChanged: (v) =>
                                        _toggleAdmin(m.profileId, v),
                                  ),
                                ],
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                tooltip: 'Remover da equipe',
                                onPressed: () => _remove(m.profileId),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchResultsList extends StatelessWidget {
  const _SearchResultsList({required this.results, required this.onAdd});

  final List<MemberName> results;
  final void Function(String profileId) onAdd;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16),
        child: Text('Nenhum perfil aprovado encontrado.'),
      );
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 220),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: results.length,
        itemBuilder: (context, index) {
          final r = results[index];
          return ListTile(
            title: Text(r.displayLabel),
            trailing: FilledButton(
              onPressed: () => onAdd(r.id),
              child: const Text('Adicionar e liberar'),
            ),
          );
        },
      ),
    );
  }
}
