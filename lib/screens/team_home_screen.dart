import 'package:flutter/material.dart';

import '../models/profile.dart';
import '../models/team.dart';
import '../models/team_membership.dart';
import '../models/top.dart';
import '../services/supabase_service.dart';
import '../widgets/app_logo.dart';
import 'team_chat_screen.dart';
import 'team_members_screen.dart';

/// Tela inicial de uma equipe: chat da equipe e, pra quem administra
/// (ou é admin global do app), gestão de membros.
class TeamHomeScreen extends StatefulWidget {
  const TeamHomeScreen({super.key, required this.top, required this.team});

  final Top top;
  final Team team;

  @override
  State<TeamHomeScreen> createState() => _TeamHomeScreenState();
}

class _TeamHomeScreenState extends State<TeamHomeScreen> {
  Profile? _myProfile;

  @override
  void initState() {
    super.initState();
    SupabaseService.instance
        .fetchMyProfile()
        .then((p) {
          if (mounted) setState(() => _myProfile = p);
        })
        .catchError((_) {});
  }

  bool get _isGlobalAdmin =>
      _myProfile?.role == UserRole.admin || _myProfile?.isMasterAdmin == true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppLogoAppBarLeading(),
        title: Text(widget.team.label),
      ),
      body: StreamBuilder<List<TeamMembership>>(
        stream: SupabaseService.instance.watchMyTeamMemberships(widget.top.id),
        builder: (context, snapshot) {
          final myRow = (snapshot.data ?? [])
              .where((m) => m.team == widget.team)
              .toList();
          final iAmTeamAdmin = myRow.isNotEmpty && myRow.first.isTeamAdmin;
          final showManage =
              widget.team != Team.geral && (iAmTeamAdmin || _isGlobalAdmin);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: const Icon(Icons.chat),
                  title: const Text('Chat da equipe'),
                  subtitle: Text('Conversa exclusiva de ${widget.team.label}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          TeamChatScreen(top: widget.top, team: widget.team),
                    ),
                  ),
                ),
              ),
              if (showManage)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.manage_accounts),
                    title: const Text('Gerenciar membros'),
                    subtitle: const Text('Liberar, promover ou remover'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TeamMembersScreen(
                          top: widget.top,
                          team: widget.team,
                        ),
                      ),
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
