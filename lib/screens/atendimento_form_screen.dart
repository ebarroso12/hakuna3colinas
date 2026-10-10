import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../models/afericao.dart';
import '../models/atendimento.dart';
import '../models/participant.dart';
import '../models/top.dart';
import '../offline/outbox.dart';
import '../services/atendimento_service.dart';
import '../services/supabase_service.dart';
import '../services/triage_dinamica.dart';

/// REGISTRO DE ATENDIMENTO.
///
/// Os sinais vitais são campos fixos de propósito: o Hakuna chega, afere,
/// digita o número e segue. Antes isso ia solto dentro do texto
/// ("AFERIDO PA 150X90"), o que impede qualquer leitura posterior — não dá
/// para comparar duas aferições nem ver evolução quando o dado está no
/// meio de uma frase.
///
/// Funciona sem internet: o registro entra na fila local e sobe quando o
/// sinal volta.
class AtendimentoFormScreen extends StatefulWidget {
  const AtendimentoFormScreen({
    super.key,
    required this.top,
    required this.participante,
    this.numeroSugerido,
  });

  final Top top;
  final Participant participante;
  final int? numeroSugerido;

  @override
  State<AtendimentoFormScreen> createState() => _AtendimentoFormScreenState();
}

class _AtendimentoFormScreenState extends State<AtendimentoFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _procedimento = TextEditingController();
  final _sistolica = TextEditingController();
  final _diastolica = TextEditingController();
  final _glicemia = TextEditingController();
  final _spo2 = TextEditingController();
  final _fc = TextEditingController();
  final _temperatura = TextEditingController();
  final _feridas = TextEditingController();

  /// Gerado já na abertura da tela: as fotos tiradas antes de gravar
  /// precisam de um nome ligado a este atendimento.
  final _clientId = Outbox.novoClientId();

  final List<String> _fotos = [];
  Position? _posicao;
  String? _erroPosicao;
  bool _salvando = false;

  @override
  void initState() {
    super.initState();
    _capturarPosicao();
  }

  @override
  void dispose() {
    for (final c in [
      _procedimento,
      _sistolica,
      _diastolica,
      _glicemia,
      _spo2,
      _fc,
      _temperatura,
      _feridas,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Pega a posição assim que a tela abre. Falhar aqui não impede o
  /// registro: atender é mais importante que saber onde.
  Future<void> _capturarPosicao() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      if (mounted) setState(() => _posicao = pos);
    } catch (e) {
      if (mounted) setState(() => _erroPosicao = '$e');
    }
  }

  Future<void> _adicionarFoto() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Foto só no celular — no navegador não há câmera.'),
        ),
      );
      return;
    }
    final origem = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Adicionar foto',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Câmera'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Galeria'),
              onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (origem == null) return;

    try {
      final arquivo = await ImagePicker().pickImage(
        source: origem,
        // Reduz antes de guardar: a foto vai subir por rede de trilha, e
        // 8 MP não acrescentam nada clinicamente sobre uma ferida.
        maxWidth: 1600,
        imageQuality: 80,
      );
      if (arquivo == null) return;
      final destino = await AtendimentoService.instance.guardarFoto(
        arquivo.path,
        clientId: '$_clientId-${_fotos.length + 1}',
      );
      if (mounted) setState(() => _fotos.add(destino));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível usar a foto: $e')),
      );
    }
  }

  /// Avisa, **durante a digitação**, que os valores vão marcar o
  /// participante como vermelho na lista.
  ///
  /// Aparece antes de salvar de propósito: se o Hakuna errou um dígito
  /// (190 em vez de 130), ele corrige agora. O atendimento é append-only —
  /// depois de salvo não tem edição, só um registro novo.
  Widget _avisoCritico() {
    final gravidade = TriageDinamica.avaliar(
      corDeCadastro: null,
      afericao: Afericao(
        medidoEm: DateTime.now(),
        systolicBp: _inteiro(_sistolica),
        diastolicBp: _inteiro(_diastolica),
        spo2: _inteiro(_spo2),
      ),
    );
    if (!gravidade.escalada) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.monitor_heart, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Valor crítico: ${gravidade.motivos.join(" · ")}. '
              'Ao salvar, este participante passa a VERMELHO na lista.',
              style: TextStyle(
                color: scheme.onErrorContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  int? _inteiro(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : int.tryParse(t);
  }

  double? _decimal(TextEditingController c) {
    final t = c.text.trim().replaceAll(',', '.');
    return t.isEmpty ? null : double.tryParse(t);
  }

  Future<void> _gravar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final uid = SupabaseService.instance.currentUser?.id;
    if (uid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sessão expirada. Entre de novo.')),
      );
      return;
    }

    setState(() => _salvando = true);
    try {
      final atendimento = Atendimento(
        clientId: _clientId,
        topId: widget.top.id,
        participantId: widget.participante.id,
        openedBy: uid,
        numeroRegistro: widget.numeroSugerido,
        procedimento: _procedimento.text.trim(),
        systolicBp: _inteiro(_sistolica),
        diastolicBp: _inteiro(_diastolica),
        glicemiaMgDl: _inteiro(_glicemia),
        spo2: _inteiro(_spo2),
        heartRate: _inteiro(_fc),
        temperatureC: _decimal(_temperatura),
        feridas: _feridas.text.trim().isEmpty ? null : _feridas.text.trim(),
        latitude: _posicao?.latitude,
        longitude: _posicao?.longitude,
        openedAt: DateTime.now(),
        fotosLocais: _fotos,
      );

      await AtendimentoService.instance.registrar(atendimento);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Atendimento gravado. Sobe sozinho quando houver sinal.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _salvando = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Não foi possível gravar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registro de atendimento'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: FilledButton(
              onPressed: _salvando ? null : _gravar,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green.shade700,
              ),
              child: _salvando
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Gravar'),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _CabecalhoPaciente(participante: widget.participante),
            const SizedBox(height: 12),
            _LinhaPosicao(posicao: _posicao, erro: _erroPosicao),
            const Divider(height: 28),

            Text(
              'SINAIS VITAIS',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Afira e digite. Deixe em branco o que não mediu.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _avisoCritico(),

            Row(
              children: [
                Expanded(
                  child: _CampoVital(
                    controller: _sistolica,
                    rotulo: 'PA sistólica',
                    sufixo: 'mmHg',
                    alerta: AlertaVital.pressaoAlterada(
                      _inteiro(_sistolica),
                      _inteiro(_diastolica),
                    ),
                    aoMudar: () => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CampoVital(
                    controller: _diastolica,
                    rotulo: 'PA diastólica',
                    sufixo: 'mmHg',
                    alerta: AlertaVital.pressaoAlterada(
                      _inteiro(_sistolica),
                      _inteiro(_diastolica),
                    ),
                    aoMudar: () => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _CampoVital(
                    controller: _glicemia,
                    rotulo: 'DX (glicemia)',
                    sufixo: 'mg/dL',
                    alerta: AlertaVital.glicemiaAlterada(_inteiro(_glicemia)),
                    aoMudar: () => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CampoVital(
                    controller: _spo2,
                    rotulo: 'SpO₂',
                    sufixo: '%',
                    alerta: AlertaVital.spo2Alterado(_inteiro(_spo2)),
                    aoMudar: () => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _CampoVital(
                    controller: _fc,
                    rotulo: 'FC',
                    sufixo: 'bpm',
                    alerta: AlertaVital.frequenciaAlterada(_inteiro(_fc)),
                    aoMudar: () => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CampoVital(
                    controller: _temperatura,
                    rotulo: 'Temperatura',
                    sufixo: '°C',
                    decimal: true,
                    alerta: AlertaVital.temperaturaAlterada(
                      _decimal(_temperatura),
                    ),
                    aoMudar: () => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _feridas,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Feridas / lesões',
                hintText: 'Local, aspecto, tamanho',
                border: OutlineInputBorder(),
              ),
            ),

            const Divider(height: 28),
            Text(
              'PROCEDIMENTO',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _procedimento,
              minLines: 6,
              maxLines: 14,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'O que foi observado e o que foi feito',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Campo obrigatório!' : null,
            ),

            const SizedBox(height: 16),
            _Fotos(
              caminhos: _fotos,
              aoAdicionar: _adicionarFoto,
              aoRemover: (c) => setState(() => _fotos.remove(c)),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _CabecalhoPaciente extends StatelessWidget {
  const _CabecalhoPaciente({required this.participante});

  final Participant participante;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.person_outline),
        title: Text(
          participante.fullName.toUpperCase(),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          [
            if (participante.idade != null) '${participante.idade} anos',
            if (participante.familia != null) 'Família ${participante.familia}',
            if (participante.bloodType != null) participante.bloodType!,
          ].join(' · '),
        ),
      ),
    );
  }
}

class _LinhaPosicao extends StatelessWidget {
  const _LinhaPosicao({required this.posicao, required this.erro});

  final Position? posicao;
  final String? erro;

  @override
  Widget build(BuildContext context) {
    if (posicao != null) {
      return Row(
        children: [
          const Icon(Icons.place, color: Colors.green, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'LatLng(lat: ${posicao!.latitude.toStringAsFixed(6)}, '
              'lng: ${posicao!.longitude.toStringAsFixed(6)})',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        Icon(
          erro == null ? Icons.location_searching : Icons.location_disabled,
          size: 20,
          color: erro == null ? null : Theme.of(context).colorScheme.error,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            erro == null
                ? 'Obtendo posição…'
                : 'Sem posição — o atendimento grava assim mesmo.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

class _CampoVital extends StatelessWidget {
  const _CampoVital({
    required this.controller,
    required this.rotulo,
    required this.sufixo,
    required this.alerta,
    required this.aoMudar,
    this.decimal = false,
  });

  final TextEditingController controller;
  final String rotulo;
  final String sufixo;
  final bool alerta;
  final VoidCallback aoMudar;
  final bool decimal;

  @override
  Widget build(BuildContext context) {
    final cor = Theme.of(context).colorScheme.error;
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [
        FilteringTextInputFormatter.allow(
          decimal ? RegExp(r'[0-9.,]') : RegExp(r'[0-9]'),
        ),
      ],
      onChanged: (_) => aoMudar(),
      decoration: InputDecoration(
        labelText: rotulo,
        suffixText: sufixo,
        isDense: true,
        border: const OutlineInputBorder(),
        // Destaque visual, não bloqueio: o valor fora de faixa merece um
        // segundo olhar, mas quem decide conduta é o Hakuna.
        enabledBorder: alerta
            ? OutlineInputBorder(borderSide: BorderSide(color: cor, width: 2))
            : null,
        labelStyle: alerta ? TextStyle(color: cor) : null,
        suffixIcon: alerta
            ? Icon(Icons.warning_amber_rounded, color: cor, size: 18)
            : null,
      ),
    );
  }
}

class _Fotos extends StatelessWidget {
  const _Fotos({
    required this.caminhos,
    required this.aoAdicionar,
    required this.aoRemover,
  });

  final List<String> caminhos;
  final VoidCallback aoAdicionar;
  final void Function(String) aoRemover;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (caminhos.isNotEmpty) ...[
          SizedBox(
            height: 110,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: caminhos.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) => Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: kIsWeb
                        ? const SizedBox(width: 110, height: 110)
                        : Image.file(
                            File(caminhos[i]),
                            width: 110,
                            height: 110,
                            fit: BoxFit.cover,
                          ),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: IconButton(
                      icon: const CircleAvatar(
                        radius: 12,
                        backgroundColor: Colors.black54,
                        child: Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                      onPressed: () => aoRemover(caminhos[i]),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],
        Center(
          child: OutlinedButton.icon(
            onPressed: aoAdicionar,
            icon: const Icon(Icons.photo_camera_outlined),
            label: Text(caminhos.isEmpty ? 'Foto' : 'Adicionar outra foto'),
          ),
        ),
        if (caminhos.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '${caminhos.length} foto(s) guardada(s) no celular. '
              'Sobem junto com o atendimento quando houver sinal.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
