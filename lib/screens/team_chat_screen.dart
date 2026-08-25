import 'package:flutter/material.dart';

import '../models/member_name.dart';
import '../models/profile.dart';
import '../models/team.dart';
import '../models/team_membership.dart';
import '../models/team_message.dart';
import '../models/top.dart';
import '../services/supabase_service.dart';
import '../widgets/app_logo.dart';
import 'direct_message_screen.dart';

/// Chat de uma equipe (ou do canal geral) — isolado das outras equipes
/// pelo RLS de team_messages (ver supabase/teams.sql). Admin da equipe
/// modera (edita/apaga) qualquer mensagem e manda alertas em negrito;
/// tocar em alguém da lateral abre uma conversa privada com ela.
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
  bool _sendingAlert = false;
  String? _sendError;
  final Map<String, MemberName> _names = {};
  final Set<String> _namesLoading = {};
  bool _iAmTeamAdmin = false;

  @override
  void initState() {
    super.initState();
    _loadAdminStatus();
  }

  Future<void> _loadAdminStatus() async {
    try {
      final profile = await SupabaseService.instance.fetchMyProfile();
      final isGlobalAdmin =
          profile.role == UserRole.admin || profile.isMasterAdmin;
      var isTeamAdmin = isGlobalAdmin;
      if (!isTeamAdmin && widget.team.dbKey != null) {
        final memberships = await SupabaseService.instance
            .watchMyTeamMemberships(widget.top.id)
            .first;
        final mine = memberships.where((m) => m.team == widget.team);
        isTeamAdmin = mine.isNotEmpty && mine.first.isTeamAdmin;
      }
      if (mounted) setState(() => _iAmTeamAdmin = isTeamAdmin);
    } catch (_) {
      // segue sem privilégio de admin — o app só some com os botões extras
    }
  }

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

  Future<void> _send({bool asAlert = false}) async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sending || _sendingAlert) return;
    setState(() {
      if (asAlert) {
        _sendingAlert = true;
      } else {
        _sending = true;
      }
      _sendError = null;
    });
    try {
      if (asAlert) {
        await SupabaseService.instance.sendTeamAlert(
          topId: widget.top.id,
          team: widget.team,
          body: text,
        );
      } else {
        await SupabaseService.instance.sendTeamMessage(
          topId: widget.top.id,
          team: widget.team,
          body: text,
        );
      }
      _messageController.clear();
    } catch (e) {
      if (mounted) setState(() => _sendError = 'Não foi possível enviar: $e');
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _sendingAlert = false;
        });
      }
    }
  }

  Future<void> _editMessage(TeamMessage message) async {
    final controller = TextEditingController(text: message.body);
    final newBody = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Editar mensagem'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (newBody == null || newBody.isEmpty || newBody == message.body) return;
    try {
      await SupabaseService.instance.editTeamMessage(
        messageId: message.id,
        body: newBody,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Não foi possível editar: $e')));
      }
    }
  }

  Future<void> _deleteMessage(TeamMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Apagar mensagem?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await SupabaseService.instance.deleteTeamMessage(message.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Não foi possível apagar: $e')));
      }
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
        title: AppBarLogoTitle(title: Text('Chat · ${widget.team.label}')),
      ),
      endDrawer: widget.team == Team.geral
          ? null
          : Drawer(
              child: SafeArea(
                child: StreamBuilder<List<TeamMembership>>(
                  stream: SupabaseService.instance.watchTeamRoster(
                    topId: widget.top.id,
                    team: widget.team,
                  ),
                  builder: (context, snapshot) {
                    final others = (snapshot.data ?? [])
                        .where(
                          (m) =>
                              m.released && !m.blocked && m.profileId != myId,
                        )
                        .toList();
                    return FutureBuilder<Map<String, MemberName>>(
                      future: SupabaseService.instance.fetchMemberNames(
                        topId: widget.top.id,
                        team: widget.team,
                        profileIds: others.map((m) => m.profileId).toList(),
                      ),
                      builder: (context, namesSnapshot) {
                        final names = namesSnapshot.data ?? {};
                        return ListView(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                'Membros de ${widget.team.label}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            for (final m in others)
                              ListTile(
                                leading: const CircleAvatar(
                                  child: Icon(Icons.person),
                                ),
                                title: Text(
                                  names[m.profileId]?.fullName ?? m.profileId,
                                ),
                                trailing: const Icon(Icons.mail_outline),
                                onTap: () {
                                  final name = names[m.profileId];
                                  Navigator.of(context).pop();
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => DirectMessageScreen(
                                        top: widget.top,
                                        otherId: m.profileId,
                                        otherLabel:
                                            name?.displayLabel ?? m.profileId,
                                        otherFirstName:
                                            name?.fullName ?? m.profileId,
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        );
                      },
                    );
                  },
                ),
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
                          color: m.isAlert
                              ? Colors.red.shade100
                              : (isMine
                                    ? Theme.of(context)
                                          .colorScheme
                                          .primaryContainer
                                    : Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest),
                          borderRadius: BorderRadius.circular(12),
                          border: m.isAlert
                              ? Border.all(color: Colors.red)
                              : null,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (m.isAlert)
                                  const Padding(
                                    padding: EdgeInsets.only(right: 4),
                                    child: Icon(
                                      Icons.warning_amber,
                                      size: 16,
                                      color: Colors.red,
                                    ),
                                  ),
                                if (!isMine)
                                  Text(
                                    senderLabel,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(fontWeight: FontWeight.bold),
                                  ),
                              ],
                            ),
                            Text(
                              m.body,
                              style: m.isAlert
                                  ? const TextStyle(fontWeight: FontWeight.bold)
                                  : null,
                            ),
                            if (m.editedAt != null)
                              Text(
                                'editado',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(fontStyle: FontStyle.italic),
                              ),
                            if (_iAmTeamAdmin)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  InkWell(
                                    onTap: () => _editMessage(m),
                                    child: const Padding(
                                      padding: EdgeInsets.only(
                                        top: 4,
                                        right: 8,
                                      ),
                                      child: Icon(Icons.edit, size: 14),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () => _deleteMessage(m),
                                    child: const Padding(
                                      padding: EdgeInsets.only(top: 4),
                                      child: Icon(
                                        Icons.delete_outline,
                                        size: 14,
                                      ),
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
                  if (widget.team != Team.geral)
                    Builder(
                      builder: (context) => IconButton(
                        icon: const Icon(Icons.groups_outlined),
                        tooltip: 'Membros da equipe',
                        onPressed: () => Scaffold.of(context).openEndDrawer(),
                      ),
                    ),
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
                  if (_iAmTeamAdmin)
                    IconButton(
                      tooltip: 'Enviar como alerta (negrito)',
                      onPressed: _sendingAlert
                          ? null
                          : () => _send(asAlert: true),
                      icon: _sendingAlert
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.warning_amber, color: Colors.red),
                    ),
                  IconButton.filled(
                    onPressed: _sending ? null : () => _send(),
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
