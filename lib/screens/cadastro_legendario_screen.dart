import 'package:flutter/material.dart';

import '../services/acesso_service.dart';
import '../widgets/ficha_medica.dart';
import '../widgets/password_field.dart';

/// CADASTRO DO LEGENDÁRIO — ficha médica + criar a senha dele.
///
/// Passo 2 de 2. Chega aqui quem já provou ter a senha do Top e estar na
/// lista daquele evento (ver `PrimeiroAcessoScreen`).
///
/// **A senha do Top acaba aqui.** A pessoa sai deste fluxo com uma senha
/// própria e nunca mais usa a do grupo. Isso é o que impede o Legendário
/// 203460 de entrar na conta do 441892 digitando o número dele com a
/// senha compartilhada.
///
/// A ficha é a mesma dos Senderistas — tipo sanguíneo, comorbidades,
/// alergias, medicação. O que distingue o Legendário é ter número, e ele
/// já veio preenchido do passo anterior.
class CadastroLegendarioScreen extends StatefulWidget {
  const CadastroLegendarioScreen({
    super.key,
    required this.numero,
    required this.senhaDoTop,
    required this.convite,
  });

  final String numero;
  final String senhaDoTop;
  final ConviteValidado convite;

  @override
  State<CadastroLegendarioScreen> createState() =>
      _CadastroLegendarioScreenState();
}

class _CadastroLegendarioScreenState extends State<CadastroLegendarioScreen> {
  final _formKey = GlobalKey<FormState>();

  // Nome e família já vêm da lista do Top. Editáveis porque o cadastro do
  // evento pode estar abreviado ou com erro de digitação, e quem sabe o
  // nome certo é a própria pessoa.
  late final _nome = TextEditingController(text: widget.convite.nome);
  late final _familia = TextEditingController(
    text: widget.convite.familia ?? '',
  );

  final _apelido = TextEditingController();
  final _telefone = TextEditingController();
  final _cidade = TextEditingController();
  final _estado = TextEditingController();
  final _emergencia = TextEditingController();
  final _altura = TextEditingController();
  final _peso = TextEditingController();
  final _biotipo = TextEditingController();
  final _cirurgias = TextEditingController();
  final _atividade = TextEditingController();
  final _alergias = TextEditingController();
  final _plano = TextEditingController();
  final _medicacao = TextEditingController();
  final _restricoes = TextEditingController();

  final _senha = TextEditingController();
  final _senhaRepetida = TextEditingController();

  DateTime? _nascimento;
  String? _tipoSanguineo;
  List<String> _comorbidades = [];
  bool _salvando = false;
  String? _erro;

  /// Mínimo da senha pessoal. Tem de bater com `MIN_SENHA` na Edge
  /// Function — se o app aceitar menos, o servidor recusa e a pessoa
  /// preenche a ficha inteira para receber erro no fim.
  static const _minSenha = 8;

