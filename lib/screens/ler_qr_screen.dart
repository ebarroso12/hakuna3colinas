import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/participant_tag.dart';
import '../models/top.dart';
import '../models/triage_rule.dart';
import '../services/qr_token_service.dart';
import '../services/tag_service.dart';
import 'participant_file_screen.dart';

/// LER QR — contingência de quando a pulseira não responde.
///
/// Aparelho sem sensor NFC, ou chip da pulseira que parou de funcionar. Nos
/// dois casos o Hakuna está na frente de alguém e precisa identificar.
///
/// O QR carrega **o mesmo token** do NDEF, então daqui para baixo tudo é
/// idêntico ao NFC: `TagService.resolver` faz cache em disco, fallback,
/// auditoria e checagem de revogação. Esta tela só troca a câmera pelo
/// sensor. Ver `QrTokenService` para a razão de não haver formato próprio.
class LerQrScreen extends StatefulWidget {
  const LerQrScreen({super.key, required this.top, this.regras = const []});

  final Top top;
  final List<TriageRule> regras;

  @override
  State<LerQrScreen> createState() => _LerQrScreenState();
}

class _LerQrScreenState extends State<LerQrScreen> {
  late final MobileScannerController _controller;

  /// Trava de reentrada.
  ///
  /// A câmera dispara `onDetect` a cada quadro em que o código aparece —
  /// dezenas de vezes por segundo com o celular parado em cima do QR. Sem
  /// esta trava, cada quadro abriria uma resolução, uma linha de auditoria
  /// e uma navegação. Era o bug mais provável desta tela.
  bool _processando = false;

