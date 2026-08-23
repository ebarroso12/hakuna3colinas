import 'package:flutter/material.dart';

import '../../models/top.dart';
import '../../services/admin_service.dart';
import '../../widgets/app_logo.dart';
import 'admin_top_members_screen.dart';

/// Criação/edição de um Top: nome, número, local, descrição, status e datas.
class AdminTopFormScreen extends StatefulWidget {
  const AdminTopFormScreen({super.key, this.top});

  /// Null = criando um Top novo.
  final Top? top;

  @override
  State<AdminTopFormScreen> createState() => _AdminTopFormScreenState();
}

class _AdminTopFormScreenState extends State<AdminTopFormScreen> {
  late final _nameController = TextEditingController(text: widget.top?.name);
  late final _numberController = TextEditingController(text: widget.top?.topNumber);
  late final _locationController = TextEditingController(text: widget.top?.location);
  late final _descriptionController = TextEditingController(text: widget.top?.description);
  late TopStatus _status = widget.top?.status ?? TopStatus.draft;
  late DateTime? _startsAt = widget.top?.startsAt;
  late DateTime? _endsAt = widget.top?.endsAt;
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.top != null;

  Future<void> _pickDate({required bool isStart}) async {
    final current = isStart ? _startsAt : _endsAt;
    final picked = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startsAt = picked;
      } else {
        _endsAt = picked;
      }
    });
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Informe o nome do Top.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final topNumber = _numberController.text.trim().isEmpty ? null : _numberController.text.trim();
      final location = _locationController.text.trim().isEmpty ? null : _locationController.text.trim();
      final description = _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim();
      if (_isEditing) {
        await AdminService.instance.updateTop(
          topId: widget.top!.id,
          name: name,
          topNumber: topNumber,
          location: location,
          description: description,
          status: _status,
          startsAt: _startsAt,
          endsAt: _endsAt,
        );
      } else {
        await AdminService.instance.createTop(
          name: name,
          topNumber: topNumber,
          location: location,
          description: description,
          startsAt: _startsAt,
          endsAt: _endsAt,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = 'Não foi possível salvar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Excluir Top'),
        content: Text('Excluir "${widget.top!.name}"? Remove também posições, sinais vitais e mensagens ligados a ele.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Excluir')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await AdminService.instance.deleteTop(widget.top!.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível excluir: $e')));
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _numberController.dispose();
    _locationController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppLogoAppBarLeading(),
        title: Text(_isEditing ? 'Editar Top' : 'Novo Top'),
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.people_outline),
              tooltip: 'Gerenciar equipe',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => AdminTopMembersScreen(top: widget.top!)),
              ),
            ),
          if (_isEditing) IconButton(icon: const Icon(Icons.delete_outline), onPressed: _confirmDelete),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: _nameController, decoration: const InputDecoration(labelText: 'Nome do Top')),
          const SizedBox(height: 12),
          TextField(controller: _numberController, decoration: const InputDecoration(labelText: 'Número do Top')),
          const SizedBox(height: 12),
          TextField(controller: _locationController, decoration: const InputDecoration(labelText: 'Local')),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            decoration: const InputDecoration(labelText: 'Descrição'),
            minLines: 1,
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<TopStatus>(
            initialValue: _status,
            decoration: const InputDecoration(labelText: 'Status'),
            items: TopStatus.values.map((s) => DropdownMenuItem(value: s, child: Text(s.name))).toList(),
            onChanged: (s) => setState(() => _status = s ?? _status),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_startsAt == null ? 'Início não definido' : 'Início: ${_startsAt!.toLocal().toString().split(' ').first}'),
            trailing: const Icon(Icons.edit_calendar),
            onTap: () => _pickDate(isStart: true),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_endsAt == null ? 'Fim não definido' : 'Fim: ${_endsAt!.toLocal().toString().split(' ').first}'),
            trailing: const Icon(Icons.edit_calendar),
            onTap: () => _pickDate(isStart: false),
          ),
          const SizedBox(height: 16),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}
