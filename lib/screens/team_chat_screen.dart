import 'package:flutter/material.dart';

import '../models/member_name.dart';
import '../models/team.dart';
import '../models/team_message.dart';
import '../models/top.dart';
import '../services/supabase_service.dart';
import '../widgets/app_logo.dart';

/// Chat de uma equipe (ou do canal geral) — isolado das outras equipes
/// pelo RLS de team_messages (ver supabase/teams.sql).
class TeamChatScreen extends StatefulWidget {
  const TeamChatScreen({super.key, required this.top, required this.team});

  final Top top;
  final Team team;

  @override
  State<TeamChatScreen> createState() => _TeamChatScreenState();
}

class _TeamChatScreenState extends State<TeamChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;
  String? _sendError;
  final Map<String, MemberName> _names = {};
  final Set<String> _namesLoading = {};

  /// Busca nome/número de quem ainda não conhecemos, conforme as
  /// mensagens vão chegando — evita rebuscar tudo a cada nova mensagem.
  Future<void> _resolveMissingNames(List<TeamMessage> messages) async {
    final missing = messages
        .map((m) => m.senderId)
        .toSet()
        .where((id) => !_names.containsKey(id) && !_namesLoading.contains(id))
        .toList();
    if (missing.isEmpty) return;
    _namesLoading.addAll(missing);
    try {
      final resolved = await SupabaseService.instance.fetchMemberNames(
        topId: widget.top.id,
        team: widget.team,
        profileIds: missing,
      );
      if (mounted) setState(() => _names.addAll(resolved));
    } catch (_) {
      // segue mostrando o id cru como fallback
    } finally {
      _namesLoading.removeAll(missing);
    }
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();
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
      );
      _messageController.clear();
    } catch (e) {
      if (mounted) setState(() => _sendError = 'Não foi possível enviar: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final myId = SupabaseService.instance.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        leading: const AppLogoAppBarLeading(),
        title: Text('Chat · ${widget.team.label}'),
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
                final messages = snapshot.data ?? [];
                if (messages.isEmpty) {
                  return const Center(
                    child: Text('Nenhuma mensagem ainda. Comece a conversa.'),
                  );
                }
                _resolveMissingNames(messages);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.jumpTo(
                      _scrollController.position.maxScrollExtent,
                    );
                  }
                });
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final m = messages[index];
                    final isMine = m.senderId == myId;
                    final senderLabel =
                        _names[m.senderId]?.displayLabel ?? m.senderId;
                    return Align(
                      alignment: isMine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75,
                        ),
                        decoration: BoxDecoration(
                          color: isMine
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!isMine)
                              Text(
                                senderLabel,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                            Text(m.body),
                          ],
                        ),
                      ),
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
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: 'Mensagem para ${widget.team.label}...',
                        border: const OutlineInputBorder(),
                      ),
                      minLines: 1,
                      maxLines: 4,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: _sending
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
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
