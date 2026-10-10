import 'package:flutter/material.dart';

import '../models/participant.dart';
import '../models/profile.dart';
import '../models/top.dart';
import '../models/triage_rule.dart';
import '../services/supabase_service.dart';
import '../services/triage_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/barra_inferior.dart';
import '../widgets/cabecalho_usuario.dart';
import '../widgets/emblemas.dart';
import 'admin/participante_form_screen.dart';
import 'ler_tag_screen.dart';
import 'participant_file_screen.dart';

/// Lista de participantes do Top, com as duas buscas do app oficial:
/// uma por nome e outra por família.
///
/// Carrega tudo de uma vez e filtra na memória de propósito. A lista é
/// usada no mato, sem sinal — uma busca que depende de rede falharia
/// justamente onde o app precisa funcionar. 215 registros filtram
/// instantaneamente.
class ParticipantsListScreen extends StatefulWidget {
  const ParticipantsListScreen({super.key, required this.top});

  final Top top;

  @override
  State<ParticipantsListScreen> createState() => _ParticipantsListScreenState();
}

class _ParticipantsListScreenState extends State<ParticipantsListScreen> {
  final _buscaNome = TextEditingController();
  final _buscaFamilia = TextEditingController();

  List<Participant> _todos = [];
  List<TriageRule> _regras = [];
  Profile? _meuPerfil;
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
    _buscaNome.addListener(() => setState(() {}));
    _buscaFamilia.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _buscaNome.dispose();
    _buscaFamilia.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final participantes = await SupabaseService.instance.fetchParticipants(
        widget.top.id,
      );
      // O cabecalho mostra quem esta logado naquele aparelho — falhar aqui
      // nao impede a lista de aparecer.
      try {
        _meuPerfil = await SupabaseService.instance.fetchMyProfile();
      } catch (_) {}
      // As regras de triagem vêm junto pra pintar a cor de cada linha sem
      // uma consulta por participante.
      List<TriageRule> regras = const [];
      try {
        regras = await SupabaseService.instance.fetchActiveTriageRules();
      } catch (_) {
        // Sem regras a lista ainda funciona, só não mostra cor.
      }
      if (!mounted) return;
      setState(() {
        _todos = participantes;
        _regras = regras;
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

  /// Os dois filtros se somam: digitar nos dois campos restringe aos dois
  /// critérios ao mesmo tempo.
  List<Participant> get _filtrados {
    final nome = _buscaNome.text.trim().toLowerCase();
    final familia = _buscaFamilia.text.trim().toLowerCase();
    return _todos.where((p) {
      final casaNome =
          nome.isEmpty ||
          p.fullName.toLowerCase().contains(nome) ||
          (p.nickname?.toLowerCase().contains(nome) ?? false) ||
          (p.participantCode?.toLowerCase().contains(nome) ?? false);
      final casaFamilia =
          familia.isEmpty ||
          (p.familia?.toLowerCase().contains(familia) ?? false);
      return casaNome && casaFamilia;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final lista = _filtrados;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: CabecalhoUsuario(
          perfil: _meuPerfil,
          numeroTop: widget.top.topNumber,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recarregar',
            onPressed: _carregando ? null : _carregar,
          ),
          const AppLogoTrailing(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final criou = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (_) => ParticipanteFormScreen(top: widget.top),
            ),
          );
          if (criou ?? false) await _carregar();
        },
        icon: const Icon(Icons.person_add),
        label: const Text('Novo'),
      ),
      bottomNavigationBar: BarraInferior(
        // LER TAG fica na barra, como no app oficial: e a acao mais usada
        // em campo e precisa estar a um toque de qualquer lugar da lista.
        acaoExtra: _BotaoLerTag(top: widget.top, regras: _regras),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _buscaNome,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Participantes',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: _buscaNome.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: _buscaNome.clear,
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _buscaFamilia,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Família',
                      prefixIcon: const Icon(Icons.groups_outlined),
                      isDense: true,
                      border: const OutlineInputBorder(),
                      suffixIcon: _buscaFamilia.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: _buscaFamilia.clear,
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _corpo(lista)),
          _rodapeContagem(lista.length),
        ],
      ),
    );
  }

  Widget _corpo(List<Participant> lista) {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erro != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 40),
              const SizedBox(height: 12),
              Text(
                'Não foi possível carregar os participantes.\n$_erro',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _carregar,
                child: const Text('Tentar de novo'),
              ),
            ],
          ),
        ),
      );
    }
    if (_todos.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Nenhum participante cadastrado neste Top ainda.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    if (lista.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Nenhum participante encontrado com esses filtros.'),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      itemCount: lista.length,
      itemBuilder: (context, i) => _LinhaParticipante(
        participante: lista[i],
        regras: _regras,
        top: widget.top,
      ),
    );
  }

  Widget _rodapeContagem(int visiveis) {
    final total = _todos.length;
    final filtrando = visiveis != total;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            filtrando
                ? '$visiveis de $total registros'
                : '$total ${total == 1 ? "registro" : "registros"}',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
      ),
    );
  }
}

class _LinhaParticipante extends StatelessWidget {
  const _LinhaParticipante({
    required this.participante,
    required this.regras,
    required this.top,
  });

  final Participant participante;
  final List<TriageRule> regras;
  final Top top;

  @override
  Widget build(BuildContext context) {
    // Legendário é quem tem número — e quem tem número usa o app. O
    // Senderista existe como registro e não entra.
    final ehLegendario =
        participante.participantCode != null &&
        participante.participantCode!.trim().isNotEmpty;

    final cor = TriageService.colorForParticipant(participante, regras);

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        leading: emblemaPara(ehLegendario: ehLegendario),
        title: Text(
          participante.fullName.toUpperCase(),
          style: const TextStyle(fontWeight: FontWeight.w600),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: _subtitulo(context, ehLegendario),
        trailing: cor == null
            ? const Icon(Icons.chevron_right)
            : Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cor.materialColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Tooltip(
                  message: 'Triagem: ${cor.label}',
                  child: const Icon(Icons.flag, color: Colors.white, size: 20),
                ),
              ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ParticipantFileScreen(
              participante: participante,
              top: top,
              regras: regras,
            ),
          ),
        ),
      ),
    );
  }

  Widget? _subtitulo(BuildContext context, bool ehLegendario) {
    final partes = <String>[
      if (participante.familia != null && participante.familia!.isNotEmpty)
        'Família ${participante.familia}',
      if (ehLegendario) '#${participante.participantCode}',
      if (participante.idade != null) '${participante.idade} anos',
    ];
    if (partes.isEmpty) return null;
    return Text(
      partes.join(' · '),
      style: Theme.of(context).textTheme.labelSmall,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Botão LER TAG da barra inferior.
class _BotaoLerTag extends StatelessWidget {
  const _BotaoLerTag({required this.top, required this.regras});

  final Top top;
  final List<TriageRule> regras;

  @override
  Widget build(BuildContext context) {
    final cor = Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => LerTagScreen(top: top, regras: regras),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.nfc, size: 22, color: cor),
          const SizedBox(height: 2),
          Text(
            'Ler tag',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cor),
          ),
        ],
      ),
    );
  }
}
