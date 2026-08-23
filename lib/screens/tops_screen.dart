import 'package:flutter/material.dart';

import '../models/profile.dart';
import '../models/top.dart';
import '../services/supabase_service.dart';
import '../widgets/app_logo.dart';
import 'admin/admin_home_screen.dart';
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
          if (_myProfile?.role == UserRole.admin || _myProfile?.isMasterAdmin == true)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings_outlined),
              tooltip: 'Administração',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AdminHomeScreen(isMasterAdmin: _myProfile?.isMasterAdmin ?? false),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => SupabaseService.instance.signOut(),
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
              return Center(child: Text('Erro ao carregar tops: ${snapshot.error}'));
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
                    MaterialPageRoute(builder: (_) => TopDetailScreen(top: top)),
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
