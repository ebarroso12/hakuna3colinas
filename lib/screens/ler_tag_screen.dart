import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nfc_manager/nfc_manager.dart';

import '../models/participant_tag.dart';
import '../models/top.dart';
import '../models/triage_rule.dart';
import '../offline/dados_do_top.dart';
import '../services/nfc_service.dart';
import '../services/qr_token_service.dart';
import '../services/tag_service.dart';
import 'ler_qr_screen.dart';
import 'participant_file_screen.dart';
import '../widgets/botao_inicio.dart';

/// LER TAG — encosta o celular na pulseira e abre a ficha de quem é.
///
/// Se a tag falhar por qualquer motivo, a tela manda o Hakuna para a busca
/// por nome em vez de deixá-lo parado. Identificar o paciente nunca pode
/// depender de a pulseira funcionar.
class LerTagScreen extends StatefulWidget {
  const LerTagScreen({super.key, required this.top, this.regras = const []});

  final Top top;
  final List<TriageRule> regras;

  @override
  State<LerTagScreen> createState() => _LerTagScreenState();
}

class _LerTagScreenState extends State<LerTagScreen> {
  bool _lendo = false;
  bool _nfcDisponivel = true;
  LeituraTag? _resultado;

  @override
  void initState() {
    super.initState();
    _verificarNfc();
  }

  Future<void> _verificarNfc() async {
    if (kIsWeb) {
      setState(() => _nfcDisponivel = false);
      return;
    }
    try {
      final disponibilidade = await NfcService.instance.checkAvailability();
      if (mounted) {
        setState(
          () => _nfcDisponivel = disponibilidade == NfcAvailability.enabled,
        );
      }
    } catch (_) {
      if (mounted) setState(() => _nfcDisponivel = false);
    }
  }

  Future<void> _ler() async {
    setState(() {
      _lendo = true;
      _resultado = null;
    });
    try {
      final conteudo = await NfcService.instance.readTagText();
      final leitura = await TagService.instance.resolver(
        conteudo,
        topId: widget.top.id,
      );
      if (!mounted) return;
      setState(() {
        _resultado = leitura;
        _lendo = false;
      });
      if (leitura.identificou) _abrirFicha(leitura);
    } catch (e) {
      if (!mounted) return;
      setState(() => _lendo = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Não foi possível ler a tag: $e')));
    }
  }

  /// `pushReplacement` e não `push`: voltar do QR para esta tela não serve
  /// para nada — as duas fazem a mesma coisa por sensores diferentes, e o
  /// botão "Buscar pelo nome" do QR já devolve o Hakuna para a lista.
  void _abrirQr() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => LerQrScreen(top: widget.top, regras: widget.regras),
      ),
    );
  }

  void _abrirFicha(LeituraTag leitura) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ParticipantFileScreen(
          participante: leitura.participante!,
          top: widget.top,
          regras: widget.regras,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        actions: const [BotaoInicio()],
        title: const Text('Ler tag'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!_nfcDisponivel) ...[
                const Icon(Icons.nfc, size: 64),
                const SizedBox(height: 16),
                Text(
                  kIsWeb
                      ? 'Leitura de NFC não existe no navegador.'
                      : 'Este aparelho não tem NFC disponível.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Use o QR da pulseira, ou busque pelo nome na lista.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                // Aparelho sem NFC: aqui o QR é o caminho principal, não
                // alternativa. Por isso botão preenchido e grande.
                if (QrTokenService.suportado)
                  FilledButton.icon(
                    onPressed: () => _abrirQr(),
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('LER QR DA PULSEIRA'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                  ),
              ] else ...[
                GestureDetector(
                  onTap: _lendo ? null : _ler,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_lendo)
                          const CircularProgressIndicator()
                        else
                          const Icon(Icons.nfc, size: 72),
                        const SizedBox(height: 12),
                        Text(
                          _lendo ? 'Aproxime a tag…' : 'LER TAG',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (_resultado != null && !_resultado!.identificou)
                  _Aviso(resultado: _resultado!.resultado),
                // Com NFC disponível o QR é contingência: o chip da
                // pulseira pode ter parado de responder mesmo com o sensor
                // do celular funcionando. Botão discreto, mas presente —
                // descobrir isso no mato com a pessoa esperando é tarde.
                if (QrTokenService.suportado) ...[
                  const SizedBox(height: 16),
                  TextButton.icon(
                    onPressed: _lendo ? null : _abrirQr,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('A pulseira não responde? Ler o QR'),
                  ),
                ],
              ],
              const SizedBox(height: 32),
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

class _Aviso extends StatelessWidget {
  const _Aviso({required this.resultado});

  final ResultadoLeitura resultado;

  @override
  Widget build(BuildContext context) {
    final grave = resultado == ResultadoLeitura.revogada;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: grave ? scheme.errorContainer : scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              grave ? Icons.gpp_bad : Icons.info_outline,
              color: grave ? scheme.onErrorContainer : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                resultado.mensagem,
                style: TextStyle(color: grave ? scheme.onErrorContainer : null),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Baixa participantes, tags e regras do Top para o SQLite do aparelho,
/// antes de entrar em área sem sinal.
///
/// Substitui a versão anterior, que tinha dois problemas: gravava num `Map`
/// em memória (perdido quando o sistema matava o app) e fazia **uma
/// consulta de rede por tag** — 215 ida-e-voltas. Agora são três consultas
/// em bloco e o resultado fica em disco.
Future<ResumoDownload> baixarDadosDoTop(Top top) =>
    DadosDoTop.instance.baixar(top.id);
