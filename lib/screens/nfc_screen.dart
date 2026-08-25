import 'package:flutter/material.dart';

import '../models/participant.dart';
import '../models/top.dart';
import '../services/nfc_service.dart';
import '../services/supabase_service.dart';
import '../widgets/app_logo.dart';

/// Tela de TAG/NFC — ler/identificar, vincular a um participante e
/// desvincular. A tag física guarda só um token opaco (UUID gerado pelo
/// banco, não previsível); nome, contato etc. ficam só no Supabase,
/// resolvidos a partir do token. Ver supabase/participants_and_attendance.sql.
class NfcScreen extends StatefulWidget {
  const NfcScreen({super.key, required this.top});

  final Top top;

  @override
  State<NfcScreen> createState() => _NfcScreenState();
}

class _NfcScreenState extends State<NfcScreen> {
  bool _busy = false;
  String? _status;

  Future<void> _readAndIdentify() async {
    setState(() {
      _busy = true;
      _status = 'Aproxime a tag...';
    });
    try {
      final tagUid = await NfcService.instance.readTagText();
      if (tagUid == null) {
        setState(() => _status = 'Tag sem token legível.');
        return;
      }
      final participant = await SupabaseService.instance.findParticipantByTag(
        tagUid: tagUid,
        topId: widget.top.id,
      );
      if (!mounted) return;
      if (participant == null) {
        setState(
          () => _status = 'Tag lida, mas não está vinculada a nenhum participante deste Top.',
        );
      } else {
        setState(
          () => _status =
              'Participante: ${participant.displayLabel}'
              '${participant.phone != null ? '\nTelefone: ${participant.phone}' : ''}'
              '${participant.emergencyContact != null ? '\nContato de emergência: ${participant.emergencyContact}' : ''}',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Erro na leitura: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Participant?> _pickParticipant() async {
    final participants = await SupabaseService.instance.fetchTopParticipants(
      widget.top.id,
    );
    if (!mounted) return null;
    if (participants.isEmpty) {
      setState(
        () => _status = 'Nenhum participante cadastrado neste Top ainda.',
      );
      return null;
    }
    return showModalBottomSheet<Participant?>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: participants.length,
          itemBuilder: (context, index) {
            final p = participants[index];
            return ListTile(
              title: Text(p.displayLabel),
              subtitle: p.tagUid != null
                  ? const Text('já tem tag vinculada')
                  : null,
              onTap: () => Navigator.of(context).pop(p),
            );
          },
        ),
      ),
    );
  }

  Future<void> _linkTag() async {
    final participant = await _pickParticipant();
    if (participant == null || !mounted) return;

    setState(() {
      _busy = true;
      _status = 'Aproxime a tag pra gravar...';
    });
    try {
      final tagUid = await SupabaseService.instance.registerNfcTag(
        topId: widget.top.id,
      );
      await NfcService.instance.writeTagText(tagUid);
      await SupabaseService.instance.linkParticipantTag(
        participantId: participant.id,
        tagUid: tagUid,
      );
      if (mounted) {
        setState(
          () => _status = 'Tag vinculada a ${participant.displayLabel}.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Não foi possível vincular: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _unlinkTag() async {
    final participants = (await SupabaseService.instance.fetchTopParticipants(
      widget.top.id,
    )).where((p) => p.tagUid != null).toList();
    if (!mounted) return;
    if (participants.isEmpty) {
      setState(
        () => _status = 'Nenhum participante com tag vinculada neste Top.',
      );
      return;
    }
    final participant = await showModalBottomSheet<Participant?>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: participants.length,
          itemBuilder: (context, index) {
            final p = participants[index];
            return ListTile(
              title: Text(p.displayLabel),
              onTap: () => Navigator.of(context).pop(p),
            );
          },
        ),
      ),
    );
    if (participant == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Desvincular tag?'),
        content: Text(
          'A tag de ${participant.displayLabel} vai parar de identificá-lo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Desvincular'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await SupabaseService.instance.unlinkParticipantTag(participant.id);
      if (mounted) {
        setState(
          () => _status = 'Tag de ${participant.displayLabel} desvinculada.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Não foi possível desvincular: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: AppBarLogoTitle(title: const Text('TAG / NFC'))),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: _busy ? null : _readAndIdentify,
              icon: const Icon(Icons.nfc),
              label: const Text('LER / VERIFICAR TAG'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _busy ? null : _linkTag,
              icon: const Icon(Icons.link),
              label: const Text('VINCULAR TAG A PARTICIPANTE'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
              onPressed: _busy ? null : _unlinkTag,
              icon: const Icon(Icons.link_off),
              label: const Text('DESVINCULAR TAG'),
            ),
            const SizedBox(height: 24),
            if (_busy) const Center(child: CircularProgressIndicator()),
            if (_status != null)
              Padding(padding: const EdgeInsets.all(12), child: Text(_status!)),
          ],
        ),
      ),
    );
  }
}
