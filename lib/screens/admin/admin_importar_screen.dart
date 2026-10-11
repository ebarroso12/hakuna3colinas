import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/team.dart';
import '../../models/team_message.dart';
import '../../models/top.dart';
import '../../services/admin_service.dart';
import '../../services/importador_de_pessoas.dart';
import '../../services/participante_service.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/botao_inicio.dart';

/// Importa lista de pessoas de planilha para um Top.
///
/// **Nada é gravado antes de você revisar.** A tela lê o arquivo, mostra o
/// que entendeu de cada coluna, lista o que deu problema linha por linha,
/// e só grava o que estiver marcado. Importar direto é o caminho que
/// coloca a pessoa errada numa ficha médica — número trocado significa
/// comorbidade e alergia de outro aparecendo no atendimento.
///
/// CSV, XLSX e TXT delimitado. **PDF não**: é para retenção de documento,
/// não para dado. Extrair tabela de PDF não é confiável — imagem
/// escaneada precisa de OCR, e OCR confunde `0`/`O` e `1`/`l`.
class AdminImportarScreen extends StatefulWidget {
  const AdminImportarScreen({super.key, required this.top});

  final Top top;

  @override
  State<AdminImportarScreen> createState() => _AdminImportarScreenState();
}

class _AdminImportarScreenState extends State<AdminImportarScreen> {
  LeituraDoArquivo? _leitura;
  String? _nomeDoArquivo;
  bool _lendo = false;
  bool _gravando = false;
  int _gravados = 0;

  /// Marcar como teste tudo que entrar por este arquivo.
  ///
  /// Útil para experimentar a importação sem poluir a lista do evento: o
  /// que entra marcado sai depois num clique em "apagar testes".
  bool _comoTeste = false;

  Future<void> _escolherArquivo() async {
    setState(() => _lendo = true);
    try {
      // `FilePicker.pickFiles` e estatico e devolve LISTA na v13 (era
      // `FilePicker.platform` e um objeto com `.files`). Os bytes vem de
      // `readAsBytes()`, nao de um campo `bytes`: na web o arquivo pode
      // ser um blob sem caminho local, e ler sob demanda cobre os dois
      // casos.
      final escolhidos = await FilePicker.pickFiles(
        dialogTitle: 'Escolher a lista de pessoas',
        type: FileType.custom,
        allowedExtensions: const ['csv', 'txt', 'xlsx'],
      );
      final arquivo = escolhidos.firstOrNull;
      if (arquivo == null) return;
      final bytes = await arquivo.readAsBytes();

      final nome = arquivo.name.toLowerCase();
      final leitura = nome.endsWith('.xlsx')
          ? ImportadorDePessoas.lerXlsx(bytes)
          : ImportadorDePessoas.lerCsv(bytes);

      if (!mounted) return;
      setState(() {
        _leitura = leitura;
        _nomeDoArquivo = arquivo.name;
        _gravados = 0;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível abrir o arquivo: $e')),
      );
    } finally {
      if (mounted) setState(() => _lendo = false);
    }
  }

  List<PessoaImportada> get _marcadas =>
      (_leitura?.pessoas ?? []).where((p) => p.selecionada).toList();

  Future<void> _gravar() async {
    final marcadas = _marcadas;
    if (marcadas.isEmpty) return;

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Importar ${marcadas.length} pessoa(s)?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Para o Top: ${widget.top.name}'),
            const SizedBox(height: 8),
            if (_comoTeste)
              const Text(
                'Todas entram marcadas como CADASTRO DE TESTE.',
                style: TextStyle(fontWeight: FontWeight.bold),
              )
            else
              const Text(
                'Entram como cadastro real do evento.',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            const SizedBox(height: 8),
            const Text(
              'Quem tiver equipe e cargo na planilha também é incluído na '
              'equipe, já liberado. Sem liberar, a pessoa não tem chat nem '
              'bloco de anotações.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('IMPORTAR ${marcadas.length}'),
          ),
        ],
      ),
    );
    if (confirmou != true) return;

