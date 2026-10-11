import 'package:flutter/material.dart';

import '../models/afericao.dart';
import '../models/participant.dart';
import '../models/top.dart';
import '../models/triage_rule.dart';
import '../offline/dados_do_top.dart';
import '../services/triage_dinamica.dart';
import '../services/triage_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/barra_inferior.dart';
import '../widgets/botao_inicio.dart';
import 'admin/participante_form_screen.dart';
import 'prontuario_screen.dart';

/// FICHA DO PARTICIPANTE — tudo que o Hakuna precisa ver antes de atender.
///
/// A ordem segue a do app oficial de propósito: identificação, medidas com
/// IMC, e só então o clínico. Quem já usa o app antigo encontra as coisas
/// no mesmo lugar.
class ParticipantFileScreen extends StatelessWidget {
  const ParticipantFileScreen({
    super.key,
    required this.participante,
    required this.top,
    this.regras = const [],
    this.podeEditar = false,
  });

  final Participant participante;
  final Top top;
  final List<TriageRule> regras;

  /// Editar a ficha é de admin e coordenador. Esconder o botão é cortesia:
  /// quem barra de verdade é a RLS de `top_participants`.
  final bool podeEditar;

  @override
  Widget build(BuildContext context) {
    final corDeCadastro = TriageService.colorForParticipant(
      participante,
      regras,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ficha do participante'),
        actions: const [BotaoInicio(), AppLogoTrailing()],
      ),
      bottomNavigationBar: BarraInferior(
        aoEditar: podeEditar ? () => _editar(context) : null,
        rotuloEditar: 'Editar ficha',
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _Identificacao(participante: participante),
          const SizedBox(height: 12),
          _Medidas(participante: participante),
          const SizedBox(height: 12),
          // A cor vem do disco, não da rede: esta ficha é lida no mato,
          // depois de a pulseira identificar alguém. Enquanto a aferição
          // não chega, mostra a cor de cadastro em vez de um spinner —
          // informação incompleta é melhor que tela vazia na frente de um
          // paciente.
          FutureBuilder<Afericao?>(
            future: DadosDoTop.instance.afericaoDe(participante.id),
            builder: (context, snap) => _Clinico(
              participante: participante,
              gravidade: TriageDinamica.avaliar(
                corDeCadastro: corDeCadastro,
                afericao: snap.data,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _Emergencia(participante: participante),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _abrirProntuario(context),
            icon: const Icon(Icons.assignment_outlined),
            label: const Text('PRONTUÁRIO'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  void _editar(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            ParticipanteFormScreen(top: top, participante: participante),
      ),
    );
  }

  void _abrirProntuario(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProntuarioScreen(top: top, participante: participante),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _Cartao extends StatelessWidget {
  const _Cartao({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: children,
        ),
      ),
    );
  }
}

/// Rótulo em cima, valor embaixo — o mesmo formato da ficha oficial.
/// Campo vazio aparece como "–" em vez de sumir: no atendimento, saber que
/// a informação NÃO foi preenchida vale tanto quanto o valor.
class _Campo extends StatelessWidget {
  const _Campo(this.rotulo, this.valor, {this.destaque = false});

  final String rotulo;
  final String? valor;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    final preenchido = valor != null && valor!.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rotulo.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            preenchido ? valor! : '–',
            style: destaque
                ? Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)
                : Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontStyle: preenchido ? FontStyle.italic : FontStyle.normal,
                    color: preenchido ? null : Theme.of(context).disabledColor,
                  ),
          ),
        ],
      ),
    );
  }
}

class _Identificacao extends StatelessWidget {
  const _Identificacao({required this.participante});

  final Participant participante;

  @override
  Widget build(BuildContext context) {
    final p = participante;
    return _Cartao(
      children: [
        Text(
          p.fullName.toUpperCase(),
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        if (p.nickname != null && p.nickname!.isNotEmpty)
          Text(
            '"${p.nickname}"',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        const SizedBox(height: 12),
        _LinhaIcone(
          icone: Icons.cake_outlined,
          texto: p.idade != null ? '${p.idade} anos' : 'Idade não informada',
        ),
        _LinhaIcone(
          icone: Icons.place_outlined,
          texto: p.localidade ?? 'Localidade não informada',
        ),
        _LinhaIcone(
          icone: Icons.groups_outlined,
          texto: 'FAMÍLIA ${p.familia ?? "#–"}',
        ),
        if (p.participantCode != null && p.participantCode!.isNotEmpty)
          _LinhaIcone(
            icone: Icons.military_tech_outlined,
            texto: 'Legendário #${p.participantCode}',
          ),
      ],
    );
  }
}

class _LinhaIcone extends StatelessWidget {
  const _LinhaIcone({required this.icone, required this.texto});

  final IconData icone;
  final String texto;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icone, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(texto)),
        ],
      ),
    );
  }
}

class _Medidas extends StatelessWidget {
  const _Medidas({required this.participante});

  final Participant participante;

  @override
  Widget build(BuildContext context) {
    final p = participante;
    final imc = p.imc;
    return _Cartao(
      children: [
        Wrap(
          spacing: 20,
          runSpacing: 8,
          children: [
            _Medida(
              icone: Icons.monitor_weight_outlined,
              rotulo: 'PESO',
              valor: p.weightKg != null
                  ? '${p.weightKg!.toStringAsFixed(1)} Kg'
                  : '–',
            ),
            _Medida(
              icone: Icons.height,
              rotulo: 'ALTURA',
              valor: p.heightCm != null
                  ? '${p.heightCm!.toStringAsFixed(1)} Cm'
                  : '–',
            ),
            _Medida(
              icone: Icons.health_and_safety_outlined,
              rotulo: 'IMC',
              valor: imc != null ? imc.toStringAsFixed(1) : '–',
            ),
          ],
        ),
        if (imc != null) ...[
          const SizedBox(height: 16),
          const _BarraImc(),
          const SizedBox(height: 6),
          _PonteiroImc(faixa: p.faixaImc!),
        ],
      ],
    );
  }
}

