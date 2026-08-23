import 'package:flutter/material.dart';

import '../../models/profile.dart';
import '../../services/admin_service.dart';
import '../../widgets/app_logo.dart';
import 'admin_user_edit_screen.dart';

/// Lista de todos os usuários do app, pra gestão de papéis/atribuições
/// pelo admin. A linha do admin master aparece travada (cadeado) pra quem
/// não é o próprio admin master — o banco já bloqueia a edição via RLS,
/// isso aqui só evita abrir uma tela que só vai dar erro.
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key, required this.isMasterAdmin});

  final bool isMasterAdmin;

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  late Future<List<Profile>> _future;

  @override
  void initState() {
    super.initState();
    _future = AdminService.instance.fetchAllProfiles();
  }

  void _reload() => setState(() => _future = AdminService.instance.fetchAllProfiles());

  Future<void> _approve(Profile profile) async {
    try {
      await AdminService.instance.approveProfile(profile.id);
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível aprovar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppLogoAppBarLeading(),
        title: const Text('Usuários'),
      ),
      body: FutureBuilder<List<Profile>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erro ao carregar: ${snapshot.error}'));
          }
          // Pendentes de aprovação primeiro — é a fila que o admin master
          // precisa ver de cara toda vez que abre a tela.
          final profiles = [...snapshot.data ?? []]
            ..sort((a, b) => a.approved == b.approved ? 0 : (a.approved ? 1 : -1));
          return ListView.builder(
            itemCount: profiles.length,
            itemBuilder: (context, index) {
              final profile = profiles[index];
              final locked = profile.isMasterAdmin && !widget.isMasterAdmin;
              return ListTile(
                title: Text(profile.displayLabel),
                subtitle: Text(
                  profile.isMasterAdmin
                      ? 'Admin Master'
                      : '${profile.role.name}${profile.approved ? '' : ' · pendente de aprovação'}',
                  style: profile.approved ? null : const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                ),
                trailing: !profile.approved
                    ? FilledButton(onPressed: () => _approve(profile), child: const Text('Aprovar'))
                    : (locked ? const Icon(Icons.lock_outline) : const Icon(Icons.chevron_right)),
                onTap: locked
                    ? null
                    : () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => AdminUserEditScreen(profile: profile, isMasterAdmin: widget.isMasterAdmin),
                          ),
                        );
                        _reload();
                      },
              );
            },
          );
        },
      ),
    );
  }
}
