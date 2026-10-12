import 'package:flutter/material.dart';

import '../models/profile.dart';
import '../models/team.dart';
import '../models/team_message.dart';
import '../models/top.dart';
import '../offline/chat_repositorio.dart';
import '../services/supabase_service.dart';
import '../widgets/botao_inicio.dart';
import '../widgets/botao_da_malha.dart';

/// Chat de uma equipe dentro de um Top. [TeamKey.geral] é o chat geral.
class TeamChatScreen extends StatefulWidget {
  const TeamChatScreen({
    super.key,
    required this.top,
    required this.team,
    this.isTeamAdmin = false,
  });

  final Top top;
  final TeamKey team;

  /// Admin da equipe pode marcar a mensagem como alerta. A RLS rejeita o
  /// insert de quem não for — isto aqui só evita mostrar um controle que
  /// resultaria em erro.
  final bool isTeamAdmin;

  @override
  State<TeamChatScreen> createState() => _TeamChatScreenState();
}

class _TeamChatScreenState extends State<TeamChatScreen> {
  final _controller = TextEditingController();
  Map<String, Profile> _profiles = {};
  bool _sending = false;
  bool _comoAlerta = false;
  String? _sendError;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Nomes de quem escreve. Falha aqui não é crítica: o chat cai de volta
  /// para o id cru do remetente.
  Future<void> _loadProfiles() async {
    try {
      final p = await SupabaseService.instance.fetchTeamProfiles(
        topId: widget.top.id,
        team: widget.team,
      );
      if (mounted) setState(() => _profiles = p);
    } catch (_) {
      // segue sem os nomes
    }
  }

