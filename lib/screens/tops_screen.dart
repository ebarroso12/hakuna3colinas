import 'package:flutter/material.dart';

import '../models/profile.dart';
import '../models/top.dart';
import '../offline/outbox.dart';
import '../services/acesso_service.dart';
import '../services/admin_service.dart';
import '../services/atualizacao_service.dart';
import '../services/lista_de_tops.dart';
import '../services/supabase_service.dart';
import '../widgets/app_logo.dart';
import '../widgets/barra_inferior.dart';
import '../widgets/cabecalho_usuario.dart';
import '../widgets/gaveta_do_app.dart';
import 'admin/admin_home_screen.dart';
import 'change_password_screen.dart';
import 'top_detail_screen.dart';

/// Lista os "Tops" (eventos) aos quais o usuário logado está vinculado,
/// seja como Hakuna liberado ou como Senderista inscrito.
///
/// Lê do DISCO primeiro e atualiza pela rede por baixo (ver
/// `ListaDeTops`). Era só da rede, e com o servidor fora quem entrava pelo
/// `AuthGate` parava aqui num erro cru, sem caminho até o Top — onde
/// estão EMERGÊNCIA, a leitura da pulseira e os participantes guardados.
class TopsScreen extends StatefulWidget {
  const TopsScreen({super.key});

  @override
  State<TopsScreen> createState() => _TopsScreenState();
}

class _TopsScreenState extends State<TopsScreen> {
  /// Última lista guardada no aparelho para esta conta. Null só até o
  /// disco responder.
  List<Top>? _doDisco;

  /// O que o servidor mandou nesta abertura. Null enquanto não respondeu.
  List<Top>? _daRede;

  /// Falha da última busca na rede. Nunca vai crua para a tela: quem
  /// escolhe a frase é `telaDeTops`.
  Object? _erroDaRede;

  Profile? _myProfile;

  /// Quantas entradas ainda não subiram, lido uma vez na abertura. Vai
  /// para a gaveta porque atualizar o app pode exigir desinstalar, e
  /// desinstalar apaga a fila — ver [GavetaDoApp].
  int _pendentes = 0;

  /// Se há versão mais nova publicada. Mexe só no ponto sobre a logo; a
  /// gaveta consulta de novo quando é aberta.
  bool _temVersaoNova = false;

  /// Nome da versão nova, para a faixa dizer QUAL é ("Versão 1.0.45").
  String? _nomeDaVersaoNova;

  /// Pessoas esperando liberação. Só o admin vê, no ícone de
  /// Administração. Sem este número o pedido chegava e ninguém sabia: a
  /// lista só era vista por quem lembrava de abri-la.
  int _esperandoLiberacao = 0;

  @override
  void initState() {
    super.initState();
    _carregarTops();
    _carregarPerfil();
    _verificarVersao();
    Outbox.instance.pendingCount().then((n) {
      if (mounted) setState(() => _pendentes = n);
    });
  }

  bool get _ehAdmin =>
      _myProfile?.role == UserRole.admin || _myProfile?.isMasterAdmin == true;

  String? get _uid => SupabaseService.instance.currentUserId;

  /// Disco primeiro, rede depois. A lista do disco aparece em
  /// milissegundos; a da rede, quando (e se) vier, a substitui.
  Future<void> _carregarTops() async {
    final uid = _uid;
    final disco = await ListaDeTops.instance.doDisco(uid);
    if (!mounted) return;
    setState(() => _doDisco = disco);
    await _buscarNaRede(uid);
  }

  Future<void> _buscarNaRede(String? uid) async {
    try {
      final tops = await ListaDeTops.instance.daRede(uid);
      if (!mounted) return;
      setState(() {
        _daRede = tops;
        _erroDaRede = null;
      });
    } catch (erro) {
      if (!mounted) return;
      setState(() => _erroDaRede = erro);
    }
  }

  /// Sem servidor, `fetchMyProfile` falha toda vez — e o `.then` sem
  /// tratamento deixava um erro assíncrono solto a cada abertura. Aqui o
  /// perfil fica null: o cabeçalho mostra o que tem, o ícone de
  /// administração some até a rede voltar (sem perfil não se sabe se é
  /// admin, e na dúvida não se mostra), e nada de texto cru na tela.
  Future<void> _carregarPerfil() async {
    try {
      final p = await SupabaseService.instance.fetchMyProfile();
      if (!mounted) return;
      setState(() => _myProfile = p);
    } catch (_) {
      return;
    }
    await _contarEsperando();
  }

  Future<void> _contarEsperando() async {
    if (!_ehAdmin) return;
    try {
      final n = await AcessoService.instance.pendentes();
      if (mounted) setState(() => _esperandoLiberacao = n);
    } catch (_) {
      // Contagem é conveniência: sem rede, o número só não aparece.
    }
  }

  Future<void> _verificarVersao() async {
    final v = await AtualizacaoService.instance.consultar();
    if (!mounted) return;
    // `null` é "não deu para verificar", não "está atualizado" — então o
    // ponto fica apagado, sem afirmar nada.
    setState(() {
      _temVersaoNova = v?.maisNovaQueEsta ?? false;
      _nomeDaVersaoNova = v?.nome;
    });
  }

