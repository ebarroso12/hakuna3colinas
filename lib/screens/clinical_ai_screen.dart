import 'package:flutter/material.dart';

import '../models/clinical_ai_response.dart';
import '../models/clinical_case.dart';
import '../services/clinical_ai_service.dart';
import '../widgets/app_logo.dart';

/// Hakuna Medical AI — entrada estruturada + análise. Suporte à decisão
/// clínica (CDSS): NUNCA substitui o julgamento do médico responsável.
/// Acesso restrito a Hakunas médicos (role=hakuna com CRM, ou admin) — a
/// tela em si não filtra isso de novo (já é feito antes de navegar até
/// aqui e reforçado na Edge Function), mas o aviso fica sempre visível.
class ClinicalAiScreen extends StatefulWidget {
  const ClinicalAiScreen({super.key, required this.topId, this.attendanceId});

  final String topId;
  final String? attendanceId;

  @override
  State<ClinicalAiScreen> createState() => _ClinicalAiScreenState();
}

class _ClinicalAiScreenState extends State<ClinicalAiScreen> {
  final _complaintController = TextEditingController();
  final _ageController = TextEditingController();
  final _systolicController = TextEditingController();
  final _diastolicController = TextEditingController();
  final _heartRateController = TextEditingController();
  final _respiratoryRateController = TextEditingController();
  final _spo2Controller = TextEditingController();
  final _temperatureController = TextEditingController();
  final _glasgowController = TextEditingController();
  final _onsetController = TextEditingController();
  final _notesController = TextEditingController();

  ClinicalAiMode _mode = ClinicalAiMode.rapida;
  bool _loading = false;
  String? _error;
  ClinicalAiResponse? _response;

  int? _int(TextEditingController c) => int.tryParse(c.text.trim());
  double? _double(TextEditingController c) =>
      double.tryParse(c.text.trim().replaceAll(',', '.'));

  Future<void> _analyze() async {
    final complaint = _complaintController.text.trim();
    if (complaint.isEmpty) {
      setState(() => _error = 'Descreva a queixa principal.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _response = null;
    });
    final clinicalCase = ClinicalCase(
      topId: widget.topId,
      attendanceId: widget.attendanceId,
      ageYears: _int(_ageController),
      chiefComplaint: complaint,
      onsetMinutesAgo: _int(_onsetController),
      systolicBp: _int(_systolicController),
      diastolicBp: _int(_diastolicController),
      heartRate: _int(_heartRateController),
      respiratoryRate: _int(_respiratoryRateController),
      spo2: _int(_spo2Controller),
      temperatureC: _double(_temperatureController),
      glasgow: _int(_glasgowController),
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      mode: _mode,
    );
    try {
      final result = await ClinicalAiService.instance.analyzeCase(clinicalCase);
      if (mounted) setState(() => _response = result);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              'IA indisponível — utilize protocolo clínico local.\n\nDetalhe técnico: $e',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _complaintController.dispose();
    _ageController.dispose();
    _systolicController.dispose();
    _diastolicController.dispose();
    _heartRateController.dispose();
    _respiratoryRateController.dispose();
    _spo2Controller.dispose();
    _temperatureController.dispose();
    _glasgowController.dispose();
    _onsetController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AppBarLogoTitle(title: const Text('Hakuna Medical AI')),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Suporte à decisão clínica — NUNCA substitui o julgamento médico. '
                'A decisão final é sempre sua.',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<ClinicalAiMode>(
              segments: const [
                ButtonSegment(
                  value: ClinicalAiMode.rapida,
                  label: Text('30 segundos'),
                ),
                ButtonSegment(
                  value: ClinicalAiMode.discussao,
                  label: Text('Discussão clínica'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => setState(() => _mode = s.first),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _complaintController,
              decoration: const InputDecoration(
                labelText: 'Queixa principal *',
              ),
              minLines: 1,
              maxLines: 3,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ageController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Idade'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _onsetController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Início (min atrás)',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _heartRateController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'FC'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _respiratoryRateController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'FR'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _spo2Controller,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'SpO2'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
                    controller: _glasgowController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Glasgow'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Observações'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _loading ? null : _analyze,
              child: _loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('ANALISAR CASO'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!),
              ),
            ],
            if (_response != null) ...[
              const SizedBox(height: 16),
              _ResultCard(response: _response!),
            ],
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.response});

  final ClinicalAiResponse response;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (response.isMock)
          Container(
            padding: const EdgeInsets.all(8),
            margin: const EdgeInsets.only(bottom: 12),
            color: Colors.amber.shade100,
            child: const Text(
              'RESPOSTA SIMULADA (mock) — a integração real com a OpenAI ainda não foi conectada/implantada.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        _Section(
          title: 'PRIORIDADE',
          children: [Text(response.priority.label)],
        ),
        if (response.immediateRisks.isNotEmpty)
          _Section(
            title: 'RISCOS IMEDIATOS',
            children: response.immediateRisks.map(Text.new).toList(),
          ),
        if (response.cannotMiss.isNotEmpty)
          _Section(
            title: 'NÃO PODE PERDER',
            children: response.cannotMiss.map(Text.new).toList(),
          ),
        if (response.differentialDiagnosis.isNotEmpty)
          _Section(
            title: 'HIPÓTESES PRINCIPAIS',
            children: response.differentialDiagnosis
                .map(
                  (h) => Text(
                    '${h.hypothesis} — a favor: ${h.forIt} · contra: ${h.against}',
                  ),
                )
                .toList(),
          ),
        if (response.actionsNow.isNotEmpty)
          _Section(
            title: 'CONDUTA IMEDIATA (AGORA)',
            children: response.actionsNow.map(Text.new).toList(),
          ),
        if (response.evacuationRecommendation != null)
          _Section(
            title: 'EVACUAÇÃO',
            children: [Text(response.evacuationRecommendation!)],
          ),
        if (response.missingInformation.isNotEmpty)
          _Section(
            title: 'DADOS QUE FALTAM',
            children: response.missingInformation.map(Text.new).toList(),
          ),
        if (response.evidence.isNotEmpty)
          _Section(
            title: 'EVIDÊNCIA',
            children: response.evidence
                .map(
                  (e) => Text(
                    '${e.institution} (${e.year ?? 's/d'}) — ${e.reference}',
                  ),
                )
                .toList(),
          )
        else
          const _Section(
            title: 'EVIDÊNCIA',
            children: [
              Text(
                'EVIDÊNCIA NÃO RECUPERADA — confirmar em protocolo clínico antes de utilizar.',
              ),
            ],
          ),
        _Section(title: 'INCERTEZA', children: [Text(response.uncertainty)]),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          ...children,
        ],
      ),
    );
  }
}
