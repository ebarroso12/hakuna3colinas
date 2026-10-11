import 'package:flutter/material.dart';

import '../../models/profile.dart';
import '../../models/team.dart';
import '../../models/team_message.dart';
import '../../models/top.dart';
import '../../services/admin_service.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/botao_inicio.dart';

/// Quem vê a posição dos outros neste Top.
///
/// A regra **automática** vive em `pode_ver_mapa()` no banco: admin,
/// Hakuna liberado, coordenação/subcoordenação de qualquer equipe, e
/// membros das equipes `seguranca` e `hakunas`.
///
/// Esta tela não substitui a regra — ela **sobrepõe, pessoa por pessoa**,
/// e nos dois sentidos. É a diferença entre "conceder" e "editar":
///
/// - **Pelo cargo**: segue a regra automática.
/// - **Liberado**: vê o mapa mesmo que o cargo não desse direito.
/// - **Bloqueado**: NÃO vê, mesmo sendo coordenador.
///
/// Sem o terceiro estado, tirar o mapa de um coordenador exigiria
/// rebaixá-lo de cargo — o que mexe no trabalho dele para resolver um
/// problema de privacidade.
///
/// Por que a posição é mais restrita que o alarme: alarme é emergência
/// (todos disparam e recebem), posição é vigilância contínua. 200 pessoas
/// vendo a localização de todas as outras não é necessário para mídia,
/// produção ou intercessão trabalharem.
class AdminMapaPermissoesScreen extends StatefulWidget {
  const AdminMapaPermissoesScreen({super.key, required this.top});

  final Top top;

  @override
  State<AdminMapaPermissoesScreen> createState() =>
      _AdminMapaPermissoesScreenState();
}

/// O que o admin escolheu para uma pessoa.
enum _Decisao { peloCargo, liberado, bloqueado }

class _AdminMapaPermissoesScreenState extends State<AdminMapaPermissoesScreen> {
  List<Profile> _pessoas = [];
  List<TeamMembership> _vinculos = [];
  Map<String, bool> _excecoes = {};
  Set<String> _hakunasLiberados = {};