  Future<void> _refresh() async {
    setState(() {
      // A lista que está na tela continua na tela enquanto a rede não
      // responde: se a nova busca falhar, cai de volta nela com a faixa,
      // em vez de sumir.
      if (_daRede != null) _doDisco = _daRede;
      _daRede = null;
      _erroDaRede = null;
    });
    _contarEsperando();
    await _buscarNaRede(_uid);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: GavetaDoApp(pendentesNaFila: _pendentes),
      appBar: AppBar(
        leading: AppLogoAbreGaveta(novidade: _temVersaoNova),
        title: CabecalhoUsuario(
          perfil: _myProfile,
          aoEditar: _myProfile == null
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ChangePasswordScreen(),
                  ),
                ),
        ),
        actions: [
          if (_ehAdmin)
            IconButton(
              icon: Badge(
                isLabelVisible: _esperandoLiberacao > 0,
                label: Text('$_esperandoLiberacao'),
                child: const Icon(Icons.admin_panel_settings_outlined),
              ),
              tooltip: _esperandoLiberacao > 0
                  ? 'Administração · $_esperandoLiberacao esperando liberação'
                  : 'Administração',
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => AdminHomeScreen(
                      isMasterAdmin: _myProfile?.isMasterAdmin ?? false,
                    ),
                  ),
                );
                // Voltou da administração: quem foi liberado lá sai da
                // conta na hora, sem esperar reabrir o app.
                _contarEsperando();
              },
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'change_password') {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ChangePasswordScreen(),
                  ),
                );
              } else if (value == 'sign_out') {
                SupabaseService.instance.signOut();
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'change_password',
                child: Text('Trocar senha'),
              ),
              PopupMenuItem(value: 'sign_out', child: Text('Sair')),
            ],
          ),
        ],
      ),
      bottomNavigationBar: const BarraInferior(mostrarInicio: false),
      body: Column(
        children: [
          // A versão nova era só um ponto sobre a logo, que ninguém nota —
          // e a base instalada ficava para trás sem saber. Faixa na tela
          // inicial, com o botão: o toque abre a gaveta, onde já está o
          // aviso de sincronizar antes de instalar.
          if (_temVersaoNova)
            Builder(
              builder: (context) => MaterialBanner(
                leading: const Icon(Icons.system_update),
                content: Text(
                  'Versão ${_nomeDaVersaoNova ?? "nova"} disponível. '
                  'Atualize para receber as correções.',
                ),
                actions: [
                  FilledButton(
                    onPressed: () => Scaffold.of(context).openDrawer(),
                    child: const Text('ATUALIZAR'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: Builder(
                builder: (context) {
                  final tela = telaDeTops(
                    doDisco: _doDisco,
                    daRede: _daRede,
                    erroDaRede: _erroDaRede,
                  );
                  if (tela.carregando) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final tops = tela.tops;
                  final aviso = tela.aviso;
                  if (tops.isEmpty) {
                    // ListView, e não Center: o aviso manda puxar para
                    // baixo, e o RefreshIndicator só responde a algo que
                    // rola.
                    return ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(24),
                      children: [
                        if (aviso != null) ...[
                          const Icon(Icons.cloud_off, size: 48),
                          const SizedBox(height: 16),
                        ],
                        Text(
                          aviso ?? 'Nenhum Top vinculado ainda.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    );
                  }
                  // Com lista e aviso, o aviso vai como primeira linha:
                  // curto, e a lista logo abaixo é o que importa.
                  final deslocamento = aviso == null ? 0 : 1;
                  return ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: tops.length + deslocamento,
                    itemBuilder: (context, index) {
                      if (aviso != null && index == 0) {
                        return ListTile(
                          leading: const Icon(Icons.cloud_off),
                          title: Text(aviso),
                          dense: true,
                        );
                      }
                      final top = tops[index - deslocamento];
                      final urlEmblema = AdminService.instance.urlEmblema(
                        top.emblemaPath,
                      );
                      return ListTile(
                        leading: urlEmblema == null
                            ? const CircleAvatar(child: Icon(Icons.terrain))
                            : CircleAvatar(
                                backgroundImage: NetworkImage(urlEmblema),
                                // Emblema que nao carrega nao pode esconder o Top
                                // da lista.
                                onBackgroundImageError: (_, _) {},
                                child: const SizedBox.shrink(),
                              ),
                        title: Text(
                          top.topNumber != null
                              ? 'TOP# ${top.topNumber} · ${top.name}'
                              : top.name,
                        ),
                        subtitle: Text(
                          [
                            // Em português: "draft" na lista de quem não é
                            // programador não diz nada.
                            switch (top.status.name) {
                              'draft' => 'rascunho',
                              'active' => 'em andamento',
                              'finished' => 'encerrado',
                              final outro => outro,
                            },
                            if (top.location != null) top.location!,
                          ].join(' · '),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => TopDetailScreen(top: top),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
