import 'package:flutter/material.dart';

import '../offline/outbox.dart';
import '../offline/sync_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/botao_inicio.dart';

/// FILA DO APARELHO — o que ainda não subiu, e o que foi recusado.
///
/// **Por que esta tela existe:** a quarentena resolve o travamento da fila,
/// mas cria um risco novo — entrada que sai da fila sem ninguém saber é
/// perda silenciosa. Um atendimento recusado pela RLS que não aparece em
/// lugar nenhum é pior que uma fila travada: na fila travada alguém
/// percebe que nada sobe.
///
/// Então quarentena **tem** de ser visível e reversível. É o que esta tela
/// faz: mostra o motivo em português e deixa devolver à fila depois de a
/// causa ser resolvida (o admin ativou o Top, liberou o Hakuna, devolveu a
/// coordenação da equipe).
class FilaOfflineScreen extends StatefulWidget {
  const FilaOfflineScreen({super.key});

  @override
  State<FilaOfflineScreen> createState() => _FilaOfflineScreenState();
}

class _FilaOfflineScreenState extends State<FilaOfflineScreen> {
  List<OutboxEntry> _pendentes = const [];
  List<OutboxEntry> _recusadas = const [];
  bool _carregando = true;
  bool _sincronizando = false;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final pendentes = await Outbox.instance.pending(limit: 500);
    final recusadas = await Outbox.instance.quarantined();
    if (!mounted) return;
    setState(() {
      _pendentes = pendentes;
      _recusadas = recusadas;
      _carregando = false;
    });
  }

  Future<void> _sincronizar() async {
    setState(() => _sincronizando = true);
    final r = await SyncService.instance.syncNow();
    if (!mounted) return;
    setState(() => _sincronizando = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Enviados: ${r.enviados} · recusados: ${r.quarentenados} · '
          'ainda na fila: ${r.aindaPendentes}',
        ),
      ),
    );
    await _carregar();
  }

  Future<void> _devolverTudo() async {
    final quantas = await Outbox.instance.requeueAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$quantas devolvidas à fila.')));
    await _carregar();
    await _sincronizar();
  }

  /// Descartar perde o dado. Confirmação explícita, com o conteúdo à vista.
  Future<void> _descartar(OutboxEntry e) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Descartar definitivamente?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Isto apaga o registro do aparelho. Ele nunca chegou ao '
              'servidor, então não há como recuperar depois.',
            ),
            const SizedBox(height: 12),
            Text(
              _rotuloDaEntidade(e.entity),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(_resumo(e), style: const TextStyle(fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (confirmou != true) return;
    await Outbox.instance.descartar(e.id);
    await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fila do aparelho'),
        actions: [
          const BotaoInicio(),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recarregar',
            onPressed: _carregando ? null : _carregar,
          ),
          const AppLogoTrailing(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _sincronizando ? null : _sincronizar,
        icon: _sincronizando
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.cloud_upload),
        label: const Text('Enviar agora'),
      ),
      body: _carregando
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.only(bottom: 88),
              children: [
                if (_recusadas.isNotEmpty) _blocoRecusadas(),
                _blocoPendentes(),
              ],
            ),
    );
  }

  Widget _blocoRecusadas() {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: scheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.block, color: scheme.onErrorContainer),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _recusadas.length == 1
                            ? '1 registro recusado pelo servidor'
                            : '${_recusadas.length} registros recusados pelo '
                                  'servidor',
                        style: TextStyle(
                          color: scheme.onErrorContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Estes saíram da fila para não travar o resto. Resolva a '
                  'causa (ativar o Top, liberar o Hakuna, devolver a '
                  'coordenação) e devolva à fila.',
                  style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _devolverTudo,
                  icon: const Icon(Icons.replay),
                  label: const Text('Devolver todos à fila'),
                ),
              ],
            ),
          ),
        ),
        for (final e in _recusadas) _linhaRecusada(e),
        const Divider(height: 24),
      ],
    );
  }

  Widget _linhaRecusada(OutboxEntry e) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _rotuloDaEntidade(e.entity),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(_resumo(e), style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 6),
            Text(
              e.quarantineReason ?? 'motivo não registrado',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            Text(
              'Escrito em ${_data(e.createdAt)}',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () async {
                    await Outbox.instance.requeue(e.id);
                    await _carregar();
                  },
                  icon: const Icon(Icons.replay, size: 18),
                  label: const Text('Devolver à fila'),
                ),
                TextButton.icon(
                  onPressed: () => _descartar(e),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Descartar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _blocoPendentes() {
    if (_pendentes.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text(
            'Nada esperando envio. Tudo que foi registrado neste aparelho '
            'já chegou ao servidor.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // Agrupa por tipo: "47 posições e 3 atendimentos" é mais útil que uma
    // lista de 50 linhas iguais.
    final porEntidade = <String, int>{};
    for (final e in _pendentes) {
      porEntidade[e.entity] = (porEntidade[e.entity] ?? 0) + 1;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            'Esperando sinal (${_pendentes.length})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        for (final par in porEntidade.entries)
          ListTile(
            dense: true,
            leading: Icon(_iconeDaEntidade(par.key)),
            title: Text(_rotuloDaEntidade(par.key)),
            trailing: Text(
              '${par.value}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        if (_pendentes.any((e) => e.attempts > 0))
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Alguns já falharam ao enviar e serão tentados de novo. '
              'Depois de ${SyncService.maxTentativas} falhas seguidas, a '
              'entrada vai para a lista de recusados acima em vez de '
              'travar a fila.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  static String _rotuloDaEntidade(String entity) => switch (entity) {
    'atendimentos' => 'Atendimento',
    'atendimento_fotos' => 'Foto de atendimento',
    'hakuna_positions' => 'Posição de GPS',
    'team_messages' => 'Mensagem de equipe',
    'top_hakuna_messages' => 'Mensagem do Top',
    'tag_leituras' => 'Leitura de pulseira',
    'audit_log' => 'Registro de auditoria',
    _ => entity,
  };

  static IconData _iconeDaEntidade(String entity) => switch (entity) {
    'atendimentos' => Icons.medical_services_outlined,
    'atendimento_fotos' => Icons.photo_camera_outlined,
    'hakuna_positions' => Icons.location_on_outlined,
    'team_messages' => Icons.forum_outlined,
    'top_hakuna_messages' => Icons.chat_outlined,
    'tag_leituras' => Icons.nfc,
    'audit_log' => Icons.shield_outlined,
    _ => Icons.help_outline,
  };

  /// Resumo curto do conteúdo, para o usuário reconhecer o que é.
  ///
  /// Mostra o texto da mensagem e o procedimento do atendimento, que é o
  /// que identifica o registro para quem escreveu. Não mostra o payload
  /// inteiro: tem dado clínico e id interno, e esta tela pode ser aberta
  /// com alguém olhando por cima do ombro.
  static String _resumo(OutboxEntry e) {
    final p = e.payload;
    final texto = (p['body'] ?? p['notes'] ?? p['procedimento']) as String?;
    if (texto != null && texto.trim().isNotEmpty) {
      final t = texto.trim();
      return t.length <= 80 ? t : '${t.substring(0, 80)}…';
    }
    if (e.entity == 'hakuna_positions') {
      return 'ponto de trilha';
    }
    return 'registro ${e.clientId.substring(0, 8)}';
  }

  static String _data(DateTime d) {
    final l = d.toLocal();
    String dois(int n) => n.toString().padLeft(2, '0');
    return '${dois(l.day)}/${dois(l.month)} ${dois(l.hour)}:${dois(l.minute)}';
  }
}
