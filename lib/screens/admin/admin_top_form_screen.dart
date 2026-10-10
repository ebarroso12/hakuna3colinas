import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

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
  late final _numberController = TextEditingController(
    text: widget.top?.topNumber,
  );

  /// Emblema escolhido mas ainda nao enviado. Sobe junto com o salvar,
  /// porque o caminho no Storage precisa do id do Top - que so existe
  /// depois de criado.
  Uint8List? _emblemaBytes;
  String? _emblemaExtensao;

  Future<void> _escolherEmblema() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Escolher imagem só no celular, por enquanto.'),
        ),
      );
      return;
    }
    final arquivo = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      // Emblema aparece pequeno na lista; 800px bastam e economizam a rede
      // da equipe em campo.
      maxWidth: 800,
      imageQuality: 85,
    );
    if (arquivo == null) return;
    final bytes = await arquivo.readAsBytes();
    if (!mounted) return;
    setState(() {
      _emblemaBytes = bytes;
      _emblemaExtensao = arquivo.path.contains('.')
          ? '.${arquivo.path.split('.').last}'
          : '.jpg';
    });
  }

  late final _locationController = TextEditingController(
    text: widget.top?.location,
  );
  late final _descriptionController = TextEditingController(
    text: widget.top?.description,
  );
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
      final topNumber = _numberController.text.trim().isEmpty
          ? null
          : _numberController.text.trim();
      final location = _locationController.text.trim().isEmpty
          ? null
          : _locationController.text.trim();
      final description = _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim();
      String? topId;
      if (_isEditing) {
        topId = widget.top!.id;
        await AdminService.instance.updateTop(
          topId: topId,
          name: name,
          topNumber: topNumber,
          location: location,
          description: description,
          status: _status,
          startsAt: _startsAt,
          endsAt: _endsAt,
        );
      } else {
        final criado = await AdminService.instance.createTop(
          name: name,
          topNumber: topNumber,
          location: location,
          description: description,
          startsAt: _startsAt,
          endsAt: _endsAt,
        );
        topId = criado.id;
      }

      // O emblema sobe DEPOIS de salvar: o caminho no Storage usa o id do
      // Top, que num Top novo só existe agora. Falha aqui não desfaz o
      // Top — melhor um Top sem emblema do que perder o cadastro.
      final bytes = _emblemaBytes;
      if (bytes != null) {
        try {
          await AdminService.instance.uploadEmblema(
            topId: topId,
            bytes: bytes,
            extensao: _emblemaExtensao ?? '.jpg',
          );
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Top salvo, mas o emblema não subiu: $e')),
            );
          }
        }
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
        content: Text(
          'Excluir "${widget.top!.name}"? Remove também posições, sinais vitais e mensagens ligados a ele.',
        ),
        actions: [
          const AppLogoTrailing(),
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Excluir'),
          ),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Não foi possível excluir: $e')));
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
        title: Text(_isEditing ? 'Editar Top' : 'Novo Top'),
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.people_outline),
              tooltip: 'Gerenciar equipe',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AdminTopMembersScreen(top: widget.top!),
                ),
              ),
            ),
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _CampoEmblema(
            bytes: _emblemaBytes,
            urlAtual: AdminService.instance.urlEmblema(widget.top?.emblemaPath),
            aoEscolher: _escolherEmblema,
            aoRemover: _emblemaBytes == null
                ? null
                : () => setState(() {
                    _emblemaBytes = null;
                    _emblemaExtensao = null;
                  }),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(labelText: 'Nome do Top'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _numberController,
            decoration: const InputDecoration(labelText: 'Número do Top'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _locationController,
            decoration: const InputDecoration(labelText: 'Local'),
          ),
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
            items: TopStatus.values
                .map((s) => DropdownMenuItem(value: s, child: Text(s.name)))
                .toList(),
            onChanged: (s) => setState(() => _status = s ?? _status),
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              _startsAt == null
                  ? 'Início não definido'
                  : 'Início: ${_startsAt!.toLocal().toString().split(' ').first}',
            ),
            trailing: const Icon(Icons.edit_calendar),
            onTap: () => _pickDate(isStart: true),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              _endsAt == null
                  ? 'Fim não definido'
                  : 'Fim: ${_endsAt!.toLocal().toString().split(' ').first}',
            ),
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
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Salvar'),
          ),
        ],
      ),
    );
  }
}

/// Emblema/brasão da pista do Top.
class _CampoEmblema extends StatelessWidget {
  const _CampoEmblema({
    required this.bytes,
    required this.urlAtual,
    required this.aoEscolher,
    this.aoRemover,
  });

  final Uint8List? bytes;
  final String? urlAtual;
  final VoidCallback aoEscolher;
  final VoidCallback? aoRemover;

  @override
  Widget build(BuildContext context) {
    final temNovo = bytes != null;
    final temAtual = urlAtual != null && urlAtual!.isNotEmpty;

    return Column(
      children: [
        GestureDetector(
          onTap: aoEscolher,
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Theme.of(context).dividerColor),
            ),
            clipBehavior: Clip.antiAlias,
            child: temNovo
                ? Image.memory(bytes!, fit: BoxFit.cover)
                : temAtual
                ? Image.network(
                    urlAtual!,
                    fit: BoxFit.cover,
                    // Emblema que nao carrega nao pode quebrar o formulario.
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.broken_image_outlined, size: 40),
                  )
                : const Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_photo_alternate_outlined, size: 36),
                      SizedBox(height: 4),
                      Text('Emblema', style: TextStyle(fontSize: 12)),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 6),
        Text('Emblema da pista', style: Theme.of(context).textTheme.labelSmall),
        if (aoRemover != null)
          TextButton(onPressed: aoRemover, child: const Text('Descartar')),
      ],
    );
  }
}
