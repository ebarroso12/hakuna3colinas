import 'dart:io';

import 'package:flutter/material.dart';

import '../services/supabase_service.dart';

/// Miniaturas das fotos de um atendimento, com toque para ampliar.
///
/// Existe porque as fotos não eram exibidas em lugar nenhum: a câmera
/// gravava, a fila subia, o Storage guardava — e nenhuma tela lia. Numa
/// ficha médica isso é metade do registro de uma ferida jogada fora na
/// prática.
///
/// Duas origens, de propósito:
///
/// - [caminhosLocais]: arquivos no próprio celular, de atendimento que
///   ainda está na fila. Funcionam **sem rede**, que é quando o Hakuna
///   mais precisa rever o que acabou de fotografar.
/// - [atendimentoId]: as que já subiram, buscadas como URL assinada do
///   bucket privado.
class FotosDoAtendimento extends StatefulWidget {
  const FotosDoAtendimento({
    super.key,
    this.atendimentoId,
    this.caminhosLocais = const [],
  });

  final String? atendimentoId;
  final List<String> caminhosLocais;

  @override
  State<FotosDoAtendimento> createState() => _FotosDoAtendimentoState();
}

class _FotosDoAtendimentoState extends State<FotosDoAtendimento> {
  List<String> _urls = const [];
  bool _carregando = false;

  @override
  void initState() {
    super.initState();
    _buscar();
  }

  Future<void> _buscar() async {
    final id = widget.atendimentoId;
    if (id == null) return;
    setState(() => _carregando = true);
    try {
      final urls = await SupabaseService.instance.fotosDoAtendimento(id);
      if (mounted) setState(() => _urls = urls);
    } catch (_) {
      // Sem rede não há foto do servidor — as locais seguem aparecendo.
      // Não vale mostrar erro: a ausência já é visível.
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  void _ampliar(Widget imagem) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(maxScale: 5, child: imagem),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const CircleAvatar(
                  backgroundColor: Colors.black54,
                  child: Icon(Icons.close, color: Colors.white),
                ),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniatura(Widget imagem, {required bool local}) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => _ampliar(imagem),
        child: Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(width: 72, height: 72, child: imagem),
            ),
            if (local)
              const Positioned(
                right: 2,
                bottom: 2,
                child: Icon(
                  Icons.cloud_upload_outlined,
                  size: 14,
                  color: Colors.white,
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final locais = widget.caminhosLocais
        .where((c) => File(c).existsSync())
        .toList();

    if (locais.isEmpty && _urls.isEmpty) {
      if (_carregando) {
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: SizedBox(
            height: 16,
            width: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          for (final caminho in locais)
            _miniatura(
              Image.file(File(caminho), fit: BoxFit.cover),
              local: true,
            ),
          for (final url in _urls)
            _miniatura(
              Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const ColoredBox(color: Colors.black12),
                loadingBuilder: (context, child, progresso) =>
                    progresso == null ? child : const ColoredBox(
                      color: Colors.black12,
                    ),
              ),
              local: false,
            ),
        ],
      ),
    );
  }
}
