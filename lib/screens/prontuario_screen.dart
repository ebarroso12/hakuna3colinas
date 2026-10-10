import 'package:flutter/material.dart';

import '../models/atendimento.dart';
import '../models/participant.dart';
import '../models/top.dart';
import '../services/atendimento_service.dart';
import '../services/supabase_service.dart';
import '../widgets/app_logo.dart';
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
    try {
      final lista = await SupabaseService.instance.fetchAtendimentos(
        topId: widget.top.id,
        participantId: widget.participante.id,
      );
      final pendentes = await AtendimentoService.instance.pendentesDeEnvio();
      if (!mounted) return;
      setState(() {
        _atendimentos = lista;
        _pendentes = pendentes;
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
                  'Já estão salvos no celular. Sobem sozinhos quando houver '
                  'internet.',
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
          if (_atendimentos.isEmpty && _erro == null)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'Nenhum atendimento registrado para este participante.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ..._atendimentos.map(
            (a) => _CartaoAtendimento(
              atendimento: a,
              participante: widget.participante,
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
  });

  final Atendimento atendimento;
  final Participant participante;

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
