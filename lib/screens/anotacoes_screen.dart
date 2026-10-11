import 'package:flutter/material.dart';

import '../models/anotacao.dart';
import '../models/participant.dart';
import '../models/team.dart';
import '../models/top.dart';
import '../services/anotacao_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/botao_inicio.dart';

/// Bloco de anotações de uma equipe.
///
/// O app é dos Legendários, não só dos Hakunas. A diferença é que o Hakuna
/// tem **prontuário** — dado clínico, com cerca própria — e as outras 8
/// equipes precisam do equivalente não-médico: um lugar para registrar o
/// que aconteceu no turno.
///
/// Abre de dois lugares, e o conteúdo muda conforme:
///
/// - da tela de equipes: todas as anotações da equipe naquele Top;
/// - da ficha de um participante: só as sobre aquela pessoa, e o que se
///   escrever ali já sai ligado a ela.
///
/// Funciona sem rede. O que está esperando sinal aparece na lista,
/// marcado — senão quem escreveu não veria a própria anotação e escreveria
/// de novo.
class AnotacoesScreen extends StatefulWidget {
  const AnotacoesScreen({
    super.key,
    required this.top,
    required this.team,
    this.participante,
  });

  final Top top;
  final TeamKey team;

  /// Quando vem preenchido, a tela é o bloco de anotações **daquela
  /// pessoa** dentro desta equipe.
  final Participant? participante;

  @override
  State<AnotacoesScreen> createState() => _AnotacoesScreenState();
}

class _AnotacoesScreenState extends State<AnotacoesScreen> {
  final _texto = TextEditingController();

  List<Anotacao> _doServidor = [];
  List<Anotacao> _naFila = [];
  bool _carregando = true;
  bool _salvando = false;
  String? _erroDeRede;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erroDeRede = null;
    });

    // O que está no APARELHO primeiro, e fora do try da rede. Mesma ordem
    // do prontuário, pelo mesmo motivo: quando a rede falha, o `catch` não
    // pode engolir o que a pessoa acabou de escrever.
    try {
      final fila = await AnotacaoService.instance.naFila(
        topId: widget.top.id,
        team: widget.team,
        participanteId: widget.participante?.id,
      );
      if (mounted) setState(() => _naFila = fila);
    } catch (_) {
      // Falha de disco. Não impede tentar o servidor.
    }

    try {
      final lista = await AnotacaoService.instance.doTop(
        topId: widget.top.id,
        team: widget.team,
        participanteId: widget.participante?.id,
      );
      if (!mounted) return;
      setState(() {
        _doServidor = lista;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erroDeRede = '$e';
        _carregando = false;
      });
    }
  }

  Future<void> _salvar() async {
    final texto = _texto.text.trim();
    if (texto.isEmpty) return;

    setState(() => _salvando = true);
    try {
      await AnotacaoService.instance.registrar(
        topId: widget.top.id,
        team: widget.team,
        texto: texto,
        participanteId: widget.participante?.id,
      );
      if (!mounted) return;
      _texto.clear();
      await _carregar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _naFila.isEmpty
                ? 'Anotação salva e enviada.'
                : 'Anotação GRAVADA no aparelho. Sobe quando a rede voltar.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível salvar: $e')),
      );
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final todas = [..._naFila, ..._doServidor];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.participante != null
              ? 'Anotações · ${widget.participante!.fullName}'
              : 'Anotações · ${widget.team.label}',
        ),
        actions: const [BotaoInicio(), AppLogoTrailing()],
      ),
      body: Column(
        children: [
          // O aviso fica FIXO em cima do campo, não num diálogo que se
          // dispensa. Sintoma escrito aqui não entra na triagem e não
          // aparece para quem vai atender — o Hakuna nunca leria. É o
          // erro mais provável desta tela, e o mais caro.
          Container(
            width: double.infinity,
            color: cores.secondaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: cores.onSecondaryContainer),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Anotação de trabalho da equipe ${widget.team.label}. '
                    'NÃO escreva sintoma, pressão ou conduta aqui — isso vai '
                    'no atendimento, senão a triagem não vê.',
                    style: TextStyle(
                      fontSize: 12,
                      color: cores.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _texto,
                  minLines: 3,
                  maxLines: 8,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'O que aconteceu?',
                    hintText: widget.participante != null
                        ? 'Sobre ${widget.participante!.fullName}'
                        : 'Ocorrência, combinado, pendência do turno…',
                    border: const OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _salvando ? null : _salvar,
                  icon: _salvando
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Salvar anotação'),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _carregar,
                    child: ListView(
                      padding: const EdgeInsets.all(12),
                      children: [
                        if (_erroDeRede != null)
                          Card(
                            color: cores.errorContainer,
                            child: ListTile(
                              leading: const Icon(Icons.wifi_off),
                              title: const Text(
                                'Sem internet: aparecem só as anotações '
                                'feitas neste aparelho',
                              ),
                              subtitle: Text(
                                'O que a equipe escreveu em outro celular '
                                'não dá para buscar agora.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ),
                        if (todas.isEmpty && _erroDeRede == null)
                          const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(
                              child: Text(
                                'Nenhuma anotação ainda.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        for (final a in todas)
                          _CartaoAnotacao(
                            anotacao: a,
                            // As da fila vêm primeiro na lista montada
                            // acima; marcá-las é o que diz ao autor que a
                            // anotação está salva mas ainda não chegou
                            // para os outros.
                            aguardandoSinal: _naFila.contains(a),
                            mostrarParticipante: widget.participante == null,
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _CartaoAnotacao extends StatelessWidget {
  const _CartaoAnotacao({
    required this.anotacao,
    required this.aguardandoSinal,
    required this.mostrarParticipante,
  });

  final Anotacao anotacao;
  final bool aguardandoSinal;
  final bool mostrarParticipante;

  @override
  Widget build(BuildContext context) {
    final local = anotacao.criadaEm.toLocal();
    final quando =
        '${local.day.toString().padLeft(2, "0")}/'
        '${local.month.toString().padLeft(2, "0")} '
        '${local.hour.toString().padLeft(2, "0")}:'
        '${local.minute.toString().padLeft(2, "0")}';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(anotacao.team.iconeOperacional, size: 14,
                    color: anotacao.team.cor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    // "Você" quando o nome não veio: a anotação está na
                    // fila, e quem a escreveu é quem está olhando.
                    anotacao.autorNome ?? 'Você',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (aguardandoSinal)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(
                      Icons.cloud_upload_outlined,
                      size: 15,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                  ),
                Text(quando, style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
            if (mostrarParticipante && anotacao.sobrePessoa) ...[
              const SizedBox(height: 4),
              Text(
                'Sobre: ${anotacao.participanteNome ?? "participante"}',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
            const SizedBox(height: 8),
            Text(anotacao.texto),
          ],
        ),
      ),
    );
  }
}
