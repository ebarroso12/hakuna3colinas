import 'package:flutter/material.dart';

import '../../models/profile.dart';
import '../../models/team.dart';
import '../../models/top.dart';
import '../../services/admin_service.dart';
import '../../widgets/app_logo.dart';
import '../team_members_screen.dart';

/// Gestão de quem está liberado como Hakuna e quem está inscrito como
/// Senderista num Top — "delegar função" e "trocar atribuição de todos".
class AdminTopMembersScreen extends StatefulWidget {
  const AdminTopMembersScreen({super.key, required this.top});

  final Top top;

  @override
  State<AdminTopMembersScreen> createState() => _AdminTopMembersScreenState();
}

class _AdminTopMembersScreenState extends State<AdminTopMembersScreen> {
  late Future<_MembersData> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_MembersData> _load() async {
    final profiles = await AdminService.instance.fetchAllProfiles();
    final hakunaAssignments = await AdminService.instance
        .fetchTopHakunaAssignments(widget.top.id);
    final senderistaIds = await AdminService.instance.fetchTopSenderistaIds(
      widget.top.id,
    );
    return _MembersData(
      profiles: profiles,
      hakunaAssignments: hakunaAssignments,
      senderistaIds: senderistaIds,
    );
  }

  Future<void> _toggleHakuna(Profile profile, bool released) async {
    await AdminService.instance.setHakunaReleased(
      topId: widget.top.id,
      profileId: profile.id,
      released: released,
    );
    setState(() => _future = _load());
  }

  Future<void> _toggleSenderista(Profile profile, bool registered) async {
    if (registered) {
      await AdminService.instance.registerSenderista(
        topId: widget.top.id,
        profileId: profile.id,
      );
    } else {
      await AdminService.instance.removeSenderistaFromTop(
        topId: widget.top.id,
        profileId: profile.id,
      );
    }
    setState(() => _future = _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppLogoAppBarLeading(),
        title: Text('Equipe · ${widget.top.name}'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Equipes — inicializar admin de cada uma',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final team in Team.exclusive)
                      if (!team.hasOwnInfrastructure)
                        OutlinedButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => TeamMembersScreen(
                                top: widget.top,
                                team: team,
                              ),
                            ),
                          ),
                          icon: Icon(team.icon, size: 18),
                          label: Text(team.label),
                        ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 24),
          Expanded(
            child: FutureBuilder<_MembersData>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Erro ao carregar: ${snapshot.error}'),
                  );
                }
                final data = snapshot.data!;
                return ListView.builder(
                  itemCount: data.profiles.length,
                  itemBuilder: (context, index) {
                    final profile = data.profiles[index];
                    final isHakunaReleased =
                        data.hakunaAssignments[profile.id] ?? false;
                    final isSenderista = data.senderistaIds.contains(
                      profile.id,
                    );
                    return ListTile(
                      title: Text(profile.displayLabel),
                      subtitle: Text(profile.role.name),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Column(
                            children: [
                              const Text(
                                'Hakuna',
                                style: TextStyle(fontSize: 11),
                              ),
                              Switch(
                                value: isHakunaReleased,
                                onChanged: (v) => _toggleHakuna(profile, v),
                              ),
                            ],
                          ),
                          const SizedBox(width: 8),
                          Column(
                            children: [
                              const Text(
                                'Senderista',
                                style: TextStyle(fontSize: 11),
                              ),
                              Switch(
                                value: isSenderista,
                                onChanged: (v) => _toggleSenderista(profile, v),
                              ),
                            ],
                          ),
                        ],
                      ),
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

class _MembersData {
  _MembersData({
    required this.profiles,
    required this.hakunaAssignments,
    required this.senderistaIds,
  });

  final List<Profile> profiles;
  final Map<String, bool> hakunaAssignments;
  final Set<String> senderistaIds;
}
