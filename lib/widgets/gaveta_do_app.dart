import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/atualizacao_service.dart';
import '../versao.dart';

/// Gaveta lateral: mostra qual versão está instalada e, quando há uma mais
/// nova publicada, o botão "Atualizar".
///
/// O botão abre o link do APK no navegador — ele **não** instala. Instalação
/// silenciosa exigiria Play Store (ou a permissão de instalar pacotes, que é
/// pior), e o app é distribuído por "fontes desconhecidas".
///
/// SOBRE O AVISO DO DIÁLOGO. Desde a v1.0.23 o CI assina com o keystore de
/// produção (`CN=Legendarios Connect`, SHA-1 `0B:99:...:4B:88`, conferido
/// com `apksigner` nos APKs 1.0.23, 1.0.28 e 1.0.29), então a instalação
/// por cima **funciona** e o SQLite local sobrevive. Antes disso
/// (1.0.18/1.0.19) cada build saía com uma chave de debug diferente e
/// atualizar exigia desinstalar.
///
/// O diálogo ainda fala da fila porque o caso ruim não desapareceu, só
/// ficou improvável: se por algum motivo a assinatura não casar, o Android
/// recusa com "aplicativo não instalado", a saída é desinstalar, e
/// desinstalar apaga a fila — ou seja, atendimento que ainda não subiu. Em
/// campo isso é perda de dado clínico, e vale o parágrafo.
class GavetaDoApp extends StatefulWidget {
  const GavetaDoApp({super.key, this.pendentesNaFila});

  /// Quantas entradas ainda não subiram. Serve para endurecer o aviso
  /// quando há dado clínico em risco; `null` quando quem abriu a gaveta
  /// não tem essa informação.
  final int? pendentesNaFila;

  @override
  State<GavetaDoApp> createState() => _GavetaDoAppState();
}

class _GavetaDoAppState extends State<GavetaDoApp> {
  VersaoPublicada? _publicada;
  bool _consultando = false;
  bool _consultou = false;

  @override
  void initState() {
    super.initState();
    // Abre já com o que se sabia, em vez de piscar "verificando" a cada
    // vez que o usuário abre a gaveta.
    _publicada = AtualizacaoService.instance.ultimaConhecida;
    if (!AtualizacaoService.atualizaPeloTestFlight) _verificar();
  }

  Future<void> _verificar() async {
    setState(() => _consultando = true);
    final v = await AtualizacaoService.instance.consultar();
    if (!mounted) return;
    setState(() {
      _publicada = v;
      _consultando = false;
      _consultou = true;
    });
  }

  Future<void> _atualizar(VersaoPublicada v) async {
    final pendentes = widget.pendentesNaFila ?? 0;
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Atualizar para ${v.nome}?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (v.notas != null && v.notas!.isNotEmpty) ...[
              Text(v.notas!),
              const SizedBox(height: 16),
            ],
            const Text(
              'O download abre no navegador. Depois de baixar, toque no '
              'arquivo para instalar — ele instala por cima e mantém seus '
              'dados.',
            ),
            const SizedBox(height: 12),
            if (pendentes > 0)
              Text(
                'Você tem $pendentes registro(s) ainda não enviados. Se a '
                'instalação reclamar de "aplicativo não instalado", a saída '
                'é desinstalar — e desinstalar APAGA esses registros. '
                'Sincronize antes de atualizar.',
                style: TextStyle(
                  color: Theme.of(ctx).colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
              )
            else
              const Text(
                'Se a instalação reclamar de "aplicativo não instalado", é '
                'preciso desinstalar a versão antiga primeiro — e '
                'desinstalar apaga o que estiver na fila.',
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
            child: const Text('Baixar'),
          ),
        ],
      ),
    );
    if (confirmou != true) return;

    final uri = Uri.tryParse(v.apkUrl);
    final abriu =
        uri != null &&
        await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!abriu && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível abrir ${v.apkUrl}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    final publicada = _publicada;
    final desatualizado = publicada?.maisNovaQueEsta ?? false;
    final peloTestFlight = AtualizacaoService.atualizaPeloTestFlight;

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  DrawerHeader(
                    decoration: BoxDecoration(color: cores.primaryContainer),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          'Legendário Connect',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(color: cores.onPrimaryContainer),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Versão ${Versao.completa}',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: cores.onPrimaryContainer),
                        ),
                      ],
                    ),
                  ),

                  ListTile(
                    leading: Icon(
                      desatualizado
                          ? Icons.system_update
                          : Icons.verified_outlined,
                      color: desatualizado ? cores.error : null,
                    ),
                    title: Text(
                      desatualizado
                          ? 'Versão ${publicada!.nome} disponível'
                          : 'Versão instalada: ${Versao.completa}',
                    ),
                    subtitle: Text(_legenda()),
                    trailing: peloTestFlight
                        ? null
                        : _consultando
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : IconButton(
                            icon: const Icon(Icons.refresh),
                            tooltip: 'Verificar agora',
                            onPressed: _verificar,
                          ),
                  ),

                  if (desatualizado)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: FilledButton.icon(
                        onPressed: () => _atualizar(publicada!),
                        icon: const Icon(Icons.download),
                        label: const Text('ATUALIZAR'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                peloTestFlight
                    ? 'No iPhone, o app é instalado e atualizado pelo '
                          'TestFlight.'
                    : 'Instalação por "fontes desconhecidas". O app não está '
                          'na Play Store.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Três estados, e o terceiro não é "atualizado".
  ///
  /// Sem rede a consulta devolve `null`, e afirmar "você está na última"
  /// nesse caso seria inventar: o app não sabe. Dizer que não deu para
  /// verificar é o que de fato aconteceu.
  String _legenda() {
    if (AtualizacaoService.atualizaPeloTestFlight) {
      return 'Versão nova chega pelo TestFlight, que avisa sozinho.';
    }
    final v = _publicada;
    if (v == null) {
      return _consultou
          ? 'Não foi possível verificar — sem conexão?'
          : 'Verificando...';
    }
    if (v.maisNovaQueEsta) {
      return 'Você está na ${Versao.nome}. Toque em ATUALIZAR.';
    }
    return 'Esta é a versão mais recente publicada.';
  }
}
