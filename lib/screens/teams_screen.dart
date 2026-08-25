import 'package:flutter/material.dart';

import '../models/profile.dart';
import '../models/team.dart';
import '../models/team_membership.dart';
import '../models/top.dart';
import '../services/supabase_service.dart';
import '../widgets/app_logo.dart';
import 'team_home_screen.dart';
import 'top_chat_screen.dart';

/// Lista as 9 equipes de "Legendários 3 Colinas" + o canal geral. Cada
/// equipe é isolada das outras — só quem foi liberado pelo admin daquela
/// equipe entra. Hakunas usa a infraestrutura própria já existente.
class TeamsScreen extends StatefulWidget {
  const TeamsScreen({super.key, required this.top});

  final Top top;

  @override
  State<TeamsScreen> createState() => _TeamsScreenState();
}

class _TeamsScreenState extends State<TeamsScreen> {
  Profile? _myProfile;
  Map<String, Profile> _hakunaProfiles = {};

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadHakunaProfiles();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await SupabaseService.instance.fetchMyProfile();
      if (mounted) setState(() => _myProfile = profile);
    } catch (_) {
      // segue sem perfil — o card de Hakunas some, o resto funciona normal
    }
  }

  Future<void> _loadHakunaProfiles() async {
    try {
      final profiles = await SupabaseService.instance.fetchHakunaProfiles(
        widget.top.id,
      );
      if (mounted) setState(() => _hakunaProfiles = profiles);
    } catch (_) {
      // segue sem — o card de Hakunas mostra o chat sem os nomes dos outros
    }
  }

  bool get _isHakuna =>
      _myProfile?.role == UserRole.hakuna || _myProfile?.role == UserRole.admin;

  /// Admin global do app enxerga e entra em qualquer equipe — o RLS já
  /// dá esse acesso no banco (is_admin() em toda policy de equipe), mas a
  /// tela antes só liberava o toque em quem tinha a própria linha
  /// released em top_team_members, escondendo o chat até de quem
  /// administra tudo.
  bool get _isGlobalAdmin =>
      _myProfile?.role == UserRole.admin || _myProfile?.isMasterAdmin == true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: AppBarLogoTitle(title: const Text('Equipes'))),
      body: StreamBuilder<List<TeamMembership>>(
        stream: SupabaseService.instance.watchMyTeamMemberships(widget.top.id),
        builder: (context, snapshot) {
          final myMemberships = {
            for (final m in snapshot.data ?? <TeamMembership>[]) m.team: m,
          };
          return ListView(
            padding: const EdgeInsets.all(12),
            children: [
              _TeamTile(
                team: Team.geral,
                subtitle: 'Aberta a todos os aprovados neste Top',
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        TeamHomeScreen(top: widget.top, team: Team.geral),
                  ),
                ),
              ),
              const Divider(height: 24),
              for (final team in Team.exclusive)
                if (team == Team.hakunas)
                  _TeamTile(
                    team: team,
                    subtitle: _isHakuna
                        ? 'Você é Hakuna liberado neste Top'
                        : 'Peça a um admin pra ser liberado como Hakuna',
                    trailing: _isHakuna
                        ? const Icon(Icons.chevron_right)
                        : null,
                    onTap: _isHakuna
                        ? () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => TopChatScreen(
                                top: widget.top,
                                hakunaProfiles: _hakunaProfiles,
                              ),
                            ),
                          )
                        : null,
                  )
                else
                  Builder(
                    builder: (context) {
                      final membership = myMemberships[team];
                      final released = membership?.released ?? false;
                      final canEnter = released || _isGlobalAdmin;
                      final subtitle = released
                          ? (membership!.isTeamAdmin
                                ? 'Você administra esta equipe'
                                : 'Você faz parte desta equipe')
                          : (_isGlobalAdmin
                                ? 'Você não participa, mas administra o app'
                                : 'Você não participa — peça a um admin da equipe');
                      return _TeamTile(
                        team: team,
                        subtitle: subtitle,
                        trailing: canEnter
                            ? const Icon(Icons.chevron_right)
                            : null,
                        onTap: canEnter
                            ? () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => TeamHomeScreen(
                                    top: widget.top,
                                    team: team,
                                  ),
                                ),
                              )
                            : null,
                      );
                    },
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _TeamTile extends StatelessWidget {
  const _TeamTile({
    required this.team,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  final Team team;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: Icon(team.icon),
        title: Text(team.label),
        subtitle: Text(subtitle),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}
