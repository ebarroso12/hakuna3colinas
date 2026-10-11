import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/participant.dart';
import '../../models/top.dart';
import '../../services/auditoria_service.dart';
import '../../services/participante_service.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/botao_inicio.dart';
import '../../widgets/ficha_medica.dart';

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

  /// Marca este cadastro como TESTE.
  ///
  /// Começa com o valor que a ficha já tem (editar um teste não o
  /// transforma em real sem querer).
  late bool _isTeste = widget.participante?.isTeste ?? false;

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

  /// Nomes dos campos cujo valor mudou em relação à ficha carregada.
  ///
  /// Serve para o `audit_log` dizer "alteraram comorbidades e tipo
  /// sanguíneo" em vez de "alteraram a ficha" — a segunda frase não ajuda
  /// ninguém a investigar nada.
  List<String> _camposAlterados(Map<String, dynamic> novos) {
    final antigo = widget.participante!.toMap();
    final mudou = <String>[];
    for (final chave in novos.keys) {
      // `top_id` e `active` não são editáveis nesta tela; comparar só
      // geraria ruído na lista.
      if (chave == 'top_id' || chave == 'active') continue;
      if (!_mesmoValor(antigo[chave], novos[chave])) mudou.add(chave);
    }
    return mudou;
  }

  /// Compara valor antigo e novo tolerando as diferenças de formato que
  /// existem entre o que vem do banco e o que a tela monta.
  bool _mesmoValor(Object? a, Object? b) {
    if (a == null && b == null) return true;
    // Lista de comorbidades: a ORDEM não é informação, então diferença de
    // ordem não é alteração.
    if (a is List && b is List) {
      final sa = a.map((e) => '$e').toList()..sort();
      final sb = b.map((e) => '$e').toList()..sort();
      return sa.join('|') == sb.join('|');
    }
    // `birth_date` chega como DateTime do model e sai como 'YYYY-MM-DD'.
    if (a is DateTime) return a.toIso8601String().split('T').first == '$b';
    // Números: 70 e 70.0 são o mesmo peso.
    if (a is num && b is num) return a.toDouble() == b.toDouble();
    return '$a' == '$b';
  }

  Future<void> _salvar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _salvando = true);
    try {
      // `top_id` e `registered_by` saem do `ParticipanteService`: aqui é a
      // ficha, lá é a identidade da linha.
      final dados = {
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
        'is_teste': _isTeste,
      };

      // Pela FILA, não direto no Supabase.
      //
      // Esta tela é aberta de duas telas de campo — "Novo" na lista de
      // participantes e "Editar" dentro da ficha. Quando gravava direto,
      // salvar sem sinal falhava e a ficha inteira era perdida: nome,
      // comorbidade, alergia, tudo digitado no mato e jogado fora num
      // toque. Agora vai para o aparelho e sobe quando a rede voltar.
      final String participanteId;
      if (_editando) {
        await ParticipanteService.instance.atualizar(
          id: widget.participante!.id,
          topId: widget.top.id,
          dados: dados,
        );
        participanteId = widget.participante!.id;
      } else {
        final criado = await ParticipanteService.instance.criar(
          topId: widget.top.id,
          dados: dados,
        );
        participanteId = criado.id;
      }

      // Auditoria da ficha. `AcaoAuditada.fichaAlterada` existia e
      // **nada no app a usava**: alterar comorbidade, tipo sanguíneo ou
      // alergia de um paciente não deixava rastro nenhum. Em ficha médica
      // o que mudou e quem mudou vale tanto quanto o valor atual.
      //
      // Depois de salvar, não antes: auditar uma alteração que falhou
      // seria registrar algo que não aconteceu. E `registrar` nunca lança
      // — auditoria não pode derrubar o salvamento da ficha.
      await AuditoriaService.instance.registrar(
        acao: AcaoAuditada.fichaAlterada,
        entityType: 'top_participants',
        entityId: participanteId,
        topId: widget.top.id,
        metadata: {
          'operacao': _editando ? 'alteracao' : 'criacao',
          // Só os NOMES dos campos alterados, nunca os valores: o
          // `audit_log` é legível por qualquer admin, e copiar comorbidade
          // e alergia para lá criaria um segundo prontuário com regra de
          // acesso mais frouxa que o primeiro.
          'campos': _editando
              ? _camposAlterados(dados)
              : dados.keys.where((k) => dados[k] != null).toList(),
        },
      );

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
          const BotaoInicio(),
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
            // O marcador de TESTE vem PRIMEIRO, antes de qualquer campo.
            //
            // No fim da ficha ninguém veria — e a consequência de errar é
            // assimétrica: cadastro de teste que passa por real polui a
            // lista do evento, e cadastro real marcado como teste entra na
            // conta do "apagar todos os testes". A posição é a proteção.
            Card(
              margin: const EdgeInsets.only(bottom: 16),
              color: _isTeste
                  ? Theme.of(context).colorScheme.tertiaryContainer
                  : null,
              child: SwitchListTile(
                value: _isTeste,
                onChanged: (v) => setState(() => _isTeste = v),
                title: Text(
                  _isTeste ? 'CADASTRO DE TESTE' : 'Cadastro real',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  _isTeste
                      ? 'Aparece com selo TESTE na lista e é apagado em '
                            'bloco pela ação "apagar testes". Não é pessoa '
                            'do evento.'
                      : 'Pessoa real do Top. Ligue o marcador se este '
                            'cadastro existe só para experimentar o app.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                secondary: Icon(
                  _isTeste ? Icons.science : Icons.person,
                  color: _isTeste
                      ? Theme.of(context).colorScheme.onTertiaryContainer
                      : null,
                ),
              ),
            ),

            SecaoFicha('Identificação'),
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

            SecaoFicha('Medidas'),
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
            PreviaImc(altura: _numero(_altura), peso: _numero(_peso)),

            SecaoFicha('Clínico'),
            DropdownButtonFormField<String>(
              initialValue: _tipoSanguineo,
              decoration: const InputDecoration(
                labelText: 'Tipo sanguíneo',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: tiposSanguineos
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

            SecaoFicha('Comorbidades'),
            Text(
              'Só condição clínica. É esta lista que define a cor da '
              'triagem — por isso alergia e plano de saúde ficam em campos '
              'separados, abaixo.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            SeletorComorbidades(
              selecionadas: _comorbidades,
              aoMudar: (nova) => setState(() {
                _comorbidades
                  ..clear()
                  ..addAll(nova);
              }),
            ),

            SecaoFicha('Outros dados de saúde'),
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

            SecaoFicha('Emergência'),
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
