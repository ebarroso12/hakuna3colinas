import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/participant.dart';
import '../../models/participant_tag.dart';
import '../../models/top.dart';
import '../../services/nfc_service.dart';
import '../../services/supabase_service.dart';
import '../../services/tag_service.dart';
import '../../widgets/app_logo.dart';

/// Vincular, gravar, revogar e auditar as pulseiras NFC do Top.
///
/// É o que faltava para o NFC sair do papel: o banco, a leitura e a
/// revogação já existiam, mas não havia onde emitir uma tag.
class AdminTagsScreen extends StatefulWidget {
  const AdminTagsScreen({super.key, required this.top});

  final Top top;

  @override
  State<AdminTagsScreen> createState() => _AdminTagsScreenState();
}

class _AdminTagsScreenState extends State<AdminTagsScreen> {
  final _busca = TextEditingController();

  List<Participant> _participantes = [];
  List<ParticipantTag> _tags = [];
  bool _carregando = true;
  String? _erro;

  /// false = sem tag (quem precisa de pulseira). É o filtro útil no dia da
  /// entrega das pulseiras, então começa nele.
  bool _mostrarComTag = false;

  @override
  void initState() {
    super.initState();
    _carregar();
    _busca.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final participantes = await SupabaseService.instance.fetchParticipants(
        widget.top.id,
      );
      final tags = await SupabaseService.instance.fetchTags(widget.top.id);
      if (!mounted) return;
      setState(() {
        _participantes = participantes;
        _tags = tags;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = '$e';
        _carregando = false;
      });
    }
  }

  ParticipantTag? _tagAtivaDe(String participantId) {
    for (final t in _tags) {
      if (t.participantId == participantId && t.valida) return t;
    }
    return null;
  }

  List<Participant> get _filtrados {
    final termo = _busca.text.trim().toLowerCase();
    return _participantes.where((p) {
      final temTag = _tagAtivaDe(p.id) != null;
      if (temTag != _mostrarComTag) return false;
      if (termo.isEmpty) return true;
      return p.fullName.toLowerCase().contains(termo) ||
          (p.familia?.toLowerCase().contains(termo) ?? false);
    }).toList();
  }

  Future<void> _vincular(Participant p) async {
    try {
      final tag = await TagService.instance.emitir(
        participantId: p.id,
        topId: widget.top.id,
      );
      if (!mounted) return;
      await _mostrarGravacao(p, tag);
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Não foi possível emitir: $e')));
    }
  }

  /// Oferece gravar a pulseira na hora.
  ///
  /// A tag recebe SÓ a URL com o token — nada de nome, documento ou dado
  /// médico. Quem achar a pulseira no chão não descobre nada sobre a
  /// pessoa.
  Future<void> _mostrarGravacao(Participant p, ParticipantTag tag) {
    final url = TagNdef.urlPara(tag.token);
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Gravar a pulseira'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              p.fullName.toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            if (p.familia != null) Text('Família ${p.familia}'),
            const SizedBox(height: 16),
            const Text('Conteúdo que vai na tag:'),
            const SizedBox(height: 4),
            SelectableText(
              url,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
            const SizedBox(height: 12),
            const Text(
              'Só o token vai na pulseira — nenhum dado pessoal. Encoste a '
              'tag no celular para gravar.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(dialogContext)
                    .showSnackBar(const SnackBar(content: Text('URL copiada')));
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copiar'),
          ),
          if (!kIsWeb)
            FilledButton.icon(
              onPressed: () async {
                try {
                  await NfcService.instance.writeTagText(url);
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      const SnackBar(content: Text('Pulseira gravada!')),
                    );
                  }
                } catch (e) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text('Falha ao gravar: $e')),
                    );
                  }
                }
              },
              icon: const Icon(Icons.nfc),
              label: const Text('Gravar na tag'),
            ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Depois'),
          ),
        ],
      ),
    );
  }

  Future<void> _revogar(Participant p, ParticipantTag tag) async {
    final motivo = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final campo = TextEditingController();
        return AlertDialog(
          title: const Text('Revogar a pulseira?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A tag de ${p.fullName} deixa de valer imediatamente. '
                'Quem encostar nela verá "tag revogada".',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: campo,
                decoration: const InputDecoration(
                  labelText: 'Motivo',
                  hintText: 'perdida, danificada, saiu do Top…',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(
                campo.text.trim().isEmpty ? 'sem motivo' : campo.text.trim(),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(dialogContext).colorScheme.error,
              ),
              child: const Text('Revogar'),
            ),
          ],
        );
      },
    );
    if (motivo == null) return;

    try {
      await TagService.instance.revogar(tag.id, motivo: motivo);
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Não foi possível revogar: $e')));
    }
  }

  /// Histórico de leituras — a auditoria LGPD do item 4 do spec.
  Future<void> _verLeituras(ParticipantTag tag) async {
    List<Map<String, dynamic>> leituras = const [];
    try {
      leituras = await SupabaseService.instance.fetchLeiturasTag(tag.token);
    } catch (_) {}
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Leituras (${leituras.length})'),
        content: SizedBox(
          width: 400,
          child: leituras.isEmpty
              ? const Text('Esta tag ainda não foi lida.')
              : ListView(
                  shrinkWrap: true,
                  children: leituras
                      .take(30)
                      .map(
                        (l) => ListTile(
                          dense: true,
                          leading: Icon(
                            l['resultado'] == 'ok'
                                ? Icons.check_circle_outline
                                : Icons.error_outline,
                            color: l['resultado'] == 'ok'
                                ? Colors.green
                                : Colors.orange,
                          ),
                          title: Text('${l['resultado']}'),
                          subtitle: Text('${l['lida_em']}'),
                        ),
                      )
                      .toList(),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lista = _filtrados;
    final comTag = _participantes
        .where((p) => _tagAtivaDe(p.id) != null)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Pulseiras NFC'),
            Text(
              '$comTag de ${_participantes.length} com tag',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _carregar),
          const AppLogoTrailing(),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _busca,
              decoration: const InputDecoration(
                hintText: 'Buscar por nome ou família',
                prefixIcon: Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Sem tag')),
              ButtonSegment(value: true, label: Text('Com tag')),
            ],
            selected: {_mostrarComTag},
            onSelectionChanged: (s) => setState(() => _mostrarComTag = s.first),
          ),
          const SizedBox(height: 8),
          Expanded(child: _corpo(lista)),
        ],
      ),
    );
  }

  Widget _corpo(List<Participant> lista) {
    if (_carregando) return const Center(child: CircularProgressIndicator());
    if (_erro != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Erro: $_erro', textAlign: TextAlign.center),
        ),
      );
    }
    if (lista.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _mostrarComTag
                ? 'Ninguém com pulseira ainda.'
                : 'Todos os participantes já têm pulseira.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: lista.length,
      itemBuilder: (context, i) {
        final p = lista[i];
        final tag = _tagAtivaDe(p.id);
        return Card(
          margin: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            leading: Icon(
              tag == null ? Icons.radio_button_unchecked : Icons.nfc,
              color: tag == null ? null : Colors.green,
            ),
            title: Text(p.fullName.toUpperCase()),
            subtitle: Text(
              tag == null
                  ? 'Sem pulseira'
                  : 'Token ${tag.token.substring(0, 8)}… · '
                        'emitida ${tag.issuedAt.toLocal().day}/'
                        '${tag.issuedAt.toLocal().month}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            trailing: tag == null
                ? FilledButton.tonalIcon(
                    onPressed: () => _vincular(p),
                    icon: const Icon(Icons.add_link, size: 18),
                    label: const Text('Vincular'),
                  )
                : PopupMenuButton<String>(
                    onSelected: (acao) {
                      switch (acao) {
                        case 'regravar':
                          _mostrarGravacao(p, tag);
                        case 'leituras':
                          _verLeituras(tag);
                        case 'substituir':
                          _vincular(p);
                        case 'revogar':
                          _revogar(p, tag);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: 'regravar',
                        child: Text('Gravar de novo'),
                      ),
                      PopupMenuItem(
                        value: 'leituras',
                        child: Text('Histórico de leituras'),
                      ),
                      PopupMenuItem(
                        value: 'substituir',
                        child: Text('Substituir pulseira'),
                      ),
                      PopupMenuDivider(),
                      PopupMenuItem(value: 'revogar', child: Text('Revogar')),
                    ],
                  ),
          ),
        );
      },
    );
  }
}