  LeituraTag? _resultado;
  QrDeOutroSistema? _qrEstranho;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      // Só QR: não varre código de barras, PDF417 e companhia. Reduz
      // leitura acidental e o custo por quadro.
      formats: const [BarcodeFormat.qrCode],
      detectionSpeed: DetectionSpeed.noDuplicates,
      // Sem torch por padrão: trilha à noite é caso real, mas acender a
      // lanterna sozinho na cara de um paciente deitado, não.
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    // Libera a câmera. Sem isto o sensor fica preso e a próxima abertura
    // da tela mostra preto — e em alguns aparelhos a lanterna fica acesa.
    _controller.dispose();
    super.dispose();
  }

  Future<void> _aoDetectar(BarcodeCapture captura) async {
    if (_processando) return;

    final conteudo = captura.barcodes
        .map((b) => b.rawValue)
        .firstWhere((v) => v != null && v.trim().isNotEmpty, orElse: () => null);
    if (conteudo == null) return;

    setState(() {
      _processando = true;
      _resultado = null;
      _qrEstranho = null;
      _erro = null;
    });

    final leitura = QrTokenService.interpretar(conteudo);

    if (leitura is QrDeOutroSistema) {
      // Para a câmera: sem isso o mesmo QR errado seria relido em loop e a
      // tela ficaria piscando o aviso.
      await _controller.stop();
      if (!mounted) return;
      setState(() {
        _qrEstranho = leitura;
        _processando = false;
      });
      return;
    }

    final token = (leitura as QrComToken).token;
    try {
      // Mesmo caminho do NFC. `urlPara` porque `resolver` recebe o
      // conteúdo do NDEF, e manter a mesma entrada evita dois formatos de
      // chamada para a mesma coisa.
      final resolvida = await TagService.instance.resolver(
        TagNdef.urlPara(token),
        topId: widget.top.id,
      );
      if (!mounted) return;

      if (resolvida.identificou) {
        _abrirFicha(resolvida);
        return;
      }
      await _controller.stop();
      if (!mounted) return;
      setState(() {
        _resultado = resolvida;
        _processando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = '$e';
        _processando = false;
      });
    }
  }

  void _abrirFicha(LeituraTag leitura) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ParticipantFileScreen(
          participante: leitura.participante!,
          top: widget.top,
          regras: widget.regras,
        ),
      ),
    );
  }

  Future<void> _tentarDeNovo() async {
    setState(() {
      _resultado = null;
      _qrEstranho = null;
      _erro = null;
      _processando = false;
    });
    await _controller.start();
  }

  @override
  Widget build(BuildContext context) {
    if (!QrTokenService.suportado) return _semSuporte(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ler QR da pulseira'),
        actions: [
          IconButton(
            tooltip: 'Lanterna',
            icon: const Icon(Icons.flashlight_on),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            tooltip: 'Virar câmera',
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _aoDetectar,
                  // Permissão negada, aparelho sem câmera, câmera ocupada
                  // por outro app: todos chegam aqui. Tratar num lugar só
                  // evita tela preta sem explicação, que é o pior
                  // resultado possível com um paciente esperando.
                  errorBuilder: (context, erro) => _erroDaCamera(context, erro),
                ),
                IgnorePointer(child: _mira(context)),
              ],
            ),
          ),
          _rodape(context),
        ],
      ),
    );
  }

  /// Moldura central. Não recorta a leitura — o `mobile_scanner` varre o
  /// quadro inteiro —, só diz ao Hakuna onde apontar.
  Widget _mira(BuildContext context) {
    return Center(
      child: Container(
        width: 240,
        height: 240,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 3),
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }

  Widget _rodape(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_erro != null) {
      return _faixa(
        cor: scheme.errorContainer,
        corTexto: scheme.onErrorContainer,
        icone: Icons.error_outline,
        texto: 'Não foi possível resolver o QR: $_erro',
        acao: TextButton(
          onPressed: _tentarDeNovo,
          child: const Text('Tentar de novo'),
        ),
      );
    }

    if (_qrEstranho != null) {
      return _faixa(
        cor: scheme.secondaryContainer,
        corTexto: scheme.onSecondaryContainer,
        icone: Icons.qr_code_2,
        // Diz que leu e que não é pulseira. "Não encontrado" mandaria o
        // Hakuna procurar pelo nome por causa de um QR de nota fiscal.
        texto:
            'Este QR não é de pulseira do sistema.\n'
            'Conteúdo lido: ${_qrEstranho!.amostra}',
        acao: TextButton(
          onPressed: _tentarDeNovo,
          child: const Text('Ler outro'),
        ),
      );
    }

    if (_resultado != null) {
      final r = _resultado!.resultado;
      final grave = r == ResultadoLeitura.revogada;
      return _faixa(
        cor: grave ? scheme.errorContainer : scheme.surfaceContainerHighest,
        corTexto: grave ? scheme.onErrorContainer : scheme.onSurface,
        icone: grave ? Icons.gpp_bad : Icons.info_outline,
        texto: r.mensagem,
        acao: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(
              onPressed: _tentarDeNovo,
              child: const Text('Ler outro'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Buscar pelo nome'),
            ),
          ],
        ),
      );
    }

    return _faixa(
      cor: scheme.surfaceContainerHighest,
      corTexto: scheme.onSurface,
      icone: _processando ? Icons.hourglass_top : Icons.center_focus_strong,
      texto: _processando
          ? 'Identificando…'
          : 'Aponte para o QR da pulseira.\n'
                'Se não funcionar, busque pelo nome.',
      acao: TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Buscar pelo nome'),
      ),
    );
  }

  Widget _faixa({
    required Color cor,
    required Color corTexto,
    required IconData icone,
    required String texto,
    Widget? acao,
  }) {
    return Material(
      color: cor,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icone, color: corTexto),
              const SizedBox(width: 10),
              Expanded(child: Text(texto, style: TextStyle(color: corTexto))),
              ?acao,
            ],
          ),
        ),
      ),
    );
  }

  Widget _erroDaCamera(BuildContext context, MobileScannerException erro) {
    final semPermissao =
        erro.errorCode == MobileScannerErrorCode.permissionDenied;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(semPermissao ? Icons.no_photography : Icons.videocam_off,
                size: 56),
            const SizedBox(height: 12),
            Text(
              semPermissao
                  ? 'O app não tem permissão para usar a câmera.'
                  : 'Não foi possível abrir a câmera.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              semPermissao
                  ? 'Libere a câmera nas Configurações do app, ou busque o '
                        'participante pelo nome.'
                  : 'A câmera pode estar em uso por outro app. '
                        'Busque o participante pelo nome.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.search),
              label: const Text('Buscar pelo nome'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _semSuporte(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ler QR da pulseira')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.qr_code_2, size: 64),
              const SizedBox(height: 16),
              Text(
                'Leitura de QR só no aplicativo instalado no celular.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Busque o participante pelo nome na lista.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.search),
                label: const Text('Buscar pelo nome'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
