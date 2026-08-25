import 'package:flutter/material.dart';

import '../../models/top.dart';
import '../../services/supabase_service.dart';
import '../../widgets/app_logo.dart';
import 'admin_top_form_screen.dart';

/// Lista de todos os Tops pro admin criar/editar. A RLS já libera SELECT
/// de todos os Tops pra admin (não só os vinculados), então reaproveita
/// fetchMyTops em vez de duplicar a query.
class AdminTopsScreen extends StatefulWidget {
  const AdminTopsScreen({super.key});

  @override
  State<AdminTopsScreen> createState() => _AdminTopsScreenState();
}

class _AdminTopsScreenState extends State<AdminTopsScreen> {
  late Future<List<Top>> _future;

  @override
  void initState() {
    super.initState();
    _future = SupabaseService.instance.fetchMyTops();
  }

  void _reload() =>
      setState(() => _future = SupabaseService.instance.fetchMyTops());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: AppBarLogoTitle(title: const Text('Tops'))),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          await Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const AdminTopFormScreen()));
          _reload();
        },
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<Top>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erro ao carregar: ${snapshot.error}'));
          }
          final tops = snapshot.data ?? [];
          if (tops.isEmpty) {
            return const Center(child: Text('Nenhum Top cadastrado ainda.'));
          }
          return ListView.builder(
            itemCount: tops.length,
            itemBuilder: (context, index) {
              final top = tops[index];
              return ListTile(
                title: Text(top.name),
                subtitle: Text(
                  [
                    if (top.topNumber != null) 'nº ${top.topNumber}',
                    top.status.name,
                  ].join(' · '),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AdminTopFormScreen(top: top),
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