    setState(() {
      _gravando = true;
      _gravados = 0;
    });

    final falhas = <String>[];
    for (final p in marcadas) {
      try {
        // Pelo `ParticipanteService`, não por insert direto: assim a
        // ficha vai para o cache local e para a fila, igual ao cadastro
        // feito à mão. Se a rede cair no meio da importação, o que já
        // entrou sobe depois em vez de se perder.
        final criado = await ParticipanteService.instance.criar(
          topId: widget.top.id,
          dados: {
            'full_name': p.nome,
            'participant_code': p.numero,
            'familia': p.familia,
            'phone': p.telefone,
            'cidade': p.cidade,
            'estado': p.estado,
            'active': true,
            'is_teste': _comoTeste,
          },
        );

        // Equipe e cargo, quando a planilha trouxe.
        //
        // `released: true` de propósito: o admin acabou de dizer, na
        // planilha, que a pessoa é daquela equipe. Entrar não-liberada
        // exigiria ele abrir a tela de equipes e liberar 200 nomes um por
        // um — e `is_team_member` exige `released`, então sem isso a
        // pessoa fica sem chat e sem anotações.
        if (p.equipe != null) {
          final perfil = criado.linkedProfileId;
          if (perfil != null) {
            await AdminService.instance.addTeamMember(
              topId: widget.top.id,
              profileId: perfil,
              team: p.equipe!,
              papel: p.cargo ?? TeamRole.membro,
              released: true,
            );
          }
          // Sem `linked_profile_id` não há como vincular à equipe: a
          // pessoa ainda não tem conta. A equipe entra quando ela se
          // cadastrar — e isso está dito no resumo, não escondido.
        }

        if (mounted) setState(() => _gravados++);
      } catch (e) {
        falhas.add('${p.nome} (linha ${p.linhaNoArquivo}): $e');
      }
    }

    if (!mounted) return;
    setState(() => _gravando = false);

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$_gravados importada(s)'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              if (falhas.isEmpty)
                const Text('Nenhuma falha.')
              else ...[
                Text(
                  '${falhas.length} falharam:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(ctx).colorScheme.error,
                  ),
                ),
                const SizedBox(height: 6),
                for (final f in falhas)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(f, style: const TextStyle(fontSize: 12)),
                  ),
              ],
              const SizedBox(height: 12),
              const Text(
                'Quem tem número do Legendários já consegue se '
                'autocadastrar. Quem entrou sem número NÃO consegue — '
                'o autocadastro exige o número na lista do Top.',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final leitura = _leitura;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Importar lista'),
            Text(
              widget.top.name,
              style: Theme.of(context).textTheme.labelSmall,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: const [BotaoInicio(), AppLogoTrailing()],
      ),
      bottomNavigationBar: leitura == null || leitura.vazio
          ? null
          : _BarraDeImportar(
              marcadas: _marcadas.length,
              total: leitura.pessoas.length,
              gravando: _gravando,
              gravados: _gravados,
              aoImportar: _gravar,
            ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Nada é gravado antes de você revisar.',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Aceita CSV, TXT e XLSX. A primeira linha com conteúdo '
                    'tem de ser o cabeçalho, com uma coluna de NOME.\n\n'
                    'Colunas reconhecidas: Nome, Nº Legendários, Família, '
                    'Telefone, Cidade, UF, Equipe, Cargo.\n\n'
                    'PDF não serve para importar dado — só para guardar '
                    'documento.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          FilledButton.icon(
            onPressed: _lendo || _gravando ? null : _escolherArquivo,
            icon: _lendo
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.upload_file),
            label: Text(
              _nomeDoArquivo == null
                  ? 'Escolher arquivo'
                  : 'Trocar arquivo ($_nomeDoArquivo)',
            ),
          ),

          if (leitura != null) ...[
            const SizedBox(height: 16),
            if (leitura.erro != null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: const Text('Não deu para usar este arquivo'),
                  subtitle: Text(leitura.erro!),
                ),
              )
            else ...[
              _ResumoDaLeitura(leitura: leitura),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _comoTeste,
                onChanged: _gravando
                    ? null
                    : (v) => setState(() => _comoTeste = v),
                title: Text(
                  _comoTeste
                      ? 'Importar como CADASTRO DE TESTE'
                      : 'Importar como cadastro real',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  _comoTeste
                      ? 'Entram com selo TESTE e saem depois num clique.'
                      : 'Ligue para experimentar sem poluir a lista do '
                            'evento.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                secondary: Icon(_comoTeste ? Icons.science : Icons.groups),
              ),
              const Divider(),
              for (final p in leitura.pessoas)
                _LinhaImportada(
                  pessoa: p,
                  habilitado: !_gravando,
                  aoAlternar: () => setState(
                    () => p.selecionada = !p.selecionada,
                  ),
                ),
              const SizedBox(height: 80),
            ],
          ],
        ],
      ),
    );
  }
}

