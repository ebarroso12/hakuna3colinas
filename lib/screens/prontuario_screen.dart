import 'package:flutter/material.dart';

import '../models/atendimento.dart';
import '../models/participant.dart';
import '../models/top.dart';
import '../services/atendimento_service.dart';
import '../services/supabase_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/botao_inicio.dart';
import '../widgets/fotos_do_atendimento.dart';
import 'atendimento_form_screen.dart';

/// HISTÓRICO DE ATENDIMENTOS do participante.
///
/// Só leitura: atendimento não se edita nem se apaga. Cada abertura vira um
/// registro novo, e é a sequência deles que forma o prontuário.
class ProntuarioScreen extends StatefulWidget {
  const ProntuarioScreen({
    super.key,
    required this.top,
    required this.participante,
    this.podeRegistrar = true,
  });

  final Top top;
  final Participant participante;

  /// Registrar atendimento é de Hakuna. Esconder o botão é cortesia; quem
  /// barra de verdade é a RLS de `atendimentos`.
  final bool podeRegistrar;

  @override
  State<ProntuarioScreen> createState() => _ProntuarioScreenState();
}

class _ProntuarioScreenState extends State<ProntuarioScreen> {
  List<Atendimento> _atendimentos = [];

  /// Atendimentos que ainda não subiram. Ficam separados do histórico do
  /// servidor para o Hakuna saber o que já está registrado lá e o que
  /// depende de sinal — não para esconder nada.
  List<Atendimento> _naFila = [];

