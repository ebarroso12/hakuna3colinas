import 'package:flutter/material.dart';

import '../models/profile.dart';
import '../models/top.dart';
import '../models/triage_rule.dart';
import '../offline/dados_do_top.dart';
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
    // Regras do DISCO, não da rede.
    //
    // `DadosDoTop.regras()` lê o cache local e só vai à rede se ele
    // estiver vazio. Antes esta tela buscava as duas coisas no servidor, e
    // sem sinal nem a cor de triagem aparecia — perdia-se a informação que
    // já estava no aparelho por causa da que não estava.
    final rules = await DadosDoTop.instance.regras();
    final senderistas = await SupabaseService.instance
        .fetchTopSenderistaProfiles(widget.top.id);
    return (senderistas, rules);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Senderistas · ${widget.top.name}'),
        actions: const [AppLogoTrailing()],
      ),
      body: FutureBuilder<(List<Profile>, List<TriageRule>)>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            // A lista de perfis vem do servidor e não tem cache local — só
            // `top_participants` é baixada para o disco. Então aqui não se
            // finge: diz o que não deu e aponta a tela que FUNCIONA sem
            // rede, em vez de deixar o Hakuna numa tela de erro sem saída.
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.wifi_off, size: 40),
                  const SizedBox(height: 12),
                  const Text(
                    'Esta lista precisa de internet.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Para atender agora, use "Participantes do Top": ela '
                    'funciona offline, tem a ficha completa e o registro '
                    'de atendimento.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Voltar ao Top'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => setState(() => _future = _load()),
                    child: const Text('Tentar de novo'),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '${snapshot.error}',
                    style: Theme.of(context).textTheme.labelSmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          }
          final (senderistas, rules) = snapshot.data!;
          if (senderistas.isEmpty) {
            return const Center(
              child: Text('Nenhum Senderista inscrito neste Top.'),
            );
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
                  MaterialPageRoute<void>(
                    builder: (_) => VitalSignsScreen(
                      top: widget.top,
                      profile: profile,
                      triageColor: color,
                    ),
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