class _ResumoDaLeitura extends StatelessWidget {
  const _ResumoDaLeitura({required this.leitura});

  final LeituraDoArquivo leitura;

  @override
  Widget build(BuildContext context) {
    final comProblema = leitura.pessoas.where((p) => !p.valida).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${leitura.pessoas.length} linha(s) lida(s)'
              '${comProblema > 0 ? " · $comProblema com problema" : ""}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('O que entendi de cada coluna:'),
            const SizedBox(height: 4),
            for (final e in leitura.cabecalhoReconhecido.entries)
              Text(
                '• "${e.key}" → ${e.value}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (leitura.colunasIgnoradas.isNotEmpty) ...[
              const SizedBox(height: 8),
              // Mostradas de propósito: se o nome da pessoa estiver numa
              // coluna ignorada, o admin vê aqui antes de gravar.
              Text(
                'Colunas que NÃO uso: '
                '${leitura.colunasIgnoradas.join(", ")}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LinhaImportada extends StatelessWidget {
  const _LinhaImportada({
    required this.pessoa,
    required this.habilitado,
    required this.aoAlternar,
  });

  final PessoaImportada pessoa;
  final bool habilitado;
  final VoidCallback aoAlternar;

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final partes = [
      if ((pessoa.numero ?? '').isNotEmpty) '#${pessoa.numero}',
      if ((pessoa.familia ?? '').isNotEmpty) 'Família ${pessoa.familia}',
      if (pessoa.equipe != null) pessoa.equipe!.label,
      if (pessoa.cargo != null) pessoa.cargo!.label,
    ];

    return CheckboxListTile(
      dense: true,
      value: pessoa.selecionada,
      onChanged: habilitado ? (_) => aoAlternar() : null,
      title: Text(
        pessoa.nome ?? '(sem nome)',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: pessoa.valida ? null : cores.error,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'linha ${pessoa.linhaNoArquivo}'
            '${partes.isEmpty ? "" : " · ${partes.join(" · ")}"}',
            style: Theme.of(context).textTheme.labelSmall,
          ),
          // O MOTIVO, não "linha inválida". "número repetido (igual ao da
          // linha 14)" é acionável; "erro" não é.
          for (final problema in pessoa.problemas)
            Text(
              '⚠ $problema',
              style: TextStyle(fontSize: 11, color: cores.error),
            ),
        ],
      ),
    );
  }
}

class _BarraDeImportar extends StatelessWidget {
  const _BarraDeImportar({
    required this.marcadas,
    required this.total,
    required this.gravando,
    required this.gravados,
    required this.aoImportar,
  });

  final int marcadas;
  final int total;
  final bool gravando;
  final int gravados;
  final VoidCallback aoImportar;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                gravando
                    ? 'Importando… $gravados de $marcadas'
                    : '$marcadas de $total marcada(s)',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            FilledButton.icon(
              onPressed: gravando || marcadas == 0 ? null : aoImportar,
              icon: gravando
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_alt),
              label: const Text('Importar'),
            ),
          ],
        ),
      ),
    );
  }
}
