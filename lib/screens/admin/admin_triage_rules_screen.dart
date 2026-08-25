import 'package:flutter/material.dart';

import '../../models/triage_rule.dart';
import '../../services/admin_service.dart';
import '../../widgets/app_logo.dart';

/// Edição das regras de triagem por cor (idade + nº de comorbidades).
/// Exclusiva do admin master — o banco rejeita a escrita de qualquer outro
/// usuário mesmo que essa tela seja aberta por engano.
class AdminTriageRulesScreen extends StatefulWidget {
  const AdminTriageRulesScreen({super.key});

  @override
  State<AdminTriageRulesScreen> createState() => _AdminTriageRulesScreenState();
}

class _AdminTriageRulesScreenState extends State<AdminTriageRulesScreen> {
  late Future<List<TriageRule>> _future;

  @override
  void initState() {
    super.initState();
    _future = AdminService.instance.fetchAllTriageRules();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AppBarLogoTitle(title: const Text('Regras de triagem')),
      ),
      body: FutureBuilder<List<TriageRule>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erro ao carregar: ${snapshot.error}'));
          }
          final rules = snapshot.data ?? [];
          return ListView.builder(
            itemCount: rules.length,
            itemBuilder: (context, index) => _RuleTile(rule: rules[index]),
          );
        },
      ),
    );
  }
}

class _RuleTile extends StatefulWidget {
  const _RuleTile({required this.rule});

  final TriageRule rule;

  @override
  State<_RuleTile> createState() => _RuleTileState();
}

class _RuleTileState extends State<_RuleTile> {
  late final _minAgeController = TextEditingController(
    text: widget.rule.minAge.toString(),
  );
  late final _maxAgeController = TextEditingController(
    text: widget.rule.maxAge?.toString() ?? '',
  );
  late final _minComorbController = TextEditingController(
    text: widget.rule.minComorbidities.toString(),
  );
  late final _maxComorController = TextEditingController(
    text: widget.rule.maxComorbidities.toString(),
  );
  late bool _active = widget.rule.active;
  bool _saving = false;

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final updated = TriageRule(
        id: widget.rule.id,
        color: widget.rule.color,
        label: widget.rule.label,
        minAge: int.tryParse(_minAgeController.text) ?? widget.rule.minAge,
        maxAge: _maxAgeController.text.trim().isEmpty
            ? null
            : int.tryParse(_maxAgeController.text),
        minComorbidities:
            int.tryParse(_minComorbController.text) ??
            widget.rule.minComorbidities,
        maxComorbidities:
            int.tryParse(_maxComorController.text) ??
            widget.rule.maxComorbidities,
        priority: widget.rule.priority,
        active: _active,
      );
      await AdminService.instance.updateTriageRule(updated);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Regra salva.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro ao salvar: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _minAgeController.dispose();
    _maxAgeController.dispose();
    _minComorbController.dispose();
    _maxComorController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 16,
                  height: 16,
                  color: widget.rule.color.materialColor,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.rule.label,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Switch(
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minAgeController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Idade mín.'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _maxAgeController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Idade máx. (vazio = sem limite)',
                    ),
                  ),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minComorbController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Comorbidades mín.',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _maxComorController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Comorbidades máx.',
                    ),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Salvar'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
