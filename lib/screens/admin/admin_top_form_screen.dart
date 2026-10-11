import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/top.dart';
import '../../services/acesso_service.dart';
import '../../services/admin_service.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/ficha_medica.dart';
import 'admin_top_members_screen.dart';

/// Criação/edição de um Top.
///
/// Número, nome, local/pista, cidade, diretor responsável, descrição,
/// status, datas de início e fim, e o emblema da pista.
///
/// Depois de salvo, a tela ganha o bloco de **senha de cadastro do Top** —
/// ela precisa do id, que num Top novo só existe depois do primeiro
/// salvar. Ver `_BlocoSenhaDoTop`.
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
  late final _cidadeController = TextEditingController(
    text: widget.top?.cidade,
  );
  late final _diretorController = TextEditingController(
    text: widget.top?.diretorResponsavel,
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
      final cidade = _cidadeController.text.trim().isEmpty
          ? null
          : _cidadeController.text.trim();
      final diretor = _diretorController.text.trim().isEmpty
          ? null
          : _diretorController.text.trim();
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
          cidade: cidade,
          diretorResponsavel: diretor,
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
          cidade: cidade,
          diretorResponsavel: diretor,
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
    _cidadeController.dispose();
    _diretorController.dispose();
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
                MaterialPageRoute<void>(
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
          const SecaoFicha('Identificação do Top'),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _numberController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Número do Top *',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nome do Top *',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
            ],
          ),

          const SecaoFicha('Onde'),
          TextField(
            controller: _locationController,
            decoration: const InputDecoration(
              labelText: 'Local / pista',
              helperText: 'Ex.: Fazenda 3 Colinas',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _cidadeController,
            // Separada do local porque sao coisas diferentes: a pista tem
            // nome proprio, e a cidade e o que situa quem vem de fora.
            decoration: const InputDecoration(
              labelText: 'Cidade',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),

          const SecaoFicha('Responsável'),
          TextField(
            controller: _diretorController,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Diretor responsável',
              // Deixa explicito que este campo nao da poder nenhum: quem
              // manda no app vem de `role` e de `top_hakunas`.
              helperText: 'Informativo — não define permissão no app',
              border: OutlineInputBorder(),
            ),
          ),

          const SecaoFicha('Detalhes'),
          TextField(
            controller: _descriptionController,
            decoration: const InputDecoration(
              labelText: 'Descrição',
              border: OutlineInputBorder(),
            ),
            minLines: 1,
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          const SecaoFicha('Situação'),
          DropdownButtonFormField<TopStatus>(
            initialValue: _status,
            decoration: const InputDecoration(
              labelText: 'Status',
              // Em rascunho ninguem se cadastra nem usa o chat geral: a
              // RLS recusa. Avisar aqui evita o admin distribuir a senha e
              // so descobrir depois que ninguem consegue entrar.
              helperText: 'Rascunho impede cadastro e chat geral',
              border: OutlineInputBorder(),
            ),
            items: TopStatus.values
                .map((s) => DropdownMenuItem(value: s, child: Text(s.name)))
                .toList(),
            onChanged: (s) => setState(() => _status = s ?? _status),
          ),

          const SecaoFicha('Período'),
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

          // Senha de convite: so faz sentido para Top que ja existe (o
          // servidor precisa do id). Em Top novo, aparece depois de salvar.
          if (widget.top != null) ...[
            const Divider(height: 40),
            _BlocoSenhaDoTop(top: widget.top!),
          ] else ...[
            const Divider(height: 40),
            // Sem este aviso o admin cria o Top, procura a senha e nao
            // acha - ela depende do id, que so existe depois de salvar.
            Row(
              children: [
                const Icon(Icons.info_outline, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'A senha de cadastro do Top aparece aqui depois de '
                    'salvar.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Gera e mostra a senha de convite do Top.
///
/// Uma senha para o evento inteiro, anunciada ao grupo. Ela libera o
/// CADASTRO, nunca o login: quem se cadastra sai com senha propria. Ver
/// `PrimeiroAcessoScreen`.
class _BlocoSenhaDoTop extends StatefulWidget {
  const _BlocoSenhaDoTop({required this.top});

  final Top top;

  @override
  State<_BlocoSenhaDoTop> createState() => _BlocoSenhaDoTopState();
}

class _BlocoSenhaDoTopState extends State<_BlocoSenhaDoTop> {
  bool _gerando = false;

  Future<void> _gerar() async {
    // Gerar de novo INVALIDA a anterior na hora. Quem ja se cadastrou nao
    // e afetado (tem senha propria), mas quem ainda nao, perde o convite
    // antigo - e isso precisa ser uma escolha consciente, nao um toque
    // acidental num botao.
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gerar senha do Top?'),
        content: const Text(
          'Uma senha nova INVALIDA a anterior na hora.\n\n'
          'Quem já se cadastrou não é afetado — cada um tem a senha dele. '
          'Mas quem ainda não se cadastrou vai precisar da senha nova.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Gerar'),
          ),
        ],
      ),
    );
    if (confirmou != true) return;

    setState(() => _gerando = true);
    try {
      final r = await AcessoService.instance.gerarSenhaDoTop(widget.top.id);
      if (!mounted) return;
      await _mostrar(r);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível gerar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _gerando = false);
    }
  }

  /// A senha em claro aparece UMA vez. O banco guarda so o hash.
  Future<void> _mostrar(SenhaDoTop r) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Senha do Top'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(r.topNome, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Center(
              child: SelectableText(
                r.senha,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Anuncie esta senha ao grupo do Top. Ela aparece só agora — '
              'o sistema guarda apenas um resumo criptográfico dela.',
              style: TextStyle(fontSize: 12),
            ),
            if (r.aviso != null) ...[
              const SizedBox(height: 12),
              Text(
                r.aviso!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(ctx).colorScheme.error,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: r.senha));
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Senha copiada')),
                );
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copiar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Anotei'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'SENHA DE CADASTRO DO TOP',
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
        const SizedBox(height: 6),
        Text(
          'Uma senha para o evento inteiro. Anuncie ao grupo e cada '
          'Legendário se cadastra sozinho, com o número dele. Ela libera o '
          'cadastro — depois cada um entra com a própria senha.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _gerando ? null : _gerar,
          icon: _gerando
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.key),
          label: const Text('Gerar senha do Top'),
        ),
      ],
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