  bool _carregando = true;
  String? _erro;
  final Set<String> _salvando = {};
  String _busca = '';

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
      final pessoas = await AdminService.instance.fetchAllProfiles();
      final vinculos = await AdminService.instance.fetchTeamMembers(
        widget.top.id,
      );
      final excecoes = await AdminService.instance.excecoesDeMapa(
        widget.top.id,
      );
      final hakunas = await AdminService.instance.fetchTopHakunaAssignments(
        widget.top.id,
      );
      if (!mounted) return;
      setState(() {
        _pessoas = pessoas;
        _vinculos = vinculos;
        _excecoes = excecoes;
        _hakunasLiberados = {
          for (final e in hakunas.entries)
            if (e.value) e.key,
        };
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

  /// O que a REGRA AUTOMÁTICA diz para esta pessoa.
  ///
  /// Espelha `pode_ver_mapa()` no banco de propósito, para a tela poder
  /// explicar o porquê. **A decisão real é a do banco** — isto é só o
  /// texto que aparece ao lado do nome. Se divergirem, o banco manda; e
  /// se a regra mudar lá, este método tem de mudar junto.
  ({bool ve, String motivo}) _pelaRegra(Profile p) {
    if (p.role == UserRole.admin || p.isMasterAdmin) {
      return (ve: true, motivo: 'admin');
    }
    if (_hakunasLiberados.contains(p.id)) {
      return (ve: true, motivo: 'Hakuna liberado');
    }
    final meus = _vinculos.where((v) => v.profileId == p.id && v.released);
    for (final v in meus) {
      if (v.blocked) continue;
      if (v.teamRole == TeamRole.coordenador ||
          v.teamRole == TeamRole.subcoordenador) {
        return (ve: true, motivo: '${v.teamRole.label} de ${v.team.label}');
      }
      if (v.team == TeamKey.seguranca || v.team == TeamKey.hakunas) {
        return (ve: true, motivo: 'equipe ${v.team.label}');
      }
    }
    if (meus.isEmpty) {
      return (ve: false, motivo: 'sem equipe liberada neste Top');
    }
    return (ve: false, motivo: 'membro, sem cargo que dê direito');
  }

  _Decisao _decisaoDe(String profileId) {
    final e = _excecoes[profileId];
    if (e == null) return _Decisao.peloCargo;
    return e ? _Decisao.liberado : _Decisao.bloqueado;
  }

  Future<void> _definir(Profile p, _Decisao d) async {
    setState(() => _salvando.add(p.id));
    try {
      if (d == _Decisao.peloCargo) {
        await AdminService.instance.removerExcecaoDeMapa(
          topId: widget.top.id,
          profileId: p.id,
        );
        if (mounted) setState(() => _excecoes.remove(p.id));
      } else {
        final ve = d == _Decisao.liberado;
        await AdminService.instance.definirExcecaoDeMapa(
          topId: widget.top.id,
          profileId: p.id,
          verMapa: ve,
        );
        if (mounted) setState(() => _excecoes[p.id] = ve);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível salvar: $e')),
      );
    } finally {
      if (mounted) setState(() => _salvando.remove(p.id));
    }
  }

  List<Profile> get _filtradas {
    final termo = _busca.trim().toLowerCase();
    if (termo.isEmpty) return _pessoas;
    return _pessoas
        .where(
          (p) =>
              p.fullName.toLowerCase().contains(termo) ||
              p.legendariosNumber.contains(termo),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Quem vê o mapa'),
            Text(
              widget.top.name,
              style: Theme.of(context).textTheme.labelSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
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
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.all(12),
            child: Text(
              'Por padrão vê o mapa: admin, Hakuna liberado, '
              'coordenação e subcoordenação de qualquer equipe, e as '
              'equipes Segurança e Hakunas.\n\n'
              'Aqui você muda caso a caso — inclusive para BLOQUEAR quem '
              'teria direito pelo cargo.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              decoration: const InputDecoration(
                labelText: 'Buscar por nome ou número',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _busca = v),
            ),
          ),
          Expanded(child: _corpo()),
        ],
      ),
    );
  }

  Widget _corpo() {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_erro != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, size: 36),
            const SizedBox(height: 12),
            const Text(
              'Esta tela precisa de internet.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '$_erro',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _carregar,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar de novo'),
            ),
          ],
        ),
      );
    }

    final lista = _filtradas;
    if (lista.isEmpty) {
      return const Center(child: Text('Ninguém encontrado com essa busca.'));
    }

    return ListView.builder(
      itemCount: lista.length,
      itemBuilder: (context, i) {
        final p = lista[i];
        final regra = _pelaRegra(p);
        final decisao = _decisaoDe(p.id);
        final salvando = _salvando.contains(p.id);

        // O que vale de fato, somando regra e exceção. É o que a pessoa
        // vai experimentar no app.
        final veDeFato = switch (decisao) {
          _Decisao.liberado => true,
          _Decisao.bloqueado => false,
          _Decisao.peloCargo => regra.ve,
        };

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      veDeFato ? Icons.visibility : Icons.visibility_off,
                      size: 18,
                      color: veDeFato
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        p.displayLabel,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (salvando)
                      const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Pelo cargo: ${regra.ve ? "vê" : "não vê"} — ${regra.motivo}',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 8),
                SegmentedButton<_Decisao>(
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(
                      value: _Decisao.peloCargo,
                      label: Text('Pelo cargo'),
                    ),
                    ButtonSegment(
                      value: _Decisao.liberado,
                      label: Text('Liberado'),
                    ),
                    ButtonSegment(
                      value: _Decisao.bloqueado,
                      label: Text('Bloqueado'),
                    ),
                  ],
                  selected: {decisao},
                  onSelectionChanged: salvando
                      ? null
                      : (s) => _definir(p, s.first),
                ),
                // O admin nunca perde o mapa, nem se marcado como
                // bloqueado: `pode_ver_mapa()` devolve true para ele antes
                // de olhar a exceção. Sem isso ele poderia se trancar sem
                // volta pelo app. A tela diz, em vez de deixar a pessoa
                // marcar e não entender por que nada muda.
                if ((p.role == UserRole.admin || p.isMasterAdmin) &&
                    decisao == _Decisao.bloqueado)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Admin continua vendo o mapa de qualquer forma — é a '
                      'trava que impede o admin de se trancar fora.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
