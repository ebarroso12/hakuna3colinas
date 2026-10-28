import 'package:flutter/material.dart';

import '../../models/painel_do_top.dart';
import '../../models/team.dart';
import '../../models/top.dart';
import '../../services/admin_service.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/botao_inicio.dart';

/// Painel do Top: as métricas que o admin acompanha durante o evento.
///
/// Pedido do dono em 28/10/2026: "o admin tem de ter o controle de tudo,
/// até métricas". Vem da função `painel_do_top` no banco, numa chamada só,
/// e só para admin — a recusa é do banco, não desta tela.
///
/// **Precisa de internet**, como Quem vê o mapa: contar o Top inteiro exige
/// o servidor, e um painel montado com o que está no aparelho mostraria
/// números velhos com cara de atuais. Sem rede, a tela diz isso.
///
/// O que pede ação vem pintado (fichas sem número, gente esperando
/// liberação, atendimento aberto, vital crítico). Número sem cor é só
/// informação.
class AdminPainelScreen extends StatefulWidget {
  const AdminPainelScreen({super.key, required this.top});

  final Top top;

  @override
  State<AdminPainelScreen> createState() => _AdminPainelScreenState();
}

class _AdminPainelScreenState extends State<AdminPainelScreen> {
  late Future<PainelDoTop> _painel;

  @override
  void initState() {
    super.initState();
    _painel = AdminService.instance.painelDoTop(widget.top.id);
  }

  Future<void> _recarregar() async {
    final f = AdminService.instance.painelDoTop(widget.top.id);
    setState(() => _painel = f);
    try {
      await f;
    } catch (_) {
      // O FutureBuilder mostra o erro; aqui só não deixa o
      // RefreshIndicator estourar.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Painel do Top'),
            Text(
              widget.top.topNumber != null
                  ? 'TOP# ${widget.top.topNumber} · ${widget.top.name}'
                  : widget.top.name,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          const BotaoInicio(),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar',
            onPressed: _recarregar,
          ),
          const AppLogoTrailing(),
        ],
      ),
      body: FutureBuilder<PainelDoTop>(
        future: _painel,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return _SemPainel(onTentar: _recarregar);
          }
          return RefreshIndicator(
            onRefresh: _recarregar,
            child: _Conteudo(p: snap.data!),
          );
        },
      ),
    );
  }
}

class _SemPainel extends StatelessWidget {
  const _SemPainel({required this.onTentar});

