import 'package:flutter/material.dart';

import '../models/top.dart';
import '../services/supabase_service.dart';
import '../widgets/app_logo.dart';

/// Cadastro rápido de participante em campo — sem exigir conta de login.
/// Ver supabase/participants_and_attendance.sql pra entender por que isso é
/// uma entidade separada de Senderista (que exige conta própria).
class ParticipantFormScreen extends StatefulWidget {
  const ParticipantFormScreen({super.key, required this.top});

  final Top top;

  @override
  State<ParticipantFormScreen> createState() => _ParticipantFormScreenState();
}

class _ParticipantFormScreenState extends State<ParticipantFormScreen> {
  final _fullNameController = TextEditingController();
  final _codeController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emergencyContactController = TextEditingController();
  final _notesController = TextEditingController();
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    final fullName = _fullNameController.text.trim();
    if (fullName.isEmpty) {
      setState(() => _error = 'Nome é obrigatório.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await SupabaseService.instance.registerParticipant(
        topId: widget.top.id,
        fullName: fullName,
        participantCode: _codeController.text.trim().isEmpty
            ? null
            : _codeController.text.trim(),
        nickname: _nicknameController.text.trim().isEmpty
            ? null
            : _nicknameController.text.trim(),
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        emergencyContact: _emergencyContactController.text.trim().isEmpty
            ? null
            : _emergencyContactController.text.trim(),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Não foi possível cadastrar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _codeController.dispose();
    _nicknameController.dispose();
    _phoneController.dispose();
    _emergencyContactController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AppBarLogoTitle(title: const Text('Cadastrar participante')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _fullNameController,
              decoration: const InputDecoration(labelText: 'Nome completo *'),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _codeController,
              decoration: const InputDecoration(
                labelText: 'Número/código — opcional',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nicknameController,
              decoration: const InputDecoration(
                labelText: 'Apelido / nome de guerra — opcional',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Telefone — opcional',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _emergencyContactController,
              decoration: const InputDecoration(
                labelText: 'Contato de emergência — opcional',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Observações — opcional',
              ),
            ),
            const SizedBox(height: 24),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Cadastrar'),
            ),
          ],
        ),
      ),
    );
  }
}
