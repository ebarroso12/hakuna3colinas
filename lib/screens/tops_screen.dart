import 'package:flutter/material.dart';

import '../models/profile.dart';
import '../models/top.dart';
import '../services/supabase_service.dart';
import '../widgets/app_logo.dart';
import 'admin/admin_home_screen.dart';
import 'change_password_screen.dart';
import 'top_detail_screen.dart';

/// Lista os "Tops" (eventos) aos quais o usuário logado está vinculado,
/// seja como Hakuna liberado ou como Senderista inscrito.
class TopsScreen extends StatefulWidget {
  const TopsScreen({super.key});

  @override
  State<TopsScreen> createState() => _TopsScreenState();
}

class _TopsScreenState extends State<TopsScreen> {
  late Future<List<Top>> _topsFuture;
  Profile? _myProfile;

  @override
  void initState() {
    super.initState();
    _topsFuture = SupabaseService.instance.fetchMyTops();
    SupabaseService.instance.fetchMyProfile().then((p) {
      if (mounted) setState(() => _myProfile = p);
    });
  }

  Future<void> _refresh() async {
    setState(() => _topsFuture = SupabaseService.instance.fetchMyTops());
    await _topsFuture;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppLogoAppBarLeading(),
        title: const Text('Meus Tops'),
        actions: [
          if (_myProfile?.role == UserRole.admin ||
              _myProfile?.isMasterAdmin == true)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings_outlined),
              tooltip: 'Administração',
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AdminHomeScreen(
                      isMasterAdmin: _myProfile?.isMasterAdmin ?? false,
                    ),
                  ),
                );
                // A lista não recarrega sozinha ao voltar do painel de admin
                // (initState só roda uma vez) — sem isso, um Top recém
                // criado/editado só aparecia depois de recarregar a página.
                if (mounted) _refresh();
              },
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'change_password') {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ChangePasswordScreen(),
                  ),
                );
              } else if (value == 'sign_out') {
                SupabaseService.instance.signOut();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'change_password',
                child: Text('Trocar senha'),
              ),
              PopupMenuItem(value: 'sign_out', child: Text('Sair')),
            ],
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Top>>(
          future: _topsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text('Erro ao carregar tops: ${snapshot.error}'),
              );
            }
            final tops = snapshot.data ?? [];
            if (tops.isEmpty) {
              return const Center(child: Text('Nenhum Top vinculado ainda.'));
            }
            return ListView.builder(
              itemCount: tops.length,
              itemBuilder: (context, index) {
                final top = tops[index];
                return ListTile(
                  title: Text(top.name),
                  subtitle: Text(top.status.name),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TopDetailScreen(top: top),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