  final VoidCallback onTentar;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48),
            const SizedBox(height: 12),
            const Text(
              'O painel precisa de internet.',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Os números vêm do servidor, com o Top inteiro. Com o que está '
              'só neste aparelho eles sairiam incompletos.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onTentar,
              child: const Text('Tentar de novo'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Conteudo extends StatelessWidget {
  const _Conteudo({required this.p});

  final PainelDoTop p;

  String _hora(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  String _quando(DateTime d) {
    final hoje = DateTime.now();
    final mesmoDia =
        d.year == hoje.year && d.month == hoje.month && d.day == hoje.day;
    return mesmoDia
        ? 'hoje às ${_hora(d)}'
        : '${d.day.toString().padLeft(2, '0')}/'
              '${d.month.toString().padLeft(2, '0')} às ${_hora(d)}';
  }

  @override
  Widget build(BuildContext context) {
    final esperando = p.contasAguardando + p.pedidosPendentes;
    final porChave = {for (final e in p.equipes) e.equipe: e};

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      children: [
        Text(
          'Atualizado ${_quando(p.geradoEm)} · puxe para atualizar',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 8),

        _Secao(
          titulo: 'Agora no campo',
          numeros: [
            _Numero(
              'Compartilhando posição',
              p.compartilhandoPosicaoAgora,
              legenda: '${p.comPosicaoNaUltimaHora} na última hora',
            ),
            _Numero(
              'Atendimentos abertos',
              p.atendimentosAbertos,
              alerta: p.atendimentosAbertos > 0,
            ),
            _Numero(
              'Pessoas com vital crítico',
              p.pessoasComVitalCritico,
              alerta: p.pessoasComVitalCritico > 0,
              legenda: 'SpO₂ < 90 ou PA > 180 × 110',
            ),
            _Numero(
              'Alarmes nas últimas 24 h',
              p.alarmes24h,
              alerta: p.alarmes24h > 0,
              legenda: p.ultimoAlarmeEm == null
                  ? 'nenhum alarme no Top'
                  : 'último: ${p.ultimoAlarmeNome ?? "Alguém do Top"}, '
                        '${_quando(p.ultimoAlarmeEm!)}',
            ),
          ],
        ),

        _Secao(
          titulo: 'Cadastro',
          numeros: [
            _Numero('Fichas no Top', p.fichas),
            _Numero(
              'Já com conta no app',
              p.fichasComConta,
              legenda:
                  '${(p.adesao * 100).round()}% das fichas · '
                  '${p.fichasSemConta} sem conta',
            ),
            _Numero(
              'Fichas sem número',
              p.fichasSemNumero,
              alerta: p.fichasSemNumero > 0,
              legenda: 'não conseguem fazer o Primeiro acesso',
            ),
            _Numero(
              'Fichas sem nascimento',
              p.fichasSemNascimento,
              alerta: p.fichasSemNascimento > 0,
              legenda: 'ficam sem cor de triagem',
            ),
            _Numero(
              'Esperando liberação',
              esperando,
              alerta: esperando > 0,
              legenda:
                  '${p.pedidosPendentes} pedido(s) · '
                  '${p.contasAguardando} conta(s) sem aprovação',
            ),
            if (p.fichasTeste > 0) _Numero('Cadastros de teste', p.fichasTeste),
          ],
        ),

        _Secao(
          titulo: 'Saúde',
          numeros: [
            _Numero('Hakunas liberados', p.hakunasLiberados),
            _Numero('Atendimentos no Top', p.atendimentos),
            _Numero('Atendimentos nas últimas 24 h', p.atendimentos24h),
            _Numero('Aferições de sinais vitais', p.afericoes),
          ],
        ),

        _Secao(
          titulo: 'Comunicação',
          numeros: [
            _Numero('Mensagens das equipes (24 h)', p.mensagens24h),
            _Numero('Mensagens das equipes (total)', p.mensagensTotal),
            _Numero('Chat dos Hakunas (24 h)', p.chatClinico24h),
            _Numero('Alarmes no Top (total)', p.alarmes),
          ],
        ),

        const SizedBox(height: 8),
        Text('Equipes', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        // As 9 sempre, inclusive as vazias: equipe que não aparece parece
        // equipe que não existe, e "ninguém em Segurança" é justamente o
        // que o admin precisa ver.
        for (final t in TeamKeyUi.equipes)
          _LinhaDeEquipe(equipe: t, dados: porChave[t]),
      ],
    );
  }
}

class _Numero {
  const _Numero(this.rotulo, this.valor, {this.legenda, this.alerta = false});

  final String rotulo;
  final int valor;
  final String? legenda;
  final bool alerta;
}

class _Secao extends StatelessWidget {
  const _Secao({required this.titulo, required this.numeros});

  final String titulo;
  final List<_Numero> numeros;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(titulo, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (context, c) {
              // Duas colunas no celular; uma só em tela muito estreita.
              final colunas = c.maxWidth < 300 ? 1 : 2;
              final largura = (c.maxWidth - (colunas - 1) * 8) / colunas;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final n in numeros)
                    SizedBox(
                      width: largura,
                      child: _Cartao(n: n),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Cartao extends StatelessWidget {
  const _Cartao({required this.n});

  final _Numero n;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final texto = Theme.of(context).textTheme;
    return Card(
      margin: EdgeInsets.zero,
      color: n.alerta ? cores.errorContainer : null,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${n.valor}',
              style: texto.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: n.alerta ? cores.onErrorContainer : null,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              n.rotulo,
              style: texto.bodyMedium?.copyWith(
                color: n.alerta ? cores.onErrorContainer : null,
              ),
            ),
            if (n.legenda != null) ...[
              const SizedBox(height: 2),
              Text(
                n.legenda!,
                style: texto.bodySmall?.copyWith(
                  color: n.alerta ? cores.onErrorContainer : null,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LinhaDeEquipe extends StatelessWidget {
  const _LinhaDeEquipe({required this.equipe, required this.dados});

  final TeamKey equipe;
  final EquipeNoPainel? dados;

  @override
  Widget build(BuildContext context) {
    final d = dados;
    final cores = Theme.of(context).colorScheme;
    final String detalhe;
    var alerta = false;
    if (d == null || d.membros == 0) {
      detalhe = 'Ninguém na equipe';
      alerta = true;
    } else {
      final partes = [
        '${d.membros} integrante(s)',
        if (d.faltaLiberar > 0) '${d.faltaLiberar} falta liberar',
        d.coordenacao == 0
            ? 'sem coordenação'
            : '${d.coordenacao} na coordenação',
        '${d.mensagens24h} msg em 24 h',
      ];
      detalhe = partes.join(' · ');
      alerta = d.faltaLiberar > 0 || d.coordenacao == 0;
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(equipe.icon),
      title: Text(equipe.label),
      subtitle: Text(
        detalhe,
        style: alerta ? TextStyle(color: cores.error) : null,
      ),
    );
  }
}
