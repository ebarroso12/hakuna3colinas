import 'package:flutter/material.dart';

import '../../models/profile.dart';
import '../../services/admin_service.dart';
import '../../widgets/app_logo.dart';

const _knownComorbidities = ['diabetes', 'hipertensao', 'cirurgia_previa'];

const _comorbidityLabels = {
  'diabetes': 'Diabetes',
  'hipertensao': 'Hipertensão',
  'cirurgia_previa': 'Cirurgia prévia',
};

/// Edição de um usuário pelo admin: papel, atribuições e dados de
/// triagem (data de nascimento + comorbidades). Conceder papel 'admin' só
/// é aceito pelo banco se quem edita for o admin master — o dropdown já
/// reflete essa regra desabilitando a opção pra admins comuns.
class AdminUserEditScreen extends StatefulWidget {
  const AdminUserEditScreen({super.key, required this.profile, required this.isMasterAdmin});

  final Profile profile;
  final bool isMasterAdmin;

  @override
  State<AdminUserEditScreen> createState() => _AdminUserEditScreenState();
}

class _AdminUserEditScreenState extends State<AdminUserEditScreen> {
  late UserRole _role;
  late Set<String> _comorbidities;
  DateTime? _birthDate;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _role = widget.profile.role;
    _comorbidities = widget.profile.comorbidities.toSet();
    _birthDate = widget.profile.birthDate;
  }

  Future<void> _pickBirthDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(2000, 1, 1),
      firstDate: DateTime(1920),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _birthDate = picked);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_role != widget.profile.role) {
        await AdminService.instance.updateProfileRole(widget.profile.id, _role);
      }
      await AdminService.instance.updateProfileTriageInfo(
        widget.profile.id,
        birthDate: _birthDate,
        comorbidities: _comorbidities.toList(),
      );
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
        title: const Text('Remover usuário'),
        content: Text('Remover ${widget.profile.displayLabel} do app? Essa ação não pode ser desfeita.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Remover')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await AdminService.instance.deleteProfile(widget.profile.id);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Não foi possível remover: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: const AppLogoAppBarLeading(),
        title: Text(widget.profile.displayLabel),
        actions: [
          if (!widget.profile.isMasterAdmin)
            IconButton(icon: const Icon(Icons.delete_outline), onPressed: _confirmDelete),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Papel', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          DropdownButtonFormField<UserRole>(
            initialValue: _role,
            items: UserRole.values
                .map((r) => DropdownMenuItem(
                      value: r,
                      enabled: r != UserRole.admin || widget.isMasterAdmin,
                      child: Text(r.name),
                    ))
                .toList(),
            onChanged: widget.profile.isMasterAdmin ? null : (r) => setState(() => _role = r ?? _role),
          ),
          const SizedBox(height: 24),
          Text('Triagem', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_birthDate == null ? 'Data de nascimento não informada' : _birthDate!.toLocal().toString().split(' ').first),
            trailing: const Icon(Icons.edit_calendar),
            onTap: _pickBirthDate,
          ),
          const SizedBox(height: 8),
          ..._knownComorbidities.map((c) => CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(_comorbidityLabels[c] ?? c),
                value: _comorbidities.contains(c),
                onChanged: (v) => setState(() {
                  if (v ?? false) {
                    _comorbidities.add(c);
                  } else {
                    _comorbidities.remove(c);
                  }
                }),
              )),
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
