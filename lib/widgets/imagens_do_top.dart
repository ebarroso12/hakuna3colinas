import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/top_imagem.dart';
import '../services/admin_service.dart';

/// Até 3 imagens de identidade do Top.
///
/// "A cada Top será tudo novo": logo da trilha, brasão, patrocínio. O Top
/// já tem **uma** imagem principal (`tops.emblema_path`, o campo Emblema);
/// estas são as outras três posições.
///
/// Só aparece em Top **já salvo**: as imagens vão para `top_imagens`, que
/// referencia `top_id`. Num Top sendo criado ainda não há id, e guardar os
/// bytes em memória esperando o salvamento daria uma perda silenciosa se o
/// admin fechasse a tela. A mensagem diz isso em vez de mostrar um botão
/// que falha.
class ImagensDoTop extends StatefulWidget {
  const ImagensDoTop({super.key, required this.topId});

  /// Null = Top ainda não salvo.
  final String? topId;

  @override
  State<ImagensDoTop> createState() => _ImagensDoTopState();
}

class _ImagensDoTopState extends State<ImagensDoTop> {
  List<TopImagem> _imagens = [];
  bool _carregando = false;
  final Set<int> _ocupadas = {};

  @override
  void initState() {
    super.initState();
    if (widget.topId != null) _carregar();
  }

  Future<void> _carregar() async {
    final id = widget.topId;
    if (id == null) return;
    setState(() => _carregando = true);
    try {
      final lista = await AdminService.instance.imagensDoTop(id);
      if (mounted) setState(() => _imagens = lista);
    } catch (_) {
      // Sem rede não dá para listar. Não vale mostrar erro aqui: o
      // formulário do Top tem muito mais o que fazer, e a ausência das
      // miniaturas já comunica.
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  TopImagem? _daPosicao(int ordem) =>
      _imagens.where((i) => i.ordem == ordem).firstOrNull;

  Future<void> _escolher(int ordem) async {
    final id = widget.topId;
    if (id == null) return;

    final arquivo = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      // Logo não precisa de 4000 px. Reduzir aqui poupa o upload e o
      // tráfego de quem baixa a lista de Tops no celular.
      maxWidth: 1200,
      imageQuality: 85,
    );
    if (arquivo == null) return;

    setState(() => _ocupadas.add(ordem));
    try {
      final bytes = await arquivo.readAsBytes();
      final nome = arquivo.name.toLowerCase();
      final extensao = nome.endsWith('.png')
          ? '.png'
          : nome.endsWith('.webp')
          ? '.webp'
          : '.jpg';

      await AdminService.instance.enviarImagemDoTop(
        topId: id,
        ordem: ordem,
        bytes: bytes,
        extensao: extensao,
      );
      await _carregar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Imagem $ordem salva.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível enviar: $e')),
      );
    } finally {
      if (mounted) setState(() => _ocupadas.remove(ordem));
    }
  }

  Future<void> _apagar(TopImagem img) async {
    final id = widget.topId;
    if (id == null) return;

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Apagar a imagem ${img.ordem}?'),
        content: const Text(
          'O arquivo sai do servidor junto. Não há como desfazer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Apagar'),
          ),
        ],
      ),
    );
    if (confirmou != true) return;

    setState(() => _ocupadas.add(img.ordem));
    try {
      await AdminService.instance.apagarImagemDoTop(
        topId: id,
        ordem: img.ordem,
        storagePath: img.storagePath,
      );
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível apagar: $e')),
      );
    } finally {
      if (mounted) setState(() => _ocupadas.remove(img.ordem));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'IMAGENS DO TOP (até 3)',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          widget.topId == null
              ? 'Salve o Top primeiro. As imagens ficam ligadas a ele, e '
                    'antes de salvar ele ainda não existe.'
              : 'Logo da trilha, brasão, patrocínio — o que identificar '
                    'este Top. Toque num quadro para escolher, e toque numa '
                    'imagem já posta para TROCAR por outra. O × apaga.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 10),

        if (_carregando)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          )
        else
          Row(
            children: [
              for (var ordem = 1; ordem <= 3; ordem++) ...[
                Expanded(
                  child: _Quadro(
                    ordem: ordem,
                    imagem: _daPosicao(ordem),
                    habilitado: widget.topId != null,
                    ocupado: _ocupadas.contains(ordem),
                    aoEscolher: () => _escolher(ordem),
                    aoApagar: () {
                      final img = _daPosicao(ordem);
                      if (img != null) _apagar(img);
                    },
                  ),
                ),
                if (ordem < 3) const SizedBox(width: 8),
              ],
            ],
          ),
      ],
    );
  }
}

class _Quadro extends StatelessWidget {
  const _Quadro({
    required this.ordem,
    required this.imagem,
    required this.habilitado,
    required this.ocupado,
    required this.aoEscolher,
    required this.aoApagar,
  });

  final int ordem;
  final TopImagem? imagem;
  final bool habilitado;
  final bool ocupado;
  final VoidCallback aoEscolher;
  final VoidCallback aoApagar;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    // `selo` é obrigatório aqui, não enfeite. O caminho no Storage é fixo
    // por posição, então a URL pública não muda quando a imagem muda — e o
    // `ImageCache` do Flutter e o CDN são indexados por URL. Sem o selo, o
    // admin trocava a imagem, o envio dava certo, e o quadro continuava
    // mostrando a antiga: parece falha de upload. Achado por revisão em
    // 11/10/2026.
    final base = imagem == null
        ? null
        : AdminService.instance.urlEmblema(imagem!.storagePath);
    final url = base == null ? null : '$base${imagem!.selo}';

    return AspectRatio(
      aspectRatio: 1,
      child: GestureDetector(
        // Toque num quadro CHEIO troca a imagem: `ocupado` é "enviando
        // agora", não "tem imagem". O texto acima diz isso — antes dizia
        // "toque num quadro vazio", o que fazia o admin concluir que para
        // trocar era preciso apagar primeiro. O dono do projeto reforçou
        // em 11/10/2026 que editar nome e fotos tem de funcionar sempre.
        onTap: habilitado && !ocupado ? aoEscolher : null,
        child: Container(
          decoration: BoxDecoration(
            color: cores.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: cores.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (url != null)
                Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Center(
                    child: Icon(Icons.broken_image_outlined,
                        color: cores.outline),
                  ),
                )
              else
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.add_photo_alternate_outlined,
                      color: habilitado ? cores.primary : cores.outline,
                    ),
                    const SizedBox(height: 4),
                    Text('$ordem', style: TextStyle(color: cores.outline)),
                  ],
                ),

              if (ocupado)
                ColoredBox(
                  color: Colors.black38,
                  child: const Center(
                    child: SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

              if (url != null && !ocupado)
                Positioned(
                  top: 0,
                  right: 0,
                  child: IconButton(
                    icon: const CircleAvatar(
                      radius: 12,
                      backgroundColor: Colors.black54,
                      child: Icon(Icons.close, size: 14, color: Colors.white),
                    ),
                    tooltip: 'Apagar imagem $ordem',
                    onPressed: aoApagar,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
