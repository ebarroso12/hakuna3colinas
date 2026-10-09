import 'package:flutter/material.dart';

import '../models/profile.dart';
import '../models/team.dart';
import '../models/team_message.dart';
import '../models/top.dart';
import '../services/supabase_service.dart';

/// Chat de uma equipe dentro de um Top. [TeamKey.geral] é o chat geral.
class TeamChatScreen extends StatefulWidget {
  const TeamChatScreen({
    super.key,
    required this.top,
    required this.team,
    this.isTeamAdmin = false,
  });

  final Top top;
  final TeamKey team;

  /// Admin da equipe pode marcar a mensagem como alerta. A RLS rejeita o
  /// insert de quem não for — isto aqui só evita mostrar um controle que
  /// resultaria em erro.
  final bool isTeamAdmin;

  @override
  State<TeamChatScreen> createState() => _TeamChatScreenState();
}

class _TeamChatScreenState extends State<TeamChatScreen> {
  final _controller = TextEditingController();
  Map<String, Profile> _profiles = {};
  bool _sending = false;
  bool _comoAlerta = false;
  String? _sendError;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Nomes de quem escreve. Falha aqui não é crítica: o chat cai de volta
  /// para o id cru do remetente.
  Future<void> _loadProfiles() async {
    try {
      final p = await SupabaseService.instance.fetchTeamProfiles(
        topId: widget.top.id,
        team: widget.team,
      );
      if (mounted) setState(() => _profiles = p);
    } catch (_) {
      // segue sem os nomes
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      await SupabaseService.instance.sendTeamMessage(
        topId: widget.top.id,
        team: widget.team,
        body: text,
        isAlert: _comoAlerta,
      );
      _controller.clear();
      if (mounted) setState(() => _comoAlerta = false);
    } catch (e) {
      if (mounted) setState(() => _sendError = 'Não foi possível enviar: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = SupabaseService.instance.currentUser?.id;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.team.label),
            Text(
              widget.top.name,
              style: Theme.of(context).textTheme.labelSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<TeamMessage>>(
              stream: SupabaseService.instance.watchTeamMessages(
                topId: widget.top.id,
                team: widget.team,
              ),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Não foi possível carregar o chat.\n${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final mensagens = snapshot.data!;
                if (mensagens.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        widget.team.isGeral
                            ? 'Nenhuma mensagem no chat geral ainda.'
                            : 'Nenhuma mensagem da equipe ${widget.team.label} ainda.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: mensagens.length,
                  itemBuilder: (context, i) {
                    final m = mensagens[i];
                    return _Bolha(
                      mensagem: m,
                      isMine: m.senderId == myId,
                      remetente:
                          _profiles[m.senderId]?.displayLabel ?? m.senderId,
                    );
                  },
                );
              },
            ),
          ),
          if (_sendError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                _sendError!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.isTeamAdmin)
                    CheckboxListTile(
                      value: _comoAlerta,
                      onChanged: (v) =>
                          setState(() => _comoAlerta = v ?? false),
                      title: const Text('Enviar como alerta'),
                      subtitle: const Text(
                        'Destaca a mensagem para toda a equipe',
                      ),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          decoration: const InputDecoration(
                            hintText: 'Mensagem',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _sending ? null : _send,
                        icon: _sending
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bolha extends StatelessWidget {
  const _Bolha({
    required this.mensagem,
    required this.isMine,
    required this.remetente,
  });

  final TeamMessage mensagem;
  final bool isMine;
  final String remetente;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hora = TimeOfDay.fromDateTime(mensagem.createdAt.toLocal())
        .format(context);

    final fundo = mensagem.isAlert
        ? scheme.errorContainer
        : isMine
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;
    final texto = mensagem.isAlert
        ? scheme.onErrorContainer
        : isMine
        ? scheme.onPrimaryContainer
        : scheme.onSurface;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: fundo,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (mensagem.isAlert)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.priority_high, size: 16, color: texto),
                  const SizedBox(width: 4),
                  Text(
                    'ALERTA',
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: texto, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            if (!isMine)
              Text(
                remetente,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: texto),
              ),
            Text(mensagem.body, style: TextStyle(color: texto)),
            Text(
              mensagem.editedAt != null ? '$hora · editada' : hora,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: texto.withValues(alpha: 0.7)),
            ),
          ],
        ),
      ),
    );
  }
}
