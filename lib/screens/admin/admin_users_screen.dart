import 'package:flutter/material.dart';

import '../../models/profile.dart';
import '../../services/admin_service.dart';
import '../../services/exclusao_service.dart';
import '../../widgets/app_logo.dart';
import '../../widgets/barra_de_selecao.dart';
import '../../widgets/botao_inicio.dart';
import 'admin_user_edit_screen.dart';

/// Lista de todos os usuários do app, pra gestão de papéis/atribuições
/// pelo admin. A linha do admin master aparece travada (cadeado) pra quem
/// não é o próprio admin master — o banco já bloqueia a edição via RLS,
/// isso aqui só evita abrir uma tela que só vai dar erro.
///
/// Para o admin master há **seleção múltipla com exclusão**: toque longo
/// em um nome entra no modo de seleção, e daí é marcar nome a nome. A
/// exclusão não é um `delete` daqui — ver [ExclusaoService.apagarUsuarios]
/// para o motivo.
class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key, required this.isMasterAdmin});

  final bool isMasterAdmin;

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  late Future<List<Profile>> _future;

  /// Ids marcados. Vazio = fora do modo de seleção.
  final Set<String> _marcados = {};

  /// Nomes dos marcados, para o diálogo poder listar quem sai.
  final Map<String, String> _nomes = {};

  bool _apagando = false;

  @override
  void initState() {
    super.initState();
    _future = AdminService.instance.fetchAllProfiles();
  }

  void _reload() => setState(() {
    _marcados.clear();
    _nomes.clear();
    _future = AdminService.instance.fetchAllProfiles();
  });

  Future<void> _approve(Profile profile) async {
    try {
      await AdminService.instance.approveProfile(profile.id);
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Não foi possível aprovar: $e')));
    }
  }

  void _alternar(Profile p) {
    setState(() {
      if (_marcados.remove(p.id)) {
        _nomes.remove(p.id);
      } else {
        _marcados.add(p.id);
        _nomes[p.id] = p.displayLabel;
      }
    });
  }

  /// Marca todos os que a tela deixaria marcar.
  ///
  /// Pula o admin master: ele nunca pode ser apagado, e marcá-lo só para o
  /// diálogo depois dizer que não dá é fazer o usuário trabalhar de graça.
  void _marcarTodos(List<Profile> profiles) {
    setState(() {
      for (final p in profiles) {
        if (p.isMasterAdmin) continue;
        _marcados.add(p.id);
        _nomes[p.id] = p.displayLabel;
      }
    });
  }

  Future<void> _apagar() async {
    final ids = _marcados.toList();
    setState(() => _apagando = true);
    try {
      // Confere ANTES de confirmar: o diálogo mostra nome por nome quem
      // sai e quem fica, com o motivo. Apagar o que der e avisar depois é
      // o caminho que faz alguém perder dado sem perceber.
      final deps = await ExclusaoService.instance.dependenciasDePerfis(ids);
      if (!mounted) return;

      final decisao = await confirmarExclusao(
        context,
        nomes: {for (final id in ids) id: _nomes[id] ?? id},
        dependencias: deps,
        // Usuário não tem "desativar" hoje: `approved = false` prende a
        // pessoa na tela de aguardando aprovação, o que é outra coisa.
        // Prometer um botão que faz algo diferente do que diz seria pior
        // que não ter.
        podeDesativar: false,
      );
      if (decisao != DecisaoDaExclusao.apagar) return;

      final r = await ExclusaoService.instance.apagarUsuarios(
        // Manda só os liberados: os bloqueados o servidor recusaria de
        // novo, e a lista de recusados ficaria poluída com o que a tela
        // já tinha explicado.
        ids.where((id) => deps[id]?.podeApagar ?? false).toList(),
      );
      if (!mounted) return;

      final msg = r.recusados.isEmpty
          ? '${r.apagados.length} usuário(s) apagado(s).'
          : '${r.apagados.length} apagado(s); '
                '${r.recusados.length} recusado(s) pelo servidor.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 5)),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ExclusaoService.mensagemDeErro(e)),
          duration: const Duration(seconds: 8),
        ),
      );
    } finally {
      if (mounted) setState(() => _apagando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selecionando = _marcados.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Usuários'),
        actions: const [BotaoInicio(), AppLogoTrailing()],
        // A barra de seleção entra como `bottom` e não no lugar do título:
        // assim a seta de voltar e o botão de início continuam ali. Numa
        // tela que apaga gente, a saída não pode desaparecer.
        bottom: selecionando
            ? PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: FutureBuilder<List<Profile>>(
                  future: _future,
                  builder: (context, snap) => BarraDeSelecao(
                    marcados: _marcados.length,
                    total: (snap.data ?? [])
                        .where((p) => !p.isMasterAdmin)
                        .length,
                    aoMarcarTodos: () => _marcarTodos(snap.data ?? []),
                    aoLimpar: () => setState(() {
                      _marcados.clear();
                      _nomes.clear();
                    }),
                    aoApagar: _apagando ? () {} : _apagar,
                  ),
                ),
              )
            : null,
      ),
      body: FutureBuilder<List<Profile>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Erro ao carregar: ${snapshot.error}'));
          }
          // Pendentes de aprovação primeiro — é a fila que o admin master
          // precisa ver de cara toda vez que abre a tela.
          final profiles = [...snapshot.data ?? []]
            ..sort(
              (a, b) => a.approved == b.approved ? 0 : (a.approved ? 1 : -1),
            );
          return Column(
            children: [
              if (widget.isMasterAdmin && !selecionando)
                const _DicaDeSelecao(
                  texto: 'Toque e segure um nome para marcar e apagar.',
                ),
              Expanded(
                child: ListView.builder(
                  itemCount: profiles.length,
                  itemBuilder: (context, index) {
                    final profile = profiles[index];
                    final locked =
                        profile.isMasterAdmin && !widget.isMasterAdmin;
                    final marcado = _marcados.contains(profile.id);
                    // Só o admin master seleciona, e nunca a si mesmo.
                    final podeMarcar =
                        widget.isMasterAdmin && !profile.isMasterAdmin;

                    return ListTile(
                      selected: marcado,
                      leading: selecionando
                          ? Checkbox(
                              value: marcado,
                              onChanged: podeMarcar
                                  ? (_) => _alternar(profile)
                                  : null,
                            )
                          : null,
                      title: Text(profile.displayLabel),
                      subtitle: Text(
                        profile.isMasterAdmin
                            ? 'Admin Master'
                            : '${profile.role.name}'
                                  '${profile.approved ? '' : ' · pendente de aprovação'}',
                        style: profile.approved
                            ? null
                            : const TextStyle(
                                color: Colors.orange,
                                fontWeight: FontWeight.bold,
                              ),
                      ),
                      trailing: selecionando
                          ? null
                          : (!profile.approved
                                ? FilledButton(
                                    onPressed: () => _approve(profile),
                                    child: const Text('Aprovar'),
                                  )
                                : (locked
                                      ? const Icon(Icons.lock_outline)
                                      : const Icon(Icons.chevron_right))),
                      onLongPress: podeMarcar ? () => _alternar(profile) : null,
                      onTap: selecionando
                          ? (podeMarcar ? () => _alternar(profile) : null)
                          : (locked
                                ? null
                                : () async {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) => AdminUserEditScreen(
                                          profile: profile,
                                          isMasterAdmin: widget.isMasterAdmin,
                                        ),
                                      ),
                                    );
                                    _reload();
                                  }),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DicaDeSelecao extends StatelessWidget {
  const _DicaDeSelecao({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(texto, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}
