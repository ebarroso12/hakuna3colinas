import 'package:flutter/material.dart';

import '../models/chat_message.dart';
import '../models/profile.dart';
import '../models/top.dart';
import '../services/supabase_service.dart';
import '../widgets/app_logo.dart';
import 'direct_message_screen.dart';

/// Chat em tempo real entre os Hakunas liberados de um Top. Cada mensagem
/// é visível pra todo Hakuna do mesmo evento assim que é enviada — a mesma
/// função que se cogitou resolver com o Chatwoot, mas aqui usando o
/// Realtime que já roda no projeto, sem misturar com o CRM da clínica.
///
/// Sidebar (Drawer) lista quem está na conversa, com acesso a mensagem
/// privada. @menção (ex: "@Dredsonbarroso" — ver Profile.mentionHandle)
/// sinaliza a pessoa chamada com uma notificação (Fase 8).
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
  List<Profile> _mentionSuggestions = const [];

  List<Profile> get _otherHakunas {
    final myId = SupabaseService.instance.currentUser?.id;
    return widget.hakunaProfiles.values.where((p) => p.id != myId).toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
  }

  /// Handle -> Profile, pra resolver @menções digitadas de volta pro id
  /// real da pessoa (a busca é sempre pelo id escolhido, não pelo texto —
  /// uma colisão de apelido entre duas pessoas não troca o destinatário).
  Map<String, Profile> get _handleIndex => {
    for (final p in widget.hakunaProfiles.values)
      p.mentionHandle.toLowerCase(): p,
  };

  void _onMessageChanged(String text) {
    final cursor = _messageController.selection.baseOffset;
    final upToCursor = cursor < 0 ? text : text.substring(0, cursor);
    final lastAt = upToCursor.lastIndexOf('@');
    if (lastAt == -1 || upToCursor.substring(lastAt).contains(' ')) {
      if (_mentionSuggestions.isNotEmpty)
        setState(() => _mentionSuggestions = const []);
      return;
    }
    final query = upToCursor.substring(lastAt + 1).toLowerCase();
    final matches = _otherHakunas
        .where((p) => p.mentionHandle.toLowerCase().startsWith(query))
        .take(5)
        .toList();
    setState(() => _mentionSuggestions = matches);
  }

  void _applyMention(Profile profile) {
    final text = _messageController.text;
    final cursor = _messageController.selection.baseOffset;
    final upToCursor = cursor < 0 ? text : text.substring(0, cursor);
    final lastAt = upToCursor.lastIndexOf('@');
    if (lastAt == -1) return;
    final newText =
        '${text.substring(0, lastAt)}@${profile.mentionHandle} ${text.substring(cursor < 0 ? text.length : cursor)}';
    final newCursor = lastAt + profile.mentionHandle.length + 2;
    _messageController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursor),
    );
    setState(() => _mentionSuggestions = const []);
  }

  /// Extrai quem foi @mencionado numa mensagem (resolvido pelo apelido
  /// conhecido dos Hakunas do Top) e manda uma notificação pra cada um —
  /// esse é o "sinal" de quem foi chamado.
  void _notifyMentions(String body) {
    final handleIndex = _handleIndex;
    final myId = SupabaseService.instance.currentUser?.id;
    final myLabel = widget.hakunaProfiles[myId]?.displayLabel ?? 'Um Hakuna';
    for (final match in RegExp(r'@(\w+)').allMatches(body)) {
      final mentioned = handleIndex[match.group(1)!.toLowerCase()];
      if (mentioned == null || mentioned.id == myId) continue;
      SupabaseService.instance
          .createNotification(
            topId: widget.top.id,
            type: 'mensagem',
            title: 'Você foi mencionado no chat',
            body: '$myLabel: $body',
            recipientId: mentioned.id,
          )
          .catchError((_) {});
    }
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _sendError = null;
      _mentionSuggestions = const [];
    });
    try {
      await SupabaseService.instance.sendTopMessage(
        topId: widget.top.id,
        body: text,
      );
      _notifyMentions(text);
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

  /// Renderiza o texto da mensagem destacando @menções que batem com um
  /// Hakuna conhecido do Top.
  Widget _messageBody(String body, {required bool isMine}) {
    final handles = _handleIndex;
    final spans = <TextSpan>[];
    var lastEnd = 0;
    for (final match in RegExp(r'@(\w+)').allMatches(body)) {
      final isKnown = handles.containsKey(match.group(1)!.toLowerCase());
      if (match.start > lastEnd)
        spans.add(TextSpan(text: body.substring(lastEnd, match.start)));
      spans.add(
        TextSpan(
          text: match.group(0),
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isKnown
                ? (isMine ? Colors.indigo.shade900 : Colors.indigo)
                : null,
          ),
        ),
      );
      lastEnd = match.end;
    }
    if (lastEnd < body.length)
      spans.add(TextSpan(text: body.substring(lastEnd)));
    return RichText(
      text: TextSpan(
        style: DefaultTextStyle.of(context).style,
        children: spans,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myId = SupabaseService.instance.currentUser?.id;

    return Scaffold(
      appBar: AppBar(
        leading: const AppLogoAppBarLeading(),
        title: Text('Chat · ${widget.top.name}'),
      ),
      endDrawer: Drawer(
        child: SafeArea(
          child: ListView(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Hakunas neste Top',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              for (final p in _otherHakunas)
                ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text(p.fullName),
                  subtitle: Text('@${p.mentionHandle}'),
                  trailing: const Icon(Icons.mail_outline),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            DirectMessageScreen(top: widget.top, other: p),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<ChatMessage>>(
              stream: SupabaseService.instance.watchTopMessages(widget.top.id),
              builder: (context, snapshot) {
                final messages = snapshot.data ?? [];
                if (messages.isEmpty) {
                  return const Center(
                    child: Text('Nenhuma mensagem ainda. Comece a conversa.'),
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
                    if (m.isSystem) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Center(
                          child: Text(
                            m.body,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(fontStyle: FontStyle.italic),
                          ),
                        ),
                      );
                    }
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
                            _messageBody(m.body, isMine: isMine),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (_mentionSuggestions.isNotEmpty)
            Container(
              constraints: const BoxConstraints(maxHeight: 160),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Theme.of(context).dividerColor),
                ),
              ),
              child: ListView(
                shrinkWrap: true,
                children: _mentionSuggestions
                    .map(
                      (p) => ListTile(
                        dense: true,
                        title: Text(p.fullName),
                        subtitle: Text('@${p.mentionHandle}'),
                        onTap: () => _applyMention(p),
                      ),
                    )
                    .toList(),
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
                  Builder(
                    builder: (context) => IconButton(
                      icon: const Icon(Icons.groups_outlined),
                      tooltip: 'Quem está na conversa',
                      onPressed: () => Scaffold.of(context).openEndDrawer(),
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        hintText: 'Mensagem para os Hakunas do Top... use @ pra chamar alguém',
                        border: OutlineInputBorder(),
                      ),
                      minLines: 1,
                      maxLines: 4,
                      onChanged: _onMessageChanged,
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
