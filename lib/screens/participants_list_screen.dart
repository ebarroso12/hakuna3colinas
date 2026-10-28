import 'package:flutter/material.dart';

import '../models/afericao.dart';
import '../models/participant.dart';
import '../models/profile.dart';
import '../models/top.dart';
import '../models/triage_rule.dart';

import '../offline/dados_do_top.dart';
import '../offline/sync_service.dart';
import '../offline/texto_busca.dart';
import '../services/exclusao_service.dart';
import '../services/participante_service.dart';
import '../services/supabase_service.dart';
import '../services/triage_dinamica.dart';
import '../services/triage_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/barra_de_selecao.dart';
import '../widgets/barra_inferior.dart';
import '../widgets/botao_inicio.dart';
import '../widgets/cabecalho_usuario.dart';
import '../widgets/emblemas.dart';
import 'admin/participante_form_screen.dart';
import 'ler_tag_screen.dart';
import 'participant_file_screen.dart';

/// Lista de participantes do Top, com as duas buscas do app oficial:
/// uma por nome e outra por família.
///
/// **Lê do SQLite do aparelho**, não da rede. Até a v1.0.16 esta tela
/// chamava o Supabase direto, então em cold start sem sinal ela vinha
/// vazia — justamente no mato, onde é o plano B de quando a pulseira
/// falha. Agora a rede só alimenta o disco (ver [DadosDoTop]).
///
/// Os 215 registros vêm do disco de uma vez e os filtros rodam em memória,
/// com a mesma normalização de acento da coluna `busca_normalizada` — assim
/// digitar não dispara consulta e o resultado não chega fora de ordem.
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

  /// Última aferição de cada participante, por id. É o que faz a cor
  /// reagir a PA e SpO₂ em vez de ficar travada no cadastro.
  Map<String, Afericao> _afericoes = const {};

  Profile? _meuPerfil;

  /// Ids marcados para apagar. Vazio = fora do modo de seleção.
  ///
  /// Só o admin master entra nesse modo. Esta é a tela que o Hakuna usa em
  /// campo, com a mão ocupada — um caminho de exclusão aberto para todos
  /// aqui seria pedir para alguém apagar um paciente sem querer.
  final Set<String> _marcados = {};
  final Map<String, String> _nomesMarcados = {};
  bool _excluindo = false;

  bool get _souMaster => _meuPerfil?.isMasterAdmin ?? false;
  bool get _selecionando => _marcados.isNotEmpty;

  void _alternarMarca(Participant p) {
    setState(() {
      if (_marcados.remove(p.id)) {
        _nomesMarcados.remove(p.id);
      } else {
        _marcados.add(p.id);
        _nomesMarcados[p.id] = p.fullName;
      }
    });
  }

  void _limparSelecao() => setState(() {
    _marcados.clear();
    _nomesMarcados.clear();
  });

  /// Marca todos os que estão VISÍVEIS, não os 216.
  ///
  /// É o que faz o botão ser útil junto com a busca: filtra por "TESTE",
  /// marca todos, apaga. Marcar a lista inteira a partir de uma tela
  /// filtrada seria a forma mais fácil de alguém apagar o Top completo
  /// achando que apagou três nomes.
  void _marcarVisiveis(List<Participant> visiveis) {
    setState(() {
      for (final p in visiveis) {
        _marcados.add(p.id);
        _nomesMarcados[p.id] = p.fullName;
      }
    });
  }

  /// Apaga TODOS os cadastros de teste deste Top, de uma vez.
  ///
  /// Existe porque a alternativa é marcar nome por nome entre 216 — e aí
  /// se marca errado. `is_teste` é dado, não convenção de nome.
  Future<void> _apagarTestes() async {
    final testes = _todos.where((p) => p.isTeste).toList();
    if (testes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não há cadastro de teste neste Top.')),
      );
      return;
    }

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Apagar ${testes.length} cadastro(s) de teste?'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Text(
                'Sai de vez. Cadastro de teste que RECEBEU atendimento é '
                'mantido — o atendimento existe e ficaria sem paciente.',
              ),
              const SizedBox(height: 12),
              for (final p in testes)
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 2),
                  child: Text('• ${p.fullName}'),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('APAGAR TESTES'),
          ),
        ],
      ),
    );
    if (confirmou != true) return;

    setState(() => _excluindo = true);
    try {
      final r = await ParticipanteService.instance.apagarTestesDoTop(
        widget.top.id,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            r.bloqueados == 0
                ? '${r.apagados} cadastro(s) de teste apagado(s).'
                : '${r.apagados} apagado(s). ${r.bloqueados} '
                      'mantido(s) por ter atendimento registrado.',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ExclusaoService.mensagemDeErro(e)),
          duration: const Duration(seconds: 8),
        ),
      );
    } finally {
      if (mounted) setState(() => _excluindo = false);
    }
  }

  Future<void> _apagarMarcados() async {
    final ids = _marcados.toList();
    setState(() => _excluindo = true);
    try {
      final deps = await ExclusaoService.instance.dependenciasDeSenderistas(
        ids,
      );
      if (!mounted) return;

      final decisao = await confirmarExclusao(
        context,
        nomes: {for (final id in ids) id: _nomesMarcados[id] ?? id},
        dependencias: deps,
        // Senderista TEM desativar: `active = false` tira das listas e
        // mantém o prontuário inteiro. É a resposta certa para quem já
        // foi atendido.
        podeDesativar: true,
      );

      final liberados = ids
          .where((id) => deps[id]?.podeApagar ?? false)
          .toList();
      final bloqueados = ids
          .where((id) => !(deps[id]?.podeApagar ?? false))
          .toList();

      String? mensagem;
      if (decisao == DecisaoDaExclusao.apagar) {
        final n = await ExclusaoService.instance.apagarSenderistas(liberados);
        mensagem = '$n senderista(s) apagado(s).';
      } else if (decisao == DecisaoDaExclusao.desativar) {
        await ExclusaoService.instance.desativarSenderistas(bloqueados);
        mensagem =
            '${bloqueados.length} desativado(s). O prontuário foi mantido.';
      }
      if (mensagem == null) return;

      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(mensagem)));
      _limparSelecao();
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ExclusaoService.mensagemDeErro(e)),
          duration: const Duration(seconds: 8),
        ),
      );
    } finally {
      if (mounted) setState(() => _excluindo = false);
    }
  }

  bool _carregando = true;
  String? _erro;

  /// Quando os dados deste Top foram baixados. Null = nunca.
  ///
  /// Aparece na tela de propósito: no mato a idade do dado é informação
  /// clínica, e fingir que a lista está atualizada é pior que admitir que
  /// ela tem três horas.
  DateTime? _baixadoEm;

  @override
  void initState() {
    super.initState();
    // Disco primeiro, rede depois: a lista aparece na hora, com ou sem
    // sinal, e se houver sinal se atualiza sozinha em seguida. Antes a
    // lista só buscava o servidor no PRIMEIRO "Baixar" — depois disso,
    // nada que entrasse por outro aparelho chegava a esta tela.
    _carregar().then((_) => _atualizar(silencioso: true));
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
      final dados = DadosDoTop.instance;
      final participantes = await dados.participantes(widget.top.id);
      final regras = await dados.regras();
      final afericoes = await dados.afericoes(widget.top.id);
      final baixadoEm = await dados.baixadoEm(widget.top.id);
      // O cabecalho mostra quem esta logado naquele aparelho — falhar aqui
      // nao impede a lista de aparecer.
      try {
        _meuPerfil = await SupabaseService.instance.fetchMyProfile();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _todos = participantes;
        _regras = regras;
        _afericoes = afericoes;
        _baixadoEm = baixadoEm;
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

  /// Baixa os dados do Top para o aparelho. Precisa de sinal.
  ///
  /// É o botão que o Hakuna aperta antes de subir a trilha. Depois dele a
  /// lista e a leitura de tag funcionam sem rede, inclusive se o sistema
  /// matar o app e ele reabrir no meio do mato.
  Future<void> _baixar() => _atualizar(silencioso: false);

  /// Busca no servidor o que mudou e regrava o disco.
  ///
  /// Envia a fila ANTES de baixar: ficha feita aqui sem sinal sobe
  /// primeiro, e a lista que desce já a inclui. Se ainda sobrar ficha na
  /// fila, [DadosDoTop.baixar] mantém a lista do disco — e a tela diz.
  ///
  /// [silencioso] é a atualização automática ao abrir: sem sinal ela falha
  /// calada, porque a lista do disco já está na tela e um aviso de erro a
  /// cada abertura no mato ensinaria a ignorar avisos.
  Future<void> _atualizar({required bool silencioso}) async {
    if (!silencioso) setState(() => _carregando = true);
    try {
      try {
        await SyncService.instance.syncNow();
      } catch (_) {}
      final resumo = await DadosDoTop.instance.baixar(widget.top.id);
      if (!mounted) return;
      if (resumo.listaMantida) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${resumo.fichasSoNoAparelho} ficha(s) deste aparelho ainda '
              'não subiram. A lista fica como está para não perdê-las; '
              'atualize de novo quando houver sinal.',
            ),
          ),
        );
      } else if (!silencioso) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Atualizado: ${resumo.participantes} participantes, '
              '${resumo.tags} pulseiras, ${resumo.regras} regras de triagem.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted && !silencioso) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sem conexão com o servidor. A lista mostra o que já estava '
              'no aparelho.',
            ),
          ),
        );
      }
    }
    if (mounted) await _carregar();
  }

  /// Os dois filtros se somam: digitar nos dois campos restringe aos dois
  /// critérios ao mesmo tempo.
  ///
  /// Normaliza acento com [TextoBusca] — a mesma função que gera a coluna
  /// `busca_normalizada` no cache, para que os dois caminhos devolvam o
  /// mesmo resultado. Sem isso, `"joao"` não encontrava `"JOÃO"`.
  List<Participant> get _filtrados {
    final nome = TextoBusca.normalizar(_buscaNome.text);
    final familia = TextoBusca.normalizar(_buscaFamilia.text);
    if (nome.isEmpty && familia.isEmpty) return _todos;
    return _todos.where((p) {
      final casaNome =
          nome.isEmpty ||
          TextoBusca.chaveDe(
            nome: p.fullName,
            apelido: p.nickname,
            codigo: p.participantCode,
          ).contains(nome);
      final casaFamilia =
          familia.isEmpty || TextoBusca.normalizar(p.familia).contains(familia);
      return casaNome && casaFamilia;
    }).toList();
  }

  /// Gravidade atual: cadastro escalado pela última aferição.
  Gravidade _gravidadeDe(Participant p) => TriageDinamica.avaliar(
    corDeCadastro: TriageService.colorForParticipant(p, _regras),
    afericao: _afericoes[p.id],
  );

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
          const BotaoInicio(),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Atualizar do servidor',
            onPressed: _carregando ? null : _baixar,
          ),
          if (_souMaster)
            IconButton(
              icon: const Icon(Icons.science_outlined),
              tooltip: 'Apagar cadastros de teste',
              onPressed: _excluindo ? null : _apagarTestes,
            ),
          const AppLogoTrailing(),
        ],
        // A barra de seleção entra como `bottom`, não no lugar do título:
        // a seta de voltar e o botão de início continuam acessíveis. Numa
        // tela que apaga gente, a saída não pode desaparecer.
        bottom: _selecionando
            ? PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: BarraDeSelecao(
                  marcados: _marcados.length,
                  total: lista.length,
                  aoMarcarTodos: () => _marcarVisiveis(lista),
                  aoLimpar: _limparSelecao,
                  aoApagar: _excluindo ? () {} : _apagarMarcados,
                ),
              )
            : null,
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
          if (_souMaster && !_selecionando)
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Text(
                'Admin master: toque e segure um nome para marcar e apagar. '
                'Com a busca ativa, "marcar todos" pega só os filtrados.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          _avisoDados(),
          _avisoCriticos(),
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
        gravidade: _gravidadeDe(lista[i]),
        regras: _regras,
        top: widget.top,
        selecionando: _selecionando,
        marcado: _marcados.contains(lista[i].id),
        aoMarcar: _souMaster ? () => _alternarMarca(lista[i]) : null,
      ),
    );
  }

  /// Aviso de quem está com sinal vital crítico aferido.
  ///
  /// A lista segue em ordem alfabética — é assim que o Hakuna está
  /// acostumado a procurar no app oficial, e reordenar faria ele perder a
  /// pessoa que estava buscando. O aviso resolve o outro lado: ninguém
  /// descobre um SpO₂ 88% por acidente, rolando a lista.
  Widget _avisoCriticos() {
    final criticos = _todos.where((p) => _gravidadeDe(p).escalada).toList();
    if (criticos.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.priority_high, color: scheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                criticos.length == 1
                    ? '1 participante com sinal vital crítico aferido: '
                          '${criticos.first.fullName.toUpperCase()}'
                    : '${criticos.length} participantes com sinal vital '
                          'crítico aferido',
                style: TextStyle(
                  color: scheme.onErrorContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Idade dos dados em disco. No mato isso é informação clínica.
  Widget _avisoDados() {
    final quando = _baixadoEm;
    final estilo = Theme.of(context).textTheme.labelMedium;
    if (quando == null) {
      return Material(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              const Icon(Icons.cloud_off, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Dados não baixados para este aparelho. Sem sinal, a lista '
                  'e a leitura de pulseira não vão funcionar.',
                ),
              ),
              TextButton(onPressed: _baixar, child: const Text('Baixar')),
            ],
          ),
        ),
      );
    }
    final horas = DateTime.now().difference(quando);
    final idade = horas.inMinutes < 60
        ? '${horas.inMinutes} min'
        : '${horas.inHours} h';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text('Dados do aparelho · baixados há $idade', style: estilo),
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
    required this.gravidade,
    required this.regras,
    required this.top,
    this.selecionando = false,
    this.marcado = false,
    this.aoMarcar,
  });

  final Participant participante;
  final Gravidade gravidade;
  final List<TriageRule> regras;
  final Top top;
  final bool selecionando;
  final bool marcado;

  /// Null quando quem está olhando não é o admin master — e aí não há
  /// toque longo nem checkbox.
  final VoidCallback? aoMarcar;

  @override
  Widget build(BuildContext context) {
    // Legendário é quem tem número — e quem tem número usa o app. O
    // Senderista existe como registro e não entra.
    final ehLegendario =
        participante.participantCode != null &&
        participante.participantCode!.trim().isNotEmpty;

    final cor = gravidade.cor;

    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        selected: marcado,
        leading: selecionando
            ? Checkbox(
                value: marcado,
                onChanged: aoMarcar == null ? null : (_) => aoMarcar!(),
              )
            : emblemaPara(ehLegendario: ehLegendario),
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
                  message: gravidade.escalada
                      ? 'CRÍTICO · ${gravidade.motivos.join(" · ")}'
                      : 'Triagem: ${cor.label}',
                  child: Icon(
                    // Ícone diferente quando a cor veio do sinal vital e
                    // não do cadastro: cor sozinha não distingue "é idoso
                    // com comorbidade" de "está com SpO₂ 88% agora", e são
                    // prioridades diferentes para quem decide a fila.
                    gravidade.escalada ? Icons.monitor_heart : Icons.flag,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
        onLongPress: aoMarcar,
        onTap: selecionando
            ? aoMarcar
            : () => Navigator.of(context).push(
                MaterialPageRoute<void>(
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

    // O selo TESTE vai no subtítulo e não no nome: o nome é o que o Hakuna
    // procura na busca, e prefixá-lo quebraria a ordem alfabética e a
    // leitura rápida da lista.
    if (!participante.isTeste && partes.isEmpty) return null;

    return Row(
      children: [
        if (participante.isTeste) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.tertiary,
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              'TESTE',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onTertiary,
              ),
            ),
          ),
          const SizedBox(width: 5),
        ],
        Expanded(
          child: Text(
            partes.join(' · '),
            style: Theme.of(context).textTheme.labelSmall,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
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
        MaterialPageRoute<void>(
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
