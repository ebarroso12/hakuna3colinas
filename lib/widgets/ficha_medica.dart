import 'package:flutter/material.dart';

import '../models/participant.dart';

/// Peças comuns aos dois formulários de ficha médica: o do admin
/// (`ParticipanteFormScreen`) e o do autocadastro
/// (`CadastroLegendarioScreen`).
///
/// **Por que existe:** a ficha tem quase vinte campos clínicos. Mantê-la
/// escrita duas vezes significaria que acrescentar "alergia a dipirona"
/// num lugar e esquecer no outro passa despercebido — e o campo some da
/// ficha de metade das pessoas sem ninguém notar.
///
/// Aqui ficam as listas de partida e os widgets pequenos. Os formulários
/// montam o layout próprio, porque as duas telas têm públicos diferentes:
/// o admin preenche ficha de terceiro e vê campos de controle; o
/// Legendário preenche a própria e cria senha.

/// Lista de partida de comorbidades.
///
/// O campo livre continua existindo: doença que não está aqui não pode
/// ficar de fora da ficha.
const comorbidadesComuns = [
  'hipertensão',
  'diabetes',
  'asma',
  'cardiopatia',
  'obesidade',
  'epilepsia',
  'doença renal',
  'problema de coluna',
];

const tiposSanguineos = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];

/// Título de seção do formulário.
class SecaoFicha extends StatelessWidget {
  const SecaoFicha(this.titulo, {super.key});

  final String titulo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Text(
        titulo.toUpperCase(),
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

/// Mostra o IMC enquanto se digita altura e peso — evita descobrir só
/// depois de salvar que faltou um dos dois.
class PreviaImc extends StatelessWidget {
  const PreviaImc({super.key, required this.altura, required this.peso});

  final double? altura;
  final double? peso;

  @override
  Widget build(BuildContext context) {
    if (altura == null || peso == null || altura! <= 0) {
      return const SizedBox.shrink();
    }
    final metros = altura! / 100;
    final imc = peso! / (metros * metros);
    // Reaproveita a classificação do model em vez de repetir as faixas:
    // é a mesma conta que a ficha mostra depois de salva.
    final faixa = Participant(
      id: '',
      topId: '',
      fullName: '',
      heightCm: altura,
      weightKg: peso,
    ).faixaImc;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        'IMC ${imc.toStringAsFixed(1)} · ${faixa?.label ?? ""}',
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// Campo livre para comorbidade fora da lista.
class CampoOutraComorbidade extends StatefulWidget {
  const CampoOutraComorbidade({super.key, required this.aoAdicionar});

  final void Function(String) aoAdicionar;

  @override
  State<CampoOutraComorbidade> createState() => _CampoOutraComorbidadeState();
}

class _CampoOutraComorbidadeState extends State<CampoOutraComorbidade> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _adicionar() {
    final texto = _controller.text.trim();
    if (texto.isEmpty) return;
    widget.aoAdicionar(texto);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            decoration: const InputDecoration(
              labelText: 'Outra comorbidade',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _adicionar(),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: _adicionar,
        ),
      ],
    );
  }
}

/// Seletor de comorbidades: chips da lista comum + as digitadas à mão.
///
/// Separado porque é o campo que a triagem conta. `Participant
/// .totalComorbidades` conta ESTA lista — e é por isso que alergia, plano
/// de saúde e medicação têm campos próprios: incluí-los aqui inflaria a
/// contagem e mudaria a cor de triagem de quem não tem comorbidade alguma.
class SeletorComorbidades extends StatelessWidget {
  const SeletorComorbidades({
    super.key,
    required this.selecionadas,
    required this.aoMudar,
  });

  final List<String> selecionadas;
  final void Function(List<String>) aoMudar;

  @override
  Widget build(BuildContext context) {
    final extras = selecionadas.where(
      (c) => !comorbidadesComuns.contains(c),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final c in comorbidadesComuns)
              FilterChip(
                label: Text(c),
                selected: selecionadas.contains(c),
                onSelected: (marcou) {
                  final nova = [...selecionadas];
                  if (marcou) {
                    nova.add(c);
                  } else {
                    nova.remove(c);
                  }
                  aoMudar(nova);
                },
              ),
            for (final c in extras)
              InputChip(
                label: Text(c),
                onDeleted: () => aoMudar([...selecionadas]..remove(c)),
              ),
          ],
        ),
        const SizedBox(height: 8),
        CampoOutraComorbidade(
          aoAdicionar: (nova) {
            if (selecionadas.contains(nova)) return;
            aoMudar([...selecionadas, nova]);
          },
        ),
        const SizedBox(height: 4),
        Text(
          '${selecionadas.length} comorbidade(s) — conta para a triagem',
          style: Theme.of(context).textTheme.labelSmall,
        ),
      ],
    );
  }
}
