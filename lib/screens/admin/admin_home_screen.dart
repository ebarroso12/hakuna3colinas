import 'package:flutter/material.dart';

import '../../widgets/app_logo.dart';
import 'admin_tops_screen.dart';
import 'admin_triage_rules_screen.dart';
import 'admin_users_screen.dart';

/// Painel do admin/admin master: usuários, Tops e regras de triagem.
class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key, required this.isMasterAdmin});

  final bool isMasterAdmin;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppLogoAppBarLeading(),
        title: const Text('Administração'),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.people),
            title: const Text('Usuários'),
            subtitle: const Text('Papéis, atribuições, dados de triagem'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => AdminUsersScreen(isMasterAdmin: isMasterAdmin)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.hiking),
            title: const Text('Tops'),
            subtitle: const Text('Criar, editar, gerenciar equipe'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AdminTopsScreen()),
            ),
          ),
          if (isMasterAdmin)
            ListTile(
              leading: const Icon(Icons.rule),
              title: const Text('Regras de triagem'),
              subtitle: const Text('Idade e comorbidades por cor'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AdminTriageRulesScreen()),
              ),
            ),
        ],
      ),
    );
  }
}
