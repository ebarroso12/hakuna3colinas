import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import '../models/profile.dart';
import '../models/top.dart';
import '../offline/chat_repositorio.dart';
import '../services/supabase_service.dart';
import '../widgets/app_logo.dart';

/// Chat em tempo real entre os Hakunas liberados de um Top. Cada mensagem
/// é visível pra todo Hakuna do mesmo evento assim que é enviada — a mesma
/// função que se cogitou resolver com o Chatwoot, mas aqui usando o
/// Realtime que já roda no projeto, sem misturar com o CRM da clínica.
class TopChatScreen extends StatefulWidget {
  const TopChatScreen({
    super.key,
    required this.top,
    required this.hakunaProfiles,
  });

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
      // Fila local, não rede. Ver `ChatRepositorio`.
      await ChatRepositorio.instance.enviarParaTop(
        topId: widget.top.id,
        body: text,
      );
      _messageController.clear();
    } catch (e) {
      if (mounted) {
        setState(() => _sendError = 'Não foi possível guardar no aparelho: $e');
      }
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
        title: Text('Chat · ${widget.top.name}'),
        actions: const [AppLogoTrailing()],
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<ChatNaTela<ChatMessage>>(
              stream: ChatRepositorio.instance.observarTop(widget.top.id),
              builder: (context, snapshot) {
                final chat = snapshot.data;
                final messages = chat?.mensagens ?? const <ChatMessage>[];
                if (messages.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        (chat?.offline ?? false)
                            ? 'Sem conexão com o chat. O que você enviar '
                                  'agora fica guardado no aparelho e sobe '
                                  'quando o sinal voltar.'
                            : 'Nenhuma mensagem ainda. Comece a conversa.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
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
                        widget.hakunaProfiles[m.senderId]?.displayLabel ??
                        m.senderId;
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
                            // Relógio enquanto não entregue: no mato o
                            // Hakuna precisa saber que a mensagem ainda
                            // não saiu do aparelho.
                            if (m.pendente)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.schedule, size: 12),
                                  const SizedBox(width: 3),
                                  Text(
                                    'aguardando sinal',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          fontStyle: FontStyle.italic,
                                        ),
                                  ),
                                ],
                              ),
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
