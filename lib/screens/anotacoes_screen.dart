import 'package:flutter/material.dart';

import '../models/anotacao.dart';
import '../models/participant.dart';
import '../models/team.dart';
import '../models/top.dart';
import '../services/anotacao_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/botao_inicio.dart';

/// Bloco de anotações.
///
/// O app é dos Legendários, e as 9 equipes trabalham no Top. A diferença é
/// que a equipe **Hakunas** tem prontuário — dado clínico, com cerca
/// própria — e todas elas precisam de um lugar para registrar o que
/// acontece no turno.
///
/// **Cada membro tem o seu bloco, e ele é editável.** Não há sobrescrita
/// entre pessoas porque cada login tem o bloco dele. Abaixo do campo
/// aparecem os blocos dos colegas da equipe, em leitura.
///
/// Abre de dois lugares:
///
/// - da lista de chats: o bloco do turno naquela equipe;
/// - da ficha de um participante: o bloco sobre **aquela pessoa**.
///
/// Funciona sem rede: o texto fica no aparelho e sobe quando o sinal
/// voltar.
class AnotacoesScreen extends StatefulWidget {
  const AnotacoesScreen({
    super.key,
    required this.top,
    required this.team,
    this.participante,
  });

  final Top top;
  final TeamKey team;
  final Participant? participante;

  @override
  State<AnotacoesScreen> createState() => _AnotacoesScreenState();
}

class _AnotacoesScreenState extends State<AnotacoesScreen> {
  final _texto = TextEditingController();

  Anotacao? _meu;
  List<Anotacao> _daEquipe = [];
  bool _carregando = true;
  bool _salvando = false;
  bool _naFila = false;
  String? _erroDeRede;

  /// Se o texto na tela difere do que está salvo. Governa o aviso de
  /// "não salvo" e o estado do botão.
  bool _mudou = false;

  @override
  void initState() {
    super.initState();
    _texto.addListener(_verificarMudanca);
    _carregar();
  }

  @override
  void dispose() {
    _texto.removeListener(_verificarMudanca);
    _texto.dispose();
    super.dispose();
  }

  void _verificarMudanca() {
    final mudou = _texto.text.trim() != (_meu?.texto ?? '').trim();
    if (mudou != _mudou) setState(() => _mudou = mudou);
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erroDeRede = null;
    });

    // O que está NO APARELHO primeiro, e fora do try da rede.
    //
    // A ordem é a proteção: o bloco da fila é a versão mais recente, e se
    // a busca no servidor viesse antes e falhasse, o `catch` deixaria a
    // tela com o texto antigo — ou vazia — por cima do que a pessoa
    // acabou de escrever.
    Anotacao? local;
    try {
      local = await AnotacaoService.instance.meuBlocoNaFila(
        topId: widget.top.id,
        team: widget.team,
        participanteId: widget.participante?.id,
      );
    } catch (_) {
      // Falha de disco. Não impede tentar o servidor.
    }
    if (local != null && mounted) {
      setState(() {
        _meu = local;
        _naFila = true;
        _texto.text = local!.texto;
        _mudou = false;
      });
    }

    try {
      final doServidor = await AnotacaoService.instance.meuBloco(
        topId: widget.top.id,
        team: widget.team,
        participanteId: widget.participante?.id,
      );
      final equipe = await AnotacaoService.instance.daEquipe(
        topId: widget.top.id,
        team: widget.team,
        participanteId: widget.participante?.id,
      );
      if (!mounted) return;
      setState(() {
        // O do servidor só substitui o da fila se não houver versão local:
        // o que está na fila é mais novo por definição.
        if (local == null) {
          _meu = doServidor;
          _naFila = false;
          _texto.text = doServidor?.texto ?? '';
          _mudou = false;
        }
        _daEquipe = equipe;
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
    if (texto.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Escreva algo antes de salvar.')),
      );
      return;
    }

    setState(() => _salvando = true);
    try {
      final salvo = await AnotacaoService.instance.salvar(
        topId: widget.top.id,
        team: widget.team,
        texto: texto,
        participanteId: widget.participante?.id,
        anterior: _meu,
      );
      if (!mounted) return;
      setState(() {
        _meu = salvo;
        _mudou = false;
      });
      await _carregar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _naFila
                ? 'Salvo no aparelho. Sobe quando a rede voltar.'
                : 'Bloco salvo.',
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
    // Os blocos dos colegas: tudo da equipe menos o meu.
    final dosColegas = _daEquipe
        .where((a) => a.blocoId != _meu?.blocoId)
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.participante != null
              ? 'Anotações · ${widget.participante!.fullName}'
              : 'Anotações · ${widget.team.label}',
        ),
        actions: const [BotaoInicio(), AppLogoTrailing()],
      ),
      body: ListView(
        children: [
          // Aviso FIXO, não um diálogo que se dispensa. Sintoma escrito
          // aqui fica fora da triagem e invisível para quem vai atender:
          // é o erro mais provável desta tela e o mais caro.
          Container(
            width: double.infinity,
            color: cores.secondaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 18,
                  color: cores.onSecondaryContainer,
                ),
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
                Row(
                  children: [
                    Text(
                      'Meu bloco',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const Spacer(),
                    if (_naFila)
                      Row(
                        children: [
                          Icon(
                            Icons.cloud_upload_outlined,
                            size: 15,
                            color: cores.tertiary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'aguardando sinal',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      )
                    else if (_meu != null)
                      Text(
                        'salvo ${_quando(_meu!.atualizadoEm)}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                  ],
                ),
                const SizedBox(height: 8),

                TextField(
                  controller: _texto,
                  minLines: 6,
                  maxLines: 20,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: widget.participante != null
                        ? 'O que você precisa registrar sobre '
                              '${widget.participante!.fullName}'
                        : 'Ocorrências, combinados, pendências do turno…',
                    border: const OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),

                if (_mudou)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Alterações não salvas.',
                      style: TextStyle(
                        color: cores.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                FilledButton.icon(
                  // Desabilitado quando nada mudou: evita gravar uma
                  // versão igual à anterior e poluir a fila.
                  onPressed: (_salvando || !_mudou) ? null : _salvar,
                  icon: _salvando
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Salvar'),
                ),
              ],
            ),
          ),

          if (_erroDeRede != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Card(
                color: cores.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.wifi_off),
                  title: const Text('Sem internet'),
                  subtitle: Text(
                    'Seu bloco está salvo no aparelho. O que a equipe '
                    'escreveu em outro celular não dá para buscar agora.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ),

          if (_carregando)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (dosColegas.isNotEmpty) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: Text(
                'Blocos da equipe (${dosColegas.length})',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            for (final a in dosColegas)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _BlocoDoColega(anotacao: a, quando: _quando),
              ),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }

  String _quando(DateTime utc) {
    final l = utc.toLocal();
    return '${l.day.toString().padLeft(2, "0")}/'
        '${l.month.toString().padLeft(2, "0")} '
        '${l.hour.toString().padLeft(2, "0")}:'
        '${l.minute.toString().padLeft(2, "0")}';
  }
}

class _BlocoDoColega extends StatelessWidget {
  const _BlocoDoColega({required this.anotacao, required this.quando});

  final Anotacao anotacao;
  final String Function(DateTime) quando;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  anotacao.team.iconeOperacional,
                  size: 14,
                  color: anotacao.team.cor,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    anotacao.autorNome ?? 'Membro da equipe',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  quando(anotacao.atualizadoEm),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
            if (anotacao.sobrePessoa && anotacao.participanteNome != null) ...[
              const SizedBox(height: 4),
              Text(
                'Sobre: ${anotacao.participanteNome}',
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
