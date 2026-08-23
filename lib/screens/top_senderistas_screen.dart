import 'package:flutter/material.dart';

import '../models/profile.dart';
import '../models/top.dart';
import '../models/triage_rule.dart';
import '../services/supabase_service.dart';
import '../services/triage_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/triage_badge.dart';
import 'vital_signs_screen.dart';

/// Lista os Senderistas inscritos num Top, com a cor de triagem de cada um,
/// pra o Hakuna escolher em quem registrar sinais vitais.
class TopSenderistasScreen extends StatefulWidget {
  const TopSenderistasScreen({super.key, required this.top});

  final Top top;

  @override
  State<TopSenderistasScreen> createState() => _TopSenderistasScreenState();
}

class _TopSenderistasScreenState extends State<TopSenderistasScreen> {
  late Future<(List<Profile>, List<TriageRule>)> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<(List<Profile>, List<TriageRule>)> _load() async {
    final senderistas = await SupabaseService.instance.fetchTopSenderistaProfiles(widget.top.id);
    final rules = await SupabaseService.instance.fetchActiveTriageRules();
    return (senderistas, rules);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppLogoAppBarLeading(),
        title: Text('Senderistas · ${widget.top.name}'),
      ),
      body: FutureBuilder<(List<Profile>, List<TriageRule>)>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erro ao carregar: ${snapshot.error}'));
          }
          final (senderistas, rules) = snapshot.data!;
          if (senderistas.isEmpty) {
            return const Center(child: Text('Nenhum Senderista inscrito neste Top.'));
          }
          return ListView.builder(
            itemCount: senderistas.length,
            itemBuilder: (context, index) {
              final profile = senderistas[index];
              final color = TriageService.colorFor(profile, rules);
              return ListTile(
                title: Text(profile.displayLabel),
                trailing: TriageBadge(color: color),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => VitalSignsScreen(top: widget.top, profile: profile, triageColor: color),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