class _Medida extends StatelessWidget {
  const _Medida({
    required this.icone,
    required this.rotulo,
    required this.valor,
  });

  final IconData icone;
  final String rotulo;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icone, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(rotulo, style: Theme.of(context).textTheme.labelSmall),
            Text(
              valor,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }
}

/// A faixa colorida do IMC, nas mesmas 6 divisões do app oficial.
class _BarraImc extends StatelessWidget {
  const _BarraImc();

  static const _cores = {
    FaixaImc.abaixo: Color(0xFF2196F3),
    FaixaImc.normal: Color(0xFF4CAF50),
    FaixaImc.sobrepeso: Color(0xFFFFC107),
    FaixaImc.obesidade1: Color(0xFFFF9800),
    FaixaImc.obesidade2: Color(0xFFF44336),
    FaixaImc.obesidade3: Color(0xFF9C27B0),
  };

  /// Larguras proporcionais, pra barra parecer a do app oficial (a faixa
  /// "abaixo" e a "obesidade 3" são as mais largas).
  static const _pesos = {
    FaixaImc.abaixo: 4,
    FaixaImc.normal: 2,
    FaixaImc.sobrepeso: 1,
    FaixaImc.obesidade1: 1,
    FaixaImc.obesidade2: 1,
    FaixaImc.obesidade3: 3,
  };

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 34,
        child: Row(
          children: [
            for (final faixa in FaixaImc.values)
              Expanded(
                flex: _pesos[faixa]!,
                child: Container(
                  color: _cores[faixa],
                  alignment: Alignment.center,
                  child: Text(
                    faixa.sigla,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PonteiroImc extends StatelessWidget {
  const _PonteiroImc({required this.faixa});

  final FaixaImc faixa;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          Icons.arrow_drop_up,
          size: 20,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        const SizedBox(width: 4),
        Text(
          faixa.label,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

/// Explica por que a cor não é a do cadastro.
///
/// Sem isto o Hakuna vê vermelho e não sabe se é por idade e comorbidade ou
/// por uma aferição de agora — e essas duas coisas pedem conduta diferente.
/// Mostra também a cor de base, para deixar claro que o cadastro não foi
/// apagado: ele volta a valer quando uma aferição normal chegar.
class _MotivoEscalada extends StatelessWidget {
  const _MotivoEscalada({required this.gravidade});

  final Gravidade gravidade;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = gravidade.corDeCadastro;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.monitor_heart, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'VERMELHO por sinal vital aferido',
                  style: TextStyle(
                    color: scheme.onErrorContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  gravidade.motivos.join(' · '),
                  style: TextStyle(color: scheme.onErrorContainer),
                ),
                if (base != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Triagem de cadastro: ${base.label}',
                    style: TextStyle(
                      color: scheme.onErrorContainer,
                      fontSize: 12,
                    ),
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

class _Clinico extends StatelessWidget {
  const _Clinico({required this.participante, required this.gravidade});

  final Participant participante;
  final Gravidade gravidade;

  @override
  Widget build(BuildContext context) {
    final p = participante;
    return _Cartao(
      children: [
        _Campo('Biotipo', p.biotipo),
        _Campo('Tipo sanguíneo', p.bloodType, destaque: true),
        _IndicativoSaude(cor: gravidade.cor),
        if (gravidade.escalada) _MotivoEscalada(gravidade: gravidade),
        _Campo('Cirurgias', p.cirurgias),
        _Campo('Observação Hakuna', p.observacaoHakuna),
        _Campo('Atividade física semanal', p.atividadeFisicaSemanal),
        const Divider(height: 24),
        _ListaMarcada(
          titulo: 'Comorbidades',
          itens: p.comorbidades,
          vazio: 'Nenhuma comorbidade registrada',
        ),
        // Alergia, plano e medicação ficam FORA de comorbidades: é a lista
        // de comorbidades que a triagem conta para decidir a cor, e incluir
        // plano de saúde ali inflaria a contagem.
        const SizedBox(height: 8),
        _Campo('Alergias', p.alergias),
        _Campo('Medicamentos de uso contínuo', p.medicamentosContinuos),
        _Campo('Restrições físicas', p.restricoesFisicas),
        _Campo('Plano de saúde', p.planoSaude),
      ],
    );
  }
}

class _IndicativoSaude extends StatelessWidget {
  const _IndicativoSaude({required this.cor});

  final TriageColor? cor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'INDICATIVO SAÚDE',
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: cor?.materialColor ?? Theme.of(context).disabledColor,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: Text(
              cor?.label.toUpperCase() ?? 'NÃO CLASSIFICADO',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ListaMarcada extends StatelessWidget {
  const _ListaMarcada({
    required this.titulo,
    required this.itens,
    required this.vazio,
  });

  final String titulo;
  final List<String> itens;
  final String vazio;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo.toUpperCase(),
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        if (itens.isEmpty)
          Text(
            vazio,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Theme.of(context).disabledColor),
          )
        else
          ...itens.map(
            (i) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(i)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Emergencia extends StatelessWidget {
  const _Emergencia({required this.participante});

  final Participant participante;

  @override
  Widget build(BuildContext context) {
    final contato = participante.emergencyContact;
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.emergency_share_outlined,
              color: Theme.of(context).colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CONTATO DE EMERGÊNCIA',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    contato != null && contato.trim().isNotEmpty
                        ? contato
                        : 'Não informado',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