  @override
  void dispose() {
    for (final c in [
      _nome, _familia, _apelido, _telefone, _cidade, _estado, _emergencia,
      _altura, _peso, _biotipo, _cirurgias, _atividade, _alergias, _plano,
      _medicacao, _restricoes, _senha, _senhaRepetida,
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
    final hoje = DateTime.now();
    final escolhida = await showDatePicker(
      context: context,
      initialDate: _nascimento ?? DateTime(hoje.year - 35),
      firstDate: DateTime(hoje.year - 100),
      lastDate: hoje,
      helpText: 'Data de nascimento',
    );
    if (escolhida != null) setState(() => _nascimento = escolhida);
  }

  Future<void> _cadastrar() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // Data de nascimento não é campo de texto, então o validator do Form
    // não a alcança. E ela não é opcional: a triagem é f(idade,
    // comorbidades) — sem nascimento, a pessoa aparece sem cor na lista.
    if (_nascimento == null) {
      setState(() => _erro = 'Informe a data de nascimento.');
      return;
    }

    setState(() {
      _salvando = true;
      _erro = null;
    });
    try {
      await AcessoService.instance.cadastrar(
        numero: widget.numero,
        senhaDoTop: widget.senhaDoTop,
        senhaPessoal: _senha.text,
        // Nomes de coluna do Postgres, como o resto do projeto.
        ficha: {
          'full_name': _nome.text.trim(),
          'nickname': _texto(_apelido),
          'phone': _texto(_telefone),
          'birth_date': _nascimento!.toIso8601String().split('T').first,
          'cidade': _texto(_cidade),
          'estado': _texto(_estado),
          'emergency_contact': _texto(_emergencia),
          'height_cm': _numero(_altura),
          'weight_kg': _numero(_peso),
          'blood_type': _tipoSanguineo,
          'biotipo': _texto(_biotipo),
          'cirurgias': _texto(_cirurgias),
          'atividade_fisica_semanal': _texto(_atividade),
          'comorbidades': _comorbidades,
          'alergias': _texto(_alergias),
          'plano_saude': _texto(_plano),
          'medicamentos_continuos': _texto(_medicacao),
          'restricoes_fisicas': _texto(_restricoes),
        },
      );
      if (!mounted) return;
      await _mostrarConcluido();
    } on AcessoRecusado catch (e) {
      if (mounted) setState(() => _erro = e.mensagem);
    } catch (e) {
      if (mounted) setState(() => _erro = 'Não foi possível cadastrar: $e');
    } finally {
      if (mounted) setState(() => _salvando = false);
    }
  }

  /// Fecha o fluxo até a tela de entrada.
  ///
  /// Não loga automaticamente de propósito: a pessoa acabou de criar uma
  /// senha e precisa usá-la uma vez para fixar. Entrar sozinho faria ela
  /// descobrir que esqueceu a senha só dias depois, no mato.
  Future<void> _mostrarConcluido() async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle_outline, size: 40),
        title: const Text('Cadastro concluído'),
        content: Text(
          'Agora entre com:\n\n'
          'Número: ${widget.numero}\n'
          'Senha: a que você acabou de criar\n\n'
          'A senha do Top não serve mais para entrar.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    // Volta até a tela de entrada, desmontando primeiro acesso e cadastro.
    Navigator.of(context).popUntil((rota) => rota.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Seu cadastro')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _cabecalho(context),

            const SecaoFicha('Identificação'),
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
                    controller: _apelido,
                    decoration: const InputDecoration(
                      labelText: 'Apelido',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            InkWell(
              onTap: _escolherNascimento,
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Data de nascimento *',
                  border: const OutlineInputBorder(),
                  // A triagem depende da idade; sem ela a pessoa fica sem
                  // cor na lista.
                  helperText: _nascimento == null
                      ? 'Obrigatória — a cor de triagem depende da idade'
                      : null,
                ),
                child: Text(
                  _nascimento == null
                      ? 'Toque para escolher'
                      : '${_nascimento!.day.toString().padLeft(2, '0')}/'
                            '${_nascimento!.month.toString().padLeft(2, '0')}/'
                            '${_nascimento!.year}',
                ),
              ),
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
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    controller: _cidade,
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
                    maxLength: 2,
                    decoration: const InputDecoration(
                      labelText: 'UF',
                      border: OutlineInputBorder(),
                      isDense: true,
                      counterText: '',
                    ),
                  ),
                ),
              ],
            ),

            const SecaoFicha('Medidas'),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _altura,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Altura (cm)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _peso,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Peso (kg)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            PreviaImc(altura: _numero(_altura), peso: _numero(_peso)),

            const SecaoFicha('Clínico'),
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
              controller: _cirurgias,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Cirurgias',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _atividade,
              decoration: const InputDecoration(
                labelText: 'Atividade física semanal',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),

            const SecaoFicha('Comorbidades'),
            SeletorComorbidades(
              selecionadas: _comorbidades,
              aoMudar: (nova) => setState(() => _comorbidades = nova),
            ),

            const SecaoFicha('Alergias e medicação'),
            // Fora de comorbidades de propósito: é a lista de comorbidades
            // que a triagem conta, e incluir plano de saúde ali inflaria a
            // contagem — erro que o app oficial comete.
            TextFormField(
              controller: _alergias,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Alergias',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _medicacao,
              minLines: 1,
              maxLines: 3,
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

            const SecaoFicha('Emergência'),
            TextFormField(
              controller: _emergencia,
              decoration: const InputDecoration(
                labelText: 'Contato de emergência',
                helperText: 'Nome e telefone de quem avisar',
                border: OutlineInputBorder(),
              ),
            ),

            const SecaoFicha('Sua senha'),
            Text(
              'Esta é a senha que você vai usar para entrar daqui em diante. '
              'A senha do Top não serve mais depois do cadastro.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            PasswordField(
              controller: _senha,
              labelText: 'Criar senha *',
              comBorda: true,
              validator: (v) {
                if (v == null || v.length < _minSenha) {
                  return 'Pelo menos $_minSenha caracteres';
                }
                // Mesma regra do servidor: senha pessoal igual à do Top
                // entregaria a conta a todo mundo que recebeu o convite.
                if (v.trim().toUpperCase() ==
                    widget.senhaDoTop.trim().toUpperCase()) {
                  return 'Escolha uma senha diferente da senha do Top';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            PasswordField(
              controller: _senhaRepetida,
              labelText: 'Repetir senha *',
              comBorda: true,
              validator: (v) =>
                  v == _senha.text ? null : 'As senhas não são iguais',
            ),

            const SizedBox(height: 24),
            if (_erro != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  _erro!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            FilledButton(
              onPressed: _salvando ? null : _cadastrar,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
              ),
              child: _salvando
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('CONCLUIR CADASTRO'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  /// Mostra em qual Top a pessoa está entrando e com qual número.
  ///
  /// Serve de conferência: se o nome que veio da lista não for o dela, ela
  /// digitou o número de outra pessoa e para aqui, antes de criar conta.
  Widget _cabecalho(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Passo 2 de 2',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: scheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.convite.nome,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: scheme.onPrimaryContainer,
            ),
          ),
          Text(
            'Nº ${widget.numero}'
            '${widget.convite.familia != null ? ' · Família ${widget.convite.familia}' : ''}',
            style: TextStyle(color: scheme.onPrimaryContainer),
          ),
          Text(
            'Top ${widget.convite.topNome}',
            style: TextStyle(color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: 6),
          Text(
            'Não é você? Volte e confira o número.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: scheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
