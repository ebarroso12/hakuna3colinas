import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/participant.dart';
import '../../models/top.dart';
import '../../services/supabase_service.dart';
import '../../widgets/app_logo.dart';

/// Cadastro e edição da ficha de um participante.
///
/// Era o que ainda obrigava a mexer no banco por SQL para colocar gente no
/// Top. Com esta tela o app fica autossuficiente.
///
/// A ordem dos blocos segue a da ficha de leitura de propósito: quem
/// preenche e quem consulta veem as coisas no mesmo lugar.
class ParticipanteFormScreen extends StatefulWidget {
  const ParticipanteFormScreen({
    super.key,
    required this.top,
    this.participante,
  });

  final Top top;

  /// Null = cadastro novo.
  final Participant? participante;

  @override
  State<ParticipanteFormScreen> createState() => _ParticipanteFormScreenState();
}

class _ParticipanteFormScreenState extends State<ParticipanteFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final _nome = TextEditingController(text: widget.participante?.fullName);
  late final _apelido = TextEditingController(
    text: widget.participante?.nickname,
  );
  late final _familia = TextEditingController(
    text: widget.participante?.familia,
  );
  late final _codigo = TextEditingController(
    text: widget.participante?.participantCode,
  );
  late final _telefone = TextEditingController(
    text: widget.participante?.phone,
  );
  late final _cidade = TextEditingController(text: widget.participante?.cidade);
  late final _estado = TextEditingController(text: widget.participante?.estado);
  late final _emergencia = TextEditingController(
    text: widget.participante?.emergencyContact,
  );
  late final _altura = TextEditingController(
    text: widget.participante?.heightCm?.toStringAsFixed(0),
  );
  late final _peso = TextEditingController(
    text: widget.participante?.weightKg?.toStringAsFixed(1),
  );
  late final _biotipo = TextEditingController(
    text: widget.participante?.biotipo,
  );
  late final _cirurgias = TextEditingController(
    text: widget.participante?.cirurgias,
  );
  late final _observacao = TextEditingController(
    text: widget.participante?.observacaoHakuna,
  );
  late final _atividade = TextEditingController(
    text: widget.participante?.atividadeFisicaSemanal,
  );
  late final _alergias = TextEditingController(
    text: widget.participante?.alergias,
  );
  late final _plano = TextEditingController(
    text: widget.participante?.planoSaude,
  );
  late final _medicacao = TextEditingController(
    text: widget.participante?.medicamentosContinuos,
  );
  late final _restricoes = TextEditingController(
    text: widget.participante?.restricoesFisicas,
  );

  DateTime? _nascimento;
  String? _tipoSanguineo;
  late final List<String> _comorbidades = [
    ...?widget.participante?.comorbidades,
  ];

  bool _salvando = false;

  static const _tiposSanguineos = [
    'A+',
    'A-',
    'B+',
    'B-',
    'AB+',
    'AB-',
    'O+',
    'O-',
  ];

  /// Lista de partida. O campo livre continua existindo — doença que não
  /// está aqui não pode ficar de fora da ficha.
  static const _comorbidadesComuns = [
    'hipertensão',
    'diabetes',
    'asma',
    'cardiopatia',
    'obesidade',
    'epilepsia',
    'doença renal',
    'problema de coluna',
  ];

  bool get _editando => widget.participante != null;

  @override
  void initState() {
    super.initState();
    _nascimento = widget.participante?.birthDate;
    _tipoSanguineo = widget.participante?.bloodType;
  }

  @override
  void dispose() {
    for (final c in [
      _nome,
      _apelido,
      _familia,
      _codigo,
      _telefone,
      _cidade,
      _estado,
      _emergencia,
      _altura,
      _peso,
      _biotipo,
      _cirurgias,
      _observacao,
      _atividade,
      _alergias,
      _plano,
      _medicacao,
      _restricoes,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _texto(TextEditingController c) {
    final t = c.text.trim();
    return t.isEmpty ? null : t;
  }

  double? _numero(TextEditingController c) {
    final t = c.text.trim().replaceAll(',', '.');
    return t.isEmpty ? null : double.tryParse(t);
  }

  Future<void> _escolherNascimento() async {
    final agora = DateTime.now();
    final escolhida = await showDatePicker(
      context: context,
      initialDate: _nascimento ?? DateTime(agora.year - 30),
      firstDate: DateTime(agora.year - 100),
      lastDate: agora,
      helpText: 'Data de nascimento',
    );
    if (escolhida != null) setState(() => _nascimento = escolhida);
  }

  Future<void> _salvar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _salvando = true);
    try {
      final dados = {
        'top_id': widget.top.id,
        'full_name': _nome.text.trim(),
        'nickname': _texto(_apelido),
        'familia': _texto(_familia),
        'participant_code': _texto(_codigo),
        'phone': _texto(_telefone),
        'cidade': _texto(_cidade),
        'estado': _texto(_estado),
        'emergency_contact': _texto(_emergencia),
        'birth_date': _nascimento?.toIso8601String().split('T').first,
        'height_cm': _numero(_altura),
        'weight_kg': _numero(_peso),
        'blood_type': _tipoSanguineo,
        'biotipo': _texto(_biotipo),
        'cirurgias': _texto(_cirurgias),
        'observacao_hakuna': _texto(_observacao),
        'atividade_fisica_semanal': _texto(_atividade),
        'comorbidades': _comorbidades,
        'alergias': _texto(_alergias),
        'plano_saude': _texto(_plano),
        'medicamentos_continuos': _texto(_medicacao),
        'restricoes_fisicas': _texto(_restricoes),
        'active': true,
      };

      if (_editando) {
        await SupabaseService.instance.atualizarParticipante(
          widget.participante!.id,
          dados,
        );
      } else {
        await SupabaseService.instance.criarParticipante(dados);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _salvando = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Não foi possível salvar: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editando ? 'Editar ficha' : 'Novo participante'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: FilledButton(
              onPressed: _salvando ? null : _salvar,
              child: _salvando
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Salvar'),
            ),
          ),
          const AppLogoTrailing(),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Secao('Identificação'),
            TextFormField(
              controller: _nome,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Nome completo *',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Informe o nome' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _familia,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Família',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _codigo,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Nº Legendários',
                      // Quem tem numero e Legendario; quem nao tem e
                      // Senderista. E essa a regra que separa os dois.
                      helperText: 'Em branco = Senderista',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _apelido,
              decoration: const InputDecoration(
                labelText: 'Apelido',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
                side: BorderSide(color: Theme.of(context).dividerColor),
              ),
              leading: const Icon(Icons.cake_outlined),
              title: Text(
                _nascimento == null
                    ? 'Data de nascimento'
                    : '${_nascimento!.day.toString().padLeft(2, "0")}/'
                          '${_nascimento!.month.toString().padLeft(2, "0")}/'
                          '${_nascimento!.year}',
              ),
              // Sem data de nascimento a triagem nao classifica: a ficha
              // mostra "Sem triagem" em vez de uma cor.
              subtitle: _nascimento == null
                  ? const Text('Sem ela, a triagem não calcula a cor')
                  : null,
              trailing: const Icon(Icons.calendar_today, size: 18),
              onTap: _escolherNascimento,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    controller: _cidade,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Cidade',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _estado,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Estado',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _telefone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Telefone',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),

            _Secao('Medidas'),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _altura,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Altura',
                      suffixText: 'cm',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _peso,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Peso',
                      suffixText: 'kg',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            _PreviaImc(altura: _numero(_altura), peso: _numero(_peso)),

            _Secao('Clínico'),
            DropdownButtonFormField<String>(
              initialValue: _tipoSanguineo,
              decoration: const InputDecoration(
                labelText: 'Tipo sanguíneo',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: _tiposSanguineos
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setState(() => _tipoSanguineo = v),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _biotipo,
              decoration: const InputDecoration(
                labelText: 'Biotipo',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _atividade,
              decoration: const InputDecoration(
                labelText: 'Atividade física semanal',
                hintText: 'NENHUMA · 1 A 2 VEZES · 3 A 4 VEZES · 5 OU MAIS',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _cirurgias,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Cirurgias',
                border: OutlineInputBorder(),
              ),
            ),

            _Secao('Comorbidades'),
            Text(
              'Só condição clínica. É esta lista que define a cor da '
              'triagem — por isso alergia e plano de saúde ficam em campos '
              'separados, abaixo.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              children: [
                for (final c in _comorbidadesComuns)
                  FilterChip(
                    label: Text(c),
                    selected: _comorbidades.contains(c),
                    onSelected: (sel) => setState(() {
                      if (sel) {
                        _comorbidades.add(c);
                      } else {
                        _comorbidades.remove(c);
                      }
                    }),
                  ),
                // Comorbidade digitada à mão (não está na lista comum).
                for (final c in _comorbidades.where(
                  (c) => !_comorbidadesComuns.contains(c),
                ))
                  InputChip(
                    label: Text(c),
                    onDeleted: () => setState(() => _comorbidades.remove(c)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            _CampoOutraComorbidade(
              aoAdicionar: (nova) => setState(() => _comorbidades.add(nova)),
            ),
            const SizedBox(height: 6),
            Text(
              '${_comorbidades.length} comorbidade(s) — conta para a triagem',
              style: Theme.of(context).textTheme.labelSmall,
            ),

            _Secao('Outros dados de saúde'),
            TextFormField(
              controller: _alergias,
              minLines: 1,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Alergias',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _medicacao,
              minLines: 1,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Medicamentos de uso contínuo',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _restricoes,
              minLines: 1,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Restrições físicas',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _plano,
              decoration: const InputDecoration(
                labelText: 'Plano de saúde',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _observacao,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Observação Hakuna',
                border: OutlineInputBorder(),
              ),
            ),

            _Secao('Emergência'),
            TextFormField(
              controller: _emergencia,
              decoration: const InputDecoration(
                labelText: 'Contato de emergência',
                hintText: 'Nome e telefone de quem avisar',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _Secao extends StatelessWidget {
  const _Secao(this.titulo);

  final String titulo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 10),
      child: Text(
        titulo.toUpperCase(),
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 0.5),
      ),
    );
  }
}

/// Mostra o IMC enquanto se digita altura e peso — evita descobrir só
/// depois de salvar que faltou um dos dois.
class _PreviaImc extends StatelessWidget {
  const _PreviaImc({required this.altura, required this.peso});

  final double? altura;
  final double? peso;

  @override
  Widget build(BuildContext context) {
    if (altura == null || peso == null || altura! <= 0) {
      return const SizedBox.shrink();
    }
    final metros = altura! / 100;
    final imc = peso! / (metros * metros);
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
        style: Theme.of(context).textTheme.labelMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _CampoOutraComorbidade extends StatefulWidget {
  const _CampoOutraComorbidade({required this.aoAdicionar});

  final void Function(String) aoAdicionar;

  @override
  State<_CampoOutraComorbidade> createState() => _CampoOutraComorbidadeState();
}

class _CampoOutraComorbidadeState extends State<_CampoOutraComorbidade> {
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
