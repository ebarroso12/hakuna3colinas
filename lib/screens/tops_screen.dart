import 'package:flutter/material.dart';

import '../models/profile.dart';
import '../models/top.dart';
import '../offline/outbox.dart';
import '../services/admin_service.dart';
import '../services/atualizacao_service.dart';
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
class TopsScreen extends StatefulWidget {
  const TopsScreen({super.key});

  @override
  State<TopsScreen> createState() => _TopsScreenState();
}

class _TopsScreenState extends State<TopsScreen> {
  late Future<List<Top>> _topsFuture;
  Profile? _myProfile;

  /// Quantas entradas ainda não subiram, lido uma vez na abertura. Vai
  /// para a gaveta porque atualizar o app pode exigir desinstalar, e
  /// desinstalar apaga a fila — ver [GavetaDoApp].
  int _pendentes = 0;

  /// Se há versão mais nova publicada. Mexe só no ponto sobre a logo; a
  /// gaveta consulta de novo quando é aberta.
  bool _temVersaoNova = false;

  @override
  void initState() {
    super.initState();
    _topsFuture = SupabaseService.instance.fetchMyTops();
    SupabaseService.instance.fetchMyProfile().then((p) {
      if (mounted) setState(() => _myProfile = p);
    });
    _verificarVersao();
    Outbox.instance.pendingCount().then((n) {
      if (mounted) setState(() => _pendentes = n);
    });
  }

  Future<void> _verificarVersao() async {
    final v = await AtualizacaoService.instance.consultar();
    if (!mounted) return;
    // `null` é "não deu para verificar", não "está atualizado" — então o
    // ponto fica apagado, sem afirmar nada.
    setState(() => _temVersaoNova = v?.maisNovaQueEsta ?? false);
  }

  Future<void> _refresh() async {
    setState(() => _topsFuture = SupabaseService.instance.fetchMyTops());
    await _topsFuture;
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
                  MaterialPageRoute(
                    builder: (_) => const ChangePasswordScreen(),
                  ),
                ),
        ),
        actions: [
          if (_myProfile?.role == UserRole.admin ||
              _myProfile?.isMasterAdmin == true)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings_outlined),
              tooltip: 'Administração',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AdminHomeScreen(
                    isMasterAdmin: _myProfile?.isMasterAdmin ?? false,
                  ),
                ),
              ),
            ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'change_password') {
                Navigator.of(context).push(
                  MaterialPageRoute(
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
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Top>>(
          future: _topsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text('Erro ao carregar tops: ${snapshot.error}'),
              );
            }
            final tops = snapshot.data ?? [];
            if (tops.isEmpty) {
              return const Center(child: Text('Nenhum Top vinculado ainda.'));
            }
            return ListView.builder(
              itemCount: tops.length,
              itemBuilder: (context, index) {
                final top = tops[index];
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
                      top.status.name,
                      if (top.location != null) top.location!,
                    ].join(' · '),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TopDetailScreen(top: top),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