  /// Enfileira a mensagem. **Não espera rede.**
  ///
  /// Antes isto chamava o Supabase direto: sem sinal o envio falhava, o
  /// texto ficava no campo e o Hakuna tinha de lembrar de reenviar. Agora
  /// a mensagem entra na fila do aparelho, limpa o campo e aparece na lista
  /// marcada como pendente.
  ///
  /// O `catch` aqui só pega falha de gravação no **próprio aparelho** —
  /// disco cheio ou banco corrompido. Falta de rede não é erro: é o estado
  /// normal de operação.
  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      await ChatRepositorio.instance.enviarParaEquipe(
        topId: widget.top.id,
        team: widget.team,
        body: text,
        isAlert: _comoAlerta,
      );
      _controller.clear();
      if (mounted) setState(() => _comoAlerta = false);
    } catch (e) {
      if (mounted) {
        setState(() => _sendError = 'Não foi possível guardar no aparelho: $e');
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = SupabaseService.instance.currentUser?.id;
    return Scaffold(
      appBar: AppBar(
        actions: const [BotaoInicio()],
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.team.label),
            Text(
              widget.top.name,
              style: Theme.of(context).textTheme.labelSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<ChatNaTela<TeamMessage>>(
              stream: ChatRepositorio.instance.observarEquipe(
                topId: widget.top.id,
                team: widget.team,
              ),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final chat = snapshot.data!;
                final mensagens = chat.mensagens;

                if (mensagens.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        chat.offline
                            ? 'Sem conexão com o chat. Mensagens enviadas '
                                  'agora ficam guardadas no aparelho e sobem '
                                  'quando o sinal voltar.'
                            : widget.team.isGeral
                            ? 'Nenhuma mensagem no chat geral ainda.'
                            : 'Nenhuma mensagem da equipe ${widget.team.label} ainda.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                return Column(
                  children: [
                    // Aviso em vez de tela de erro: o histórico continua
                    // visível. Trocar a lista por uma mensagem de erro
                    // tirava do Hakuna o acesso ao que já havia sido dito.
                    // O controle do rádio fica AQUI, e não na barra do
                    // Top: é nesta tela que a pessoa percebe que a
                    // mensagem não está saindo, e é aqui que ligar faz
                    // sentido para ela.
                    BotaoDaMalha(top: widget.top),
                    if (chat.offline) _AvisoOffline(pendentes: chat.pendentes),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: mensagens.length,
                        itemBuilder: (context, i) {
                          final m = mensagens[i];
                          return _Bolha(
                            mensagem: m,
                            isMine: m.senderId == myId,
                            // Mensagem do rádio carrega o nome dentro
                            // dela: `profiles` é fechada para quem
                            // recebe, e sem rede não há como resolver o
                            // uuid. Nunca cair no uuid cru — ele ocupa a
                            // linha do nome e não ajuda a achar ninguém.
                            remetente:
                                _profiles[m.senderId]?.displayLabel ??
                                m.senderName ??
                                'Alguém do Top',
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (_sendError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                _sendError!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (widget.isTeamAdmin)
                    CheckboxListTile(
                      value: _comoAlerta,
                      onChanged: (v) =>
                          setState(() => _comoAlerta = v ?? false),
                      title: const Text('Enviar como alerta'),
                      subtitle: const Text(
                        'Destaca a mensagem para toda a equipe',
                      ),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          minLines: 1,
                          maxLines: 4,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          decoration: const InputDecoration(
                            hintText: 'Mensagem',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        onPressed: _sending ? null : _send,
                        icon: _sending
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send),
                      ),
                    ],
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

/// Faixa de "chat sem conexão". Compartilhada com o chat do Top.
class _AvisoOffline extends StatelessWidget {
  const _AvisoOffline({required this.pendentes});

  final int pendentes;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.cloud_off, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                pendentes == 0
                    ? 'Sem conexão. O chat não está recebendo mensagens novas.'
                    : pendentes == 1
                    ? 'Sem conexão. 1 mensagem guardada no aparelho.'
                    : 'Sem conexão. $pendentes mensagens guardadas no '
                          'aparelho.',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bolha extends StatelessWidget {
  const _Bolha({
    required this.mensagem,
    required this.isMine,
    required this.remetente,
  });

  final TeamMessage mensagem;
  final bool isMine;
  final String remetente;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hora = TimeOfDay.fromDateTime(mensagem.createdAt.toLocal())
        .format(context);

    final pendente = mensagem.pendente;

    // Chegou pelo rádio de outro aparelho e NINGUÉM confirmou a autoria.
    //
    // No servidor a RLS prende `sender_id = auth.uid()`: é impossível
    // falar no nome de outro. Pelo rádio, qualquer aparelho ao alcance
    // pode afirmar o que quiser de quem quiser.
    //
    // Numa emergência isso move gente: "o coordenador mandou descer"
    // forjado tira 200 pessoas do lugar. A bolha tem de dizer, e dizer
    // de um jeito que não se confunda com "ainda não enviou".
    final semAutoria = mensagem.semAutoriaConfirmada;

    final fundo = mensagem.isAlert
        ? scheme.errorContainer
        : isMine
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;
    final texto = mensagem.isAlert
        ? scheme.onErrorContainer
        : isMine
        ? scheme.onPrimaryContainer
        : scheme.onSurface;

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: fundo,
          borderRadius: BorderRadius.circular(12),
          // Contorno em vez de outra cor de fundo: cor já está ocupada
          // por alerta e por autoria própria, e somar uma terceira faria
          // as três competirem. O contorno é lido como "esta é
          // diferente" sem disputar com o resto.
          border: semAutoria
              ? Border.all(color: scheme.outline, width: 1.5)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Vem ANTES do texto de propósito: quem lê precisa saber de
            // onde veio a informação antes de agir sobre ela.
            if (semAutoria)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.wifi_tethering,
                      size: 14,
                      color: texto.withValues(alpha: 0.85),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Chegou por rádio · remetente NÃO confirmado',
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(
                              color: texto.withValues(alpha: 0.85),
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            if (mensagem.isAlert)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.priority_high, size: 16, color: texto),
                  const SizedBox(width: 4),
                  Text(
                    'ALERTA',
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: texto, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            if (!isMine)
              Text(
                remetente,
                style: Theme.of(context).textTheme.labelSmall
                    ?.copyWith(color: texto),
              ),
            Text(mensagem.body, style: TextStyle(color: texto)),
            // Relógio enquanto não entregue. É a informação que falta no
            // mato: sem isso o Hakuna acredita que avisou a equipe e
            // ninguém recebeu.
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (pendente) ...[
                  Icon(
                    Icons.schedule,
                    size: 12,
                    color: texto.withValues(alpha: 0.7),
                  ),
                  const SizedBox(width: 3),
                ],
                Text(
                  pendente
                      ? 'aguardando sinal'
                      : mensagem.editedAt != null
                      ? '$hora · editada'
                      : hora,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: texto.withValues(alpha: 0.7),
                    fontStyle: pendente ? FontStyle.italic : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