  /// Caminhos locais das fotos por `clientId` do atendimento.
  Map<String, List<String>> _fotosNaFila = const {};
  int _pendentes = 0;
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });

    // O que está NO APARELHO primeiro, e fora do try da rede.
    //
    // Era o contrário: a busca no servidor vinha antes, e quando ela
    // falhava — offline, o normal na trilha — o `catch` engolia tudo e o
    // Hakuna não via nem o histórico nem o atendimento que ele mesmo
    // acabara de registrar. O prontuário ficava cego justamente onde é
    // mais necessário.
    try {
      final naFila = await AtendimentoService.instance.pendentesDoParticipante(
        topId: widget.top.id,
        participantId: widget.participante.id,
      );
      // Caminhos das fotos lidos AQUI, uma vez. Estavam num
      // `FutureBuilder` dentro do `build` do cartão, o que recriava o
      // Future — e portanto a leitura do SQLite — a cada rebuild. Leitura
      // de disco em `build` é exatamente o que não se faz.
      final fotos = <String, List<String>>{};
      for (final a in naFila) {
        fotos[a.clientId] = await AtendimentoService.instance.fotosNaFilaDe(
          a.clientId,
        );
      }
      if (!mounted) return;
      setState(() {
        _naFila = naFila;
        _pendentes = naFila.length;
        _fotosNaFila = fotos;
      });
    } catch (_) {
      // Falha de disco. Não impede tentar o servidor.
    }

    try {
      final lista = await SupabaseService.instance.fetchAtendimentos(
        topId: widget.top.id,
        participantId: widget.participante.id,
      );
      if (!mounted) return;
      setState(() {
        _atendimentos = lista;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erro = '$e';
        _carregando = false;
      });
    }
  }

  /// Encerra o atendimento, com confirmação.
  ///
  /// Pede confirmação porque não há "reabrir" na tela: desfazer exige
  /// admin no banco. O encerramento entra na fila, então funciona offline.
  Future<void> _encerrar(Atendimento a) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Encerrar atendimento ${a.numeroRegistro ?? ""}?'),
        content: const Text(
          'Marca este atendimento como concluído e registra quem encerrou e '
          'quando. Não há como reabrir pelo app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Encerrar'),
          ),
        ],
      ),
    );
    if (confirmou != true) return;

    try {
      await AtendimentoService.instance.encerrar(
        clientIdDoAtendimento: a.clientId,
        topId: widget.top.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Atendimento encerrado.')));
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Não foi possível encerrar: $e')));
    }
  }

  Future<void> _novoAtendimento() async {
    final numero = await AtendimentoService.instance.proximoNumero(
      topId: widget.top.id,
      jaExistentes: _atendimentos.length,
    );
    if (!mounted) return;
    final gravou = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => AtendimentoFormScreen(
          top: widget.top,
          participante: widget.participante,
          numeroSugerido: numero,
        ),
      ),
    );
    if (gravou ?? false) await _carregar();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Histórico (${_atendimentos.length})'),
            Text(
              widget.participante.fullName,
              style: Theme.of(context).textTheme.labelSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          const BotaoInicio(),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _carregando ? null : _carregar,
          ),
          const AppLogoTrailing(),
        ],
      ),
      floatingActionButton: widget.podeRegistrar
          ? FloatingActionButton.extended(
              onPressed: _novoAtendimento,
              icon: const Icon(Icons.post_add),
              label: const Text('Atendimento'),
            )
          : null,
      body: _corpo(),
    );
  }

  Widget _corpo() {
    if (_carregando) return const Center(child: CircularProgressIndicator());

    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
        children: [
          if (_pendentes > 0)
            Card(
              color: Theme.of(context).colorScheme.tertiaryContainer,
              child: ListTile(
                leading: const Icon(Icons.cloud_upload_outlined),
                title: Text('$_pendentes registro(s) aguardando sinal'),
                subtitle: const Text(
                  'Já estão salvos no celular e aparecem abaixo. Sobem '
                  'sozinhos quando houver internet.',
                ),
              ),
            ),
          if (_erro != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.wifi_off),
                title: const Text('Não foi possível buscar o histórico'),
                subtitle: Text(
                  'Sem internet, só aparecem os registros já sincronizados.\n'
                  '$_erro',
                ),
              ),
            ),
          if (_atendimentos.isEmpty && _naFila.isEmpty && _erro == null)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'Nenhum atendimento registrado para este participante.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          // Os da fila primeiro: são os mais recentes por definição, e é o
          // que o Hakuna acabou de fazer.
          ..._naFila.map(
            (a) => _CartaoAtendimento(
              atendimento: a,
              participante: widget.participante,
              aguardandoSinal: true,
              fotosLocais: _fotosNaFila[a.clientId] ?? const [],
              aoEncerrar: () => _encerrar(a),
            ),
          ),
          ..._atendimentos.map(
            (a) => _CartaoAtendimento(
              atendimento: a,
              participante: widget.participante,
              aoEncerrar: () => _encerrar(a),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartaoAtendimento extends StatelessWidget {
  const _CartaoAtendimento({
    required this.atendimento,
    required this.participante,
    this.aguardandoSinal = false,
    this.fotosLocais = const [],
    this.aoEncerrar,
  });

  final Atendimento atendimento;
  final Participant participante;

  /// Marca o cartão como "ainda no aparelho". Não esconde nada — o
  /// registro é o mesmo; só avisa que outro Hakuna ainda não o vê.
  final bool aguardandoSinal;

  /// Fotos deste atendimento que ainda estão no aparelho. Já resolvidas
  /// pela tela — o cartão não lê disco.
  final List<String> fotosLocais;

  /// Null quando a tela não oferece encerrar (histórico só de leitura).
  final VoidCallback? aoEncerrar;

  @override
  Widget build(BuildContext context) {
    final a = atendimento;
    final local = a.openedAt.toLocal();
    final data =
        '${local.day.toString().padLeft(2, "0")}/'
        '${local.month.toString().padLeft(2, "0")}/${local.year}';
    final hora =
        '${local.hour.toString().padLeft(2, "0")}:'
        '${local.minute.toString().padLeft(2, "0")}';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  child: Text(
                    '${a.numeroRegistro ?? "–"}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    participante.fullName.toUpperCase(),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (atendimento.encerrado)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(
                      Icons.check_circle,
                      size: 16,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                if (aguardandoSinal)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(
                      Icons.cloud_upload_outlined,
                      size: 16,
                      color: Theme.of(context).colorScheme.tertiary,
                    ),
                  ),
                Text(
                  '$data · $hora',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (a.resumoVitais != null) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      if (a.pressaoArterial != null)
                        _Vital(
                          'PA',
                          a.pressaoArterial!,
                          alerta: AlertaVital.pressaoAlterada(
                            a.systolicBp,
                            a.diastolicBp,
                          ),
                        ),
                      if (a.glicemiaMgDl != null)
                        _Vital(
                          'DX',
                          '${a.glicemiaMgDl}',
                          alerta: AlertaVital.glicemiaAlterada(a.glicemiaMgDl),
                        ),
                      if (a.spo2 != null)
                        _Vital(
                          'SpO₂',
                          '${a.spo2}%',
                          alerta: AlertaVital.spo2Alterado(a.spo2),
                        ),
                      if (a.heartRate != null)
                        _Vital(
                          'FC',
                          '${a.heartRate}',
                          alerta: AlertaVital.frequenciaAlterada(a.heartRate),
                        ),
                      if (a.temperatureC != null)
                        _Vital(
                          'T',
                          '${a.temperatureC!.toStringAsFixed(1)}°C',
                          alerta: AlertaVital.temperaturaAlterada(
                            a.temperatureC,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(a.procedimento),
                ),
                if (a.feridas != null && a.feridas!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Feridas: ${a.feridas}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                // As fotos. Antes nenhuma tela as mostrava: a câmera
                // gravava, a fila subia, o Storage guardava e ninguém
                // conseguia rever. Em registro de ferida isso é metade do
                // que o atendimento tem a dizer.
                FotosDoAtendimento(
                  atendimentoId: a.id,
                  caminhosLocais: fotosLocais,
                ),
                if (a.temLocalizacao) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.place, size: 14, color: Colors.green),
                      const SizedBox(width: 4),
                      Text(
                        'lat: ${a.latitude!.toStringAsFixed(6)}, '
                        'lng: ${a.longitude!.toStringAsFixed(6)}',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ],
                  ),
                ],
                if (aoEncerrar != null && !a.encerrado) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: aoEncerrar,
                      icon: const Icon(Icons.check_circle_outline, size: 18),
                      label: const Text('Encerrar'),
                    ),
                  ),
                ],
                if (a.encerrado && a.closedAt != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Encerrado em '
                    '${a.closedAt!.toLocal().day.toString().padLeft(2, "0")}/'
                    '${a.closedAt!.toLocal().month.toString().padLeft(2, "0")} '
                    'às '
                    '${a.closedAt!.toLocal().hour.toString().padLeft(2, "0")}:'
                    '${a.closedAt!.toLocal().minute.toString().padLeft(2, "0")}',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Vital extends StatelessWidget {
  const _Vital(this.rotulo, this.valor, {required this.alerta});

  final String rotulo;
  final String valor;
  final bool alerta;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: alerta ? scheme.errorContainer : scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (alerta)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(
                Icons.warning_amber_rounded,
                size: 14,
                color: scheme.onErrorContainer,
              ),
            ),
          Text(
            '$rotulo $valor',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: alerta
                  ? scheme.onErrorContainer
                  : scheme.onSecondaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
