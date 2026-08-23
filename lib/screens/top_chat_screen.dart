import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import '../models/profile.dart';
import '../models/top.dart';
import '../services/supabase_service.dart';
import '../widgets/app_logo.dart';

/// Chat em tempo real entre os Hakunas liberados de um Top. Cada mensagem
/// é visível pra todo Hakuna do mesmo evento assim que é enviada — a mesma
/// função que se cogitou resolver com o Chatwoot, mas aqui usando o
/// Realtime que já roda no projeto, sem misturar com o CRM da clínica.
class TopChatScreen extends StatefulWidget {
  const TopChatScreen({super.key, required this.top, required this.hakunaProfiles});

  final Top top;
  final Map<String, Profile> hakunaProfiles;

  @override
  State<TopChatScreen> createState() => _TopChatScreenState();
}

class _TopChatScreenState extends State<TopChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;
  String? _sendError;

  Future<void> _send() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      await SupabaseService.instance.sendTopMessage(topId: widget.top.id, body: text);
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
        title: Text('Chat · ${widget.top.name}'),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: SupabaseService.instance.watchTopMessages(widget.top.id),
              builder: (context, snapshot) {
                final messages = snapshot.data ?? [];
                if (messages.isEmpty) {
                  return const Center(child: Text('Nenhuma mensagem ainda. Comece a conversa.'));
                }
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
                  }
                });
                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(12),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final m = messages[index];
                    final isMine = m.senderId == myId;
                    final senderLabel = widget.hakunaProfiles[m.senderId]?.displayLabel ?? m.senderId;
                    return Align(
                      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
                        decoration: BoxDecoration(
                          color: isMine
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(context).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!isMine)
                              Text(
                                senderLabel,
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold),
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
              child: Text(_sendError!, style: const TextStyle(color: Colors.red)),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        hintText: 'Mensagem para os Hakunas do Top...',
                        border: OutlineInputBorder(),
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
                        ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2))
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
