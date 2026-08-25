import 'package:flutter/material.dart';

import '../models/participant.dart';
import '../models/top.dart';
import '../services/supabase_service.dart';
import '../widgets/app_logo.dart';
import 'participant_form_screen.dart';

/// Lista os participantes cadastrados rapidamente num Top (ver
/// supabase/participants_and_attendance.sql), com busca e cadastro. Não
/// mistura com a lista de Senderistas com conta própria (top_senderistas) —
/// as duas telas coexistem por enquanto; unificação de UI fica pra quando o
/// vínculo linked_profile_id tiver uso real.
class ParticipantsScreen extends StatefulWidget {
  const ParticipantsScreen({super.key, required this.top});

  final Top top;

  @override
  State<ParticipantsScreen> createState() => _ParticipantsScreenState();
}

class _ParticipantsScreenState extends State<ParticipantsScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openRegisterForm() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => ParticipantFormScreen(top: widget.top)),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Participante cadastrado.')));
    }
  }

  void _showDetail(Participant p) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(p.displayLabel),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (p.participantCode != null) Text('Código: ${p.participantCode}'),
            if (p.phone != null) Text('Telefone: ${p.phone}'),
            if (p.emergencyContact != null)
              Text('Contato de emergência: ${p.emergencyContact}'),
            if (p.tagUid != null) Text('Tag NFC vinculada: ${p.tagUid}'),
            if (p.notes != null) ...[const SizedBox(height: 8), Text(p.notes!)],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AppBarLogoTitle(
          title: Text('Participantes · ${widget.top.name}'),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openRegisterForm,
        icon: const Icon(Icons.person_add),
        label: const Text('Cadastrar'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                labelText: 'Buscar por nome ou código',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Participant>>(
              stream: SupabaseService.instance.watchTopParticipants(
                widget.top.id,
              ),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final all = snapshot.data!;
                final filtered = _query.isEmpty
                    ? all
                    : all
                          .where(
                            (p) =>
                                p.fullName.toLowerCase().contains(_query) ||
                                (p.participantCode?.toLowerCase().contains(
                                      _query,
                                    ) ??
                                    false) ||
                                (p.nickname?.toLowerCase().contains(_query) ??
                                    false),
                          )
                          .toList();
                if (filtered.isEmpty) {
                  return Center(
                    child: Text(
                      all.isEmpty
                          ? 'Nenhum participante cadastrado ainda.'
                          : 'Nada encontrado.',
                    ),
                  );
                }
                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final p = filtered[index];
                    return ListTile(
                      leading: Icon(
                        p.tagUid != null ? Icons.nfc : Icons.person_outline,
                      ),
                      title: Text(p.displayLabel),
                      subtitle: p.participantCode != null
                          ? Text('Código: ${p.participantCode}')
                          : null,
                      onTap: () => _showDetail(p),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
