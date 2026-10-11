import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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

  /// O que o chip entregou na última aproximação, identificado ou não.
  ///
  /// Guardado separado do [_resultado] porque serve quando o resultado é
  /// ruim: cartão em branco, de outro sistema ou que o celular não
  /// formata. Mostrar o UID e o tipo transforma "não deu" em "este cartão
  /// é um MIFARE Classic sem conteúdo" — que é uma informação acionável.
  LeituraNfc? _chip;

  /// Regras de triagem para pintar a cor na ficha que esta tela abre.
  ///
  /// A tela busca as suas se quem a abriu nao as tinha em maos. Sem isto,
  /// abrir a ficha pela pulseira mostrava o participante **sem cor de
  /// triagem** — a prioridade dele desaparecia justamente no caminho mais
  /// rapido, o de encostar o celular no paciente. Vem de `DadosDoTop`, que
  /// le o SQLite primeiro: funciona sem sinal.
  late List<TriageRule> _regras = widget.regras;

  @override
  void initState() {
    super.initState();
    _verificarNfc();
    if (_regras.isEmpty) _carregarRegras();
  }

  Future<void> _carregarRegras() async {
    try {
      final regras = await DadosDoTop.instance.regras();
      if (mounted) setState(() => _regras = regras);
    } catch (_) {
      // Sem regras a ficha abre sem cor, que e melhor que nao abrir.
      // Identificar o paciente nunca pode depender disto.
    }
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
          () => _nfcDisponivel =
              disponibilidade == DisponibilidadeNfc.pronto,
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
      _chip = null;
    });
    try {
      final chip = await NfcService.instance.lerTag();
      final leitura = await TagService.instance.resolver(
        chip.conteudo,
        topId: widget.top.id,
      );
      if (!mounted) return;
      setState(() {
        _chip = chip;
        _resultado = leitura;
        _lendo = false;
      });
      if (leitura.identificou) _abrirFicha(leitura);
    } catch (e) {
      if (!mounted) return;
      setState(() => _lendo = false);
      // `ErroDeNfc` já vem em português e diz o que fazer. Prefixar com
      // "Não foi possível ler a tag" criaria redundância, e o caso mais
      // comum (ninguém encostou em 30 s) não é nem uma falha.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is ErroDeNfc ? e.mensagem : 'Não foi possível ler a tag: $e',
          ),
        ),
      );
    }
  }

  /// `pushReplacement` e não `push`: voltar do QR para esta tela não serve
  /// para nada — as duas fazem a mesma coisa por sensores diferentes, e o
  /// botão "Buscar pelo nome" do QR já devolve o Hakuna para a lista.
  void _abrirQr() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => LerQrScreen(top: widget.top, regras: _regras),
      ),
    );
  }

  void _abrirFicha(LeituraTag leitura) {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ParticipantFileScreen(
          participante: leitura.participante!,
          top: widget.top,
          regras: _regras,
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
                if (_resultado != null && !_resultado!.identificou) ...[
                  _Aviso(resultado: _resultado!.resultado),
                  if (_chip != null) _FichaDoChip(chip: _chip!),
                ],
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

/// O que o chip é, quando ele não é uma pulseira conhecida.
///
/// Só aparece depois de uma leitura que não identificou ninguém. Serve
/// para quem está com o cartão na mão decidir o que fazer: UID presente e
/// sem NDEF é cartão em branco ou bloqueado para gravação; nenhum dado é
/// aproximação que não completou.
class _FichaDoChip extends StatelessWidget {
  const _FichaDoChip({required this.chip});

  final LeituraNfc chip;

  @override
  Widget build(BuildContext context) {
    if (chip.vazia) return const SizedBox.shrink();
    final estilo = Theme.of(context).textTheme.labelSmall;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        children: [
          if (chip.uid.isNotEmpty)
            SelectableText(
              'UID ${chip.uidLegivel}',
              style: estilo?.copyWith(fontFamily: 'monospace'),
            ),
          Text(
            '${chip.tipo} · ${chip.padrao} · '
            '${chip.temNdef ? (chip.gravavel ? "NDEF gravável" : "NDEF protegido") : "sem NDEF"}',
            textAlign: TextAlign.center,
            style: estilo,
          ),
          if (!chip.temNdef)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Este cartão não tem conteúdo NDEF. Se é pulseira nova, '
                'emita por "Emitir pulseiras" no menu do Top.',
                textAlign: TextAlign.center,
                style: estilo,
              ),
            ),
        ],
      ),
    );
  }
}
