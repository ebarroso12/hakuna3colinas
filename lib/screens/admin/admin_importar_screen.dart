import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/profile.dart';
import '../../models/team.dart';
import '../../models/team_message.dart';
import '../../models/top.dart';
import '../../offline/dados_do_top.dart';
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

  /// Contas que já existem no app, por número do Legendários.
  ///
  /// Equipe e cargo da planilha só podem ser aplicados a quem TEM conta:
  /// `top_team_members.profile_id` referencia `profiles`, e planilha não
  /// cria conta. Antes isto era prometido no diálogo de confirmação e
  /// nunca acontecia — `ParticipanteService.criar` devolve uma ficha com
  /// `linked_profile_id` nulo, então o bloco que chamava `addTeamMember`
  /// era código morto. Achado por revisão em 11/10/2026.
  Map<String, String> _perfilPorNumero = {};
  bool _perfisCarregados = false;

  /// Quem já está neste Top: por número e por nome normalizado.
  Map<String, String> _jaNoTopPorNumero = {};
  Map<String, String> _jaNoTopPorNome = {};

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

      await _marcarQuemJaExiste(leitura);

      if (!mounted) return;
      setState(() {
        _leitura = leitura;
        _nomeDoArquivo = arquivo.name;
        _gravados = 0;
      });

      // Depois de mostrar a lista, não antes: carregar perfis precisa de
      // rede, e a revisão do arquivo não pode esperar por ela.
      _carregarPerfis();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível abrir o arquivo: $e')),
      );
    } finally {
      if (mounted) setState(() => _lendo = false);
    }
  }

  /// Desmarca quem já está neste Top.
  ///
  /// Reimportar a planilha atualizada é o caminho natural — e era o que
  /// criava duplicata: `ParticipanteService.criar` gera id novo a cada
  /// chamada, e `(top_id, participant_code)` **não** é índice único. Com
  /// duas fichas do mesmo número, `participante_elegivel` resolve com
  /// `limit 1`, e o autocadastro podia ligar a conta à ficha vazia
  /// enquanto comorbidade e alergia ficavam na outra. Achado por revisão
  /// em 11/10/2026, antes do primeiro uso.
  ///
  /// Lê do SQLite (`DadosDoTop`), então funciona sem sinal. Desmarca, não
  /// remove: se o admin quiser mesmo uma segunda pessoa de mesmo nome, ele
  /// marca de novo — e vê o motivo escrito ao lado.
  Future<void> _marcarQuemJaExiste(LeituraDoArquivo leitura) async {
    try {
      final existentes = await DadosDoTop.instance.participantes(
        widget.top.id,
      );
      _jaNoTopPorNumero = {
        for (final e in existentes)
          if ((e.participantCode ?? '').isNotEmpty)
            e.participantCode!: e.fullName,
      };
      _jaNoTopPorNome = {
        for (final e in existentes)
          ImportadorDePessoas.normalizar(e.fullName): e.fullName,
      };
    } catch (_) {
      // Sem cache local não dá para conferir. Não vale impedir a
      // importação por isso — mas o aviso no topo da tela diz que a
      // conferência não foi feita, em vez de dar a entender que foi.
      _jaNoTopPorNumero = {};
      _jaNoTopPorNome = {};
      return;
    }

    for (final p in leitura.pessoas) {
      final numero = p.numero;
      final nome = p.nome;

      if (numero != null && _jaNoTopPorNumero.containsKey(numero)) {
        p.jaExiste =
            'já está no Top com este número: ${_jaNoTopPorNumero[numero]}';
      } else if (nome != null &&
          _jaNoTopPorNome.containsKey(ImportadorDePessoas.normalizar(nome))) {
        p.jaExiste = 'já está no Top com este nome';
      }
      if (p.jaExiste != null) p.selecionada = false;
    }
  }

  /// Casa o número da planilha com contas que já existem no app.
  ///
  /// É o que torna equipe e cargo aplicáveis. Quem não tem conta entra como
  /// ficha de participante e a equipe fica pendente — dito na tela, não
  /// escondido.
  Future<void> _carregarPerfis() async {
    try {
      final perfis = await AdminService.instance.fetchAllProfiles();
      if (!mounted) return;
      setState(() {
        _perfilPorNumero = {
          for (final Profile perfil in perfis)
            if (perfil.legendariosNumber.isNotEmpty)
              perfil.legendariosNumber: perfil.id,
        };
        _perfisCarregados = true;
      });
    } catch (_) {
      // Sem rede não há como saber quem tem conta. A tela diz que equipe e
      // cargo não serão aplicados nesta importação.
      if (mounted) setState(() => _perfisCarregados = false);
    }
  }

  /// Quantas linhas marcadas têm equipe E conta — as que de fato entram em
  /// alguma equipe.
  int get _equipesAplicaveis => _marcadas
      .where((p) => p.equipe != null && _perfilPorNumero[p.numero] != null)
      .length;

  /// Marcadas com equipe na planilha mas sem conta no app.
  int get _equipesPendentes => _marcadas
      .where((p) => p.equipe != null && _perfilPorNumero[p.numero] == null)
      .length;

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
            // Isto aqui prometia que "quem tiver equipe e cargo na
            // planilha também é incluído na equipe" — e não era verdade:
            // o código que faria isso era inalcançável. Agora o texto diz
            // o que de fato acontece, com os números desta importação.
            if (_equipesAplicaveis > 0)
              Text(
                'Entram em equipe agora: $_equipesAplicaveis '
                '(já têm conta no app, casadas pelo nº do Legendários).',
              ),
            if (_equipesPendentes > 0)
              Text(
                'Com equipe na planilha mas SEM conta no app: '
                '$_equipesPendentes. A ficha entra; a equipe não. '
                'Elas entram na equipe pela tela "Equipes do Top", depois '
                'de criarem conta.',
                style: TextStyle(
                  color: Theme.of(ctx).colorScheme.error,
                ),
              ),
            if (!_perfisCarregados)
              Text(
                'Não deu para consultar as contas do app (sem rede). '
                'Nenhuma equipe será aplicada nesta importação.',
                style: TextStyle(
                  color: Theme.of(ctx).colorScheme.error,
                ),
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
    final equipesFalhas = <String>[];
    final semConta = <String>[];
    var equipesAplicadas = 0;
    for (final p in marcadas) {
      try {
        // Pelo `ParticipanteService`, não por insert direto: assim a
        // ficha vai para o cache local e para a fila, igual ao cadastro
        // feito à mão. Se a rede cair no meio da importação, o que já
        // entrou sobe depois em vez de se perder.
        await ParticipanteService.instance.criar(
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

        // Equipe e cargo, quando a planilha trouxe E a pessoa tem conta.
        //
        // O perfil vem do casamento por NÚMERO do Legendários contra as
        // contas que já existem (`_perfilPorNumero`), não de
        // `criado.linkedProfileId`: `ParticipanteService.criar` monta a
        // ficha a partir de `dados`, que nunca carrega
        // `linked_profile_id`, então aquele campo é SEMPRE nulo aqui e o
        // bloco inteiro era código morto — enquanto o diálogo de
        // confirmação prometia a inclusão na equipe. Achado por revisão em
        // 11/10/2026.
        //
        // `released: true` de propósito: o admin acabou de dizer, na
        // planilha, que a pessoa é daquela equipe. Entrar não-liberada
        // exigiria abrir a tela de equipes e liberar 200 nomes um a um — e
        // `is_team_member` exige `released`, então sem isso a pessoa fica
        // sem chat e sem bloco de anotações.
        final perfil = _perfilPorNumero[p.numero];
        if (p.equipe != null && perfil != null) {
          try {
            await AdminService.instance.addTeamMember(
              topId: widget.top.id,
              profileId: perfil,
              team: p.equipe!,
              papel: p.cargo ?? TeamRole.membro,
              released: true,
            );
            equipesAplicadas++;
          } catch (e) {
            // A ficha já entrou; perder a equipe não justifica contar a
            // pessoa como falha. Vai para a lista de pendências, com nome.
            equipesFalhas.add('${p.nome}: $e');
          }
        } else if (p.equipe != null) {
          semConta.add(p.nome ?? 'linha ${p.linhaNoArquivo}');
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
              Text(
                equipesAplicadas > 0
                    ? '$equipesAplicadas entraram em equipe, já liberadas.'
                    : 'Nenhuma equipe foi aplicada.',
                style: const TextStyle(fontSize: 12),
              ),
              if (semConta.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '${semConta.length} tinham equipe na planilha mas não '
                  'têm conta no app, então a equipe NÃO foi aplicada. A '
                  'ficha entrou. Inclua pela tela "Equipes do Top" depois '
                  'que criarem conta:',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.error,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  semConta.join(', '),
                  style: const TextStyle(fontSize: 11),
                ),
              ],
              if (equipesFalhas.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  '${equipesFalhas.length} ficha(s) entraram mas a equipe '
                  'foi recusada pelo servidor:',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(ctx).colorScheme.error,
                  ),
                ),
                for (final f in equipesFalhas)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(f, style: const TextStyle(fontSize: 11)),
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
          // Já está no Top: a linha vem DESMARCADA, e o motivo tem de
          // estar escrito. Caixa desmarcada sem explicação parece defeito
          // da tela, e o admin marca de novo — criando a duplicata que o
          // desmarque existe para evitar.
          if (pessoa.jaExiste != null)
            Text(
              '⊘ ${pessoa.jaExiste}',
              style: TextStyle(
                fontSize: 11,
                color: cores.tertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
          // O MOTIVO, não "linha inválida". "número repetido (igual ao da
          // linha 14)" é acionável; "erro" não é.
          for (final problema in pessoa.problemas)
            Text(
              '⚠ $problema',
              style: TextStyle(fontSize: 11, color: cores.error),
            ),
          // Avisos NÃO impedem a linha de entrar. Ficam em outra cor para
          // não se confundirem com o que bloqueia.
          for (final aviso in pessoa.avisos)
            Text(
              'ℹ $aviso',
              style: TextStyle(fontSize: 11, color: cores.onSurfaceVariant),
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
