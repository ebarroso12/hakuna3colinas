import 'package:flutter/material.dart';

import '../models/profile.dart';
import '../models/top.dart';
import '../models/triage_rule.dart';
import '../models/vital_signs.dart';
import '../services/supabase_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/triage_badge.dart';

/// Registro e histórico de sinais vitais de um Senderista específico num Top.
class VitalSignsScreen extends StatefulWidget {
  const VitalSignsScreen({
    super.key,
    required this.top,
    required this.profile,
    this.triageColor,
  });

  final Top top;
  final Profile profile;
  final TriageColor? triageColor;

  @override
  State<VitalSignsScreen> createState() => _VitalSignsScreenState();
}

class _VitalSignsScreenState extends State<VitalSignsScreen> {
  final _heartRateController = TextEditingController();
  final _systolicController = TextEditingController();
  final _diastolicController = TextEditingController();
  final _spo2Controller = TextEditingController();
  final _temperatureController = TextEditingController();
  final _respiratoryController = TextEditingController();
  final _notesController = TextEditingController();
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await SupabaseService.instance.recordVitalSigns(
        topId: widget.top.id,
        profileId: widget.profile.id,
        heartRate: int.tryParse(_heartRateController.text),
        systolicBp: int.tryParse(_systolicController.text),
        diastolicBp: int.tryParse(_diastolicController.text),
        spo2: int.tryParse(_spo2Controller.text),
        temperatureC: double.tryParse(
          _temperatureController.text.replaceAll(',', '.'),
        ),
        respiratoryRate: int.tryParse(_respiratoryController.text),
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );
      if (!mounted) return;
      _heartRateController.clear();
      _systolicController.clear();
      _diastolicController.clear();
      _spo2Controller.clear();
      _temperatureController.clear();
      _respiratoryController.clear();
      _notesController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sinais vitais registrados.')),
      );
    } catch (e) {
      if (mounted) setState(() => _error = 'Não foi possível salvar: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _heartRateController.dispose();
    _systolicController.dispose();
    _diastolicController.dispose();
    _spo2Controller.dispose();
    _temperatureController.dispose();
    _respiratoryController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AppBarLogoTitle(title: Text(widget.profile.displayLabel)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(child: TriageBadge(color: widget.triageColor)),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _heartRateController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'FC (bpm)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _spo2Controller,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'SpO2 (%)',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _systolicController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'PA sistólica',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _diastolicController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'PA diastólica',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _temperatureController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Temperatura (°C)',
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _respiratoryController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'FR (irpm)',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Observações / sinais de alarme',
                  ),
                  minLines: 1,
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: const Text('Registrar sinais vitais'),
                ),
              ],
            ),
          ),
          const Divider(),
          Expanded(
            child: StreamBuilder<List<VitalSigns>>(
              stream: SupabaseService.instance.watchVitalSigns(
                topId: widget.top.id,
                profileId: widget.profile.id,
              ),
              builder: (context, snapshot) {
                final history = snapshot.data ?? [];
                if (history.isEmpty) {
                  return const Center(child: Text('Nenhum registro ainda.'));
                }
                return ListView.builder(
                  itemCount: history.length,
                  itemBuilder: (context, index) {
                    final v = history[index];
                    return ListTile(
                      leading: const Icon(Icons.monitor_heart),
                      title: Text(v.summary),
                      subtitle: Text(v.recordedAt.toLocal().toString()),
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
