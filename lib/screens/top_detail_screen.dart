import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/hakuna_position.dart';
import '../models/profile.dart';
import '../models/top.dart';
import '../offline/outbox.dart';
import '../offline/sync_service.dart';
import '../services/alarme_service.dart';
import '../services/location_service.dart';
import '../services/nfc_service.dart';
import '../services/stats_service.dart';
import '../services/supabase_service.dart';
import '../widgets/barra_inferior.dart';
import '../widgets/botao_inicio.dart';
import 'admin/admin_equipes_screen.dart';
import 'admin/admin_importar_screen.dart';
import 'admin/admin_mapa_permissoes_screen.dart';
import 'admin/admin_tags_screen.dart';
import 'admin/admin_top_form_screen.dart';
import 'fila_offline_screen.dart';
import 'ler_tag_screen.dart';
import 'mapa_top_screen.dart';
import 'participants_list_screen.dart';
import 'team_chats_screen.dart';
import 'top_chat_screen.dart';
import 'top_senderistas_screen.dart';

class TopDetailScreen extends StatefulWidget {
  const TopDetailScreen({super.key, required this.top});

  final Top top;

  @override
  State<TopDetailScreen> createState() => _TopDetailScreenState();
}

class _TopDetailScreenState extends State<TopDetailScreen> {
  Profile? _myProfile;
  Map<String, Profile> _hakunaProfiles = {};
  bool _tracking = false;
  String? _nfcMessage;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadHakunaProfiles();
  }

  bool _profileLoadFailed = false;

  Future<void> _loadProfile() async {
    try {
      final profile = await SupabaseService.instance.fetchMyProfile();
      if (mounted) setState(() => _myProfile = profile);
    } catch (_) {
      if (mounted) setState(() => _profileLoadFailed = true);
    }
  }

  /// Nomes + número do Legendários dos Hakunas do Top, pra identificar quem
  /// é quem na lista de posições. Falha aqui não é crítica — a lista de
  /// posições cai de volta pro id cru, então só tenta uma vez.
  Future<void> _loadHakunaProfiles() async {
    try {
      final profiles = await SupabaseService.instance.fetchHakunaProfiles(
        widget.top.id,
      );
      if (mounted) setState(() => _hakunaProfiles = profiles);
    } catch (_) {
      // segue sem os nomes; a lista mostra o id cru como fallback
    }
  }

  Future<void> _toggleTracking() async {
    if (_tracking) {
      await LocationService.instance.stopTracking();
      if (!mounted) return;
      setState(() => _tracking = false);
      return;
    }
    try {
      await LocationService.instance.startTracking(
        widget.top.id,
        // Erros que chegam DEPOIS que o rastreamento já começou (GPS
        // desligado, permissão revogada, sessão expirada) caem aqui, não
        // no catch abaixo — o LocationService já para o rastreamento.
        onError: (error) {
          if (!mounted) return;
          setState(() => _tracking = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Rastreamento interrompido: $error')),
          );
        },
      );
      if (!mounted) return;
      setState(() => _tracking = true);
      await _ofereceLiberarSegundoPlano();
    } catch (e) {
      // Duas causas bem diferentes pro mesmo erro: GPS desligado no sistema
      // (resolve em Configurações > Localização) ou permissão do app negada
      // (resolve em Configurações > Apps > Legendario Connect). Cada uma abre
      // uma tela do Android diferente — misturar as duas confunde o usuário.
      final serviceDisabled = await LocationService.instance
          .isLocationServiceDisabled();
      if (!mounted) return;
      if (serviceDisabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Localização (GPS) está desligada no aparelho. Ative para compartilhar sua posição.',
            ),
            action: SnackBarAction(
              label: 'Abrir',
              onPressed: Geolocator.openLocationSettings,
            ),
          ),
        );
        return;
      }
      final deniedForever = await LocationService.instance
          .isPermissionDeniedForever();
      if (!mounted) return;
      if (deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Permissão de localização negada. Abra as Configurações do app para liberar.',
            ),
            action: SnackBarAction(
              label: 'Abrir',
              onPressed: Geolocator.openAppSettings,
            ),
          ),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível iniciar o rastreamento: $e')),
      );
    }
  }

  /// Depois que o rastreamento já começou, oferece liberar "Permitir o
  /// tempo todo".
  ///
  /// A ordem importa: o Android só mostra essa opção depois que a permissão
  /// básica foi concedida, e pedir antes de o usuário ver o rastreamento
  /// funcionando é o caminho mais curto para ele negar. Por isso é um
  /// convite, não um bloqueio — sem essa permissão o rastreamento continua
  /// funcionando pela notificação fixa; ela é a rede de segurança para
  /// aparelhos com economia de bateria agressiva.
  Future<void> _ofereceLiberarSegundoPlano() async {
    if (await LocationService.instance.hasBackgroundPermission()) return;
    if (!mounted) return;

    final liberar = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Manter o rastreamento na trilha'),
        content: const Text(
          'Sua posição já está sendo compartilhada.\n\n'
          'Alguns aparelhos cortam o GPS quando a tela fica muito tempo '
          'bloqueada, e aí sua trilha fica congelada no último ponto.\n\n'
          'Para evitar isso, marque "Permitir o tempo todo" na permissão de '
          'localização do app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Agora não'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Abrir Configurações'),
          ),
        ],
      ),
    );

    if (liberar ?? false) {
      await LocationService.instance.openSettingsForBackground();
    }
  }

  /// Dispara o sinal de alarme (acidente/atendimento crítico) pro Top. Pede
  /// confirmação — é uma ação séria que avisa todos os Hakunas liberados —
  /// e anexa a posição atual quando disponível, pra ajudar a localizar
  /// quem precisa de ajuda.
  Future<void> _sendAlert() async {
    final messageController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Disparar sinal de alarme?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // O texto dizia "todos os Hakunas liberados" e isso ficou
            // falso duas vezes: a RLS abriu para qualquer equipe na
            // v1.0.35 e agora o alarme vai para TODO o Top. Prometer
            // menos gente do que de fato recebe faz quem dispara achar
            // que precisa avisar os outros por fora.
            const Text(
              'Avisa TODO MUNDO neste Top agora, com a sua posição no GPS '
              'e o seu nome. Use só em acidente ou atendimento crítico.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: messageController,
              decoration: const InputDecoration(
                labelText: 'O que está acontecendo? (opcional)',
              ),
              minLines: 1,
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Disparar alarme'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    double? lat;
    double? lng;
    try {
      final position = await Geolocator.getCurrentPosition();
      lat = position.latitude;
      lng = position.longitude;
    } catch (_) {
      // segue sem posição — o alarme em si é mais importante que a localização
    }

    try {
      await AlarmeService.instance.disparar(
        topId: widget.top.id,
        mensagem: messageController.text.trim().isEmpty
            ? null
            : messageController.text.trim(),
        latitude: lat,
        longitude: lng,
      );
      if (!mounted) return;
      // O alarme está GRAVADO no aparelho neste ponto, mesmo sem rede. A
      // mensagem não pode dizer "enviado", porque pode não ter saído — e
      // não pode dizer "falhou", porque não falhou. Diz o que é verdade e
      // o que fazer a respeito.
      final pendentes = await Outbox.instance.pendingCount(
        entity: AlarmeService.entidade,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 6),
          content: Text(
            pendentes == 0
                ? 'Alarme disparado para TODO o Top, com a sua posição.'
                : 'Alarme GRAVADO e aguardando sinal. Ele sobe sozinho '
                      'quando a rede voltar — não conte com ele agora, use '
                      'o rádio.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      // Só chega aqui por sessão expirada ou falha de disco. Falta de
      // rede não cai mais neste catch — o alarme fica na fila.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível registrar o alarme: $e')),
      );
    }
  }

  Future<void> _readNfc() async {
    setState(() => _nfcMessage = 'Aproxime a tag...');
    try {
      final text = await NfcService.instance.readTagText();
      if (!mounted) return;
      setState(() => _nfcMessage = text ?? 'Tag sem texto NDEF legível.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _nfcMessage = 'Erro na leitura: $e');
    }
  }

  @override
  void dispose() {
    // Checa o estado real do serviço (LocationService.instance.isTracking),
    // não a flag local: se a tela for fechada enquanto startTracking()
    // ainda está em andamento, _tracking pode estar false mesmo com o
    // rastreamento já ativo no serviço.
    if (LocationService.instance.isTracking) {
      LocationService.instance.stopTracking();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isHakuna =
        _myProfile?.role == UserRole.hakuna ||
        _myProfile?.role == UserRole.admin;
    final podeEditarTop =
        _myProfile?.role == UserRole.admin || _myProfile?.isMasterAdmin == true;

    return Scaffold(
      // Sem `leading`: o Flutter coloca a seta de voltar sozinho. A logo foi
      // pro fim das actions — antes ela ocupava o leading e prendia o
      // usuario dentro do Top, sem como voltar pra lista.
      appBar: AppBar(
        title: Text(widget.top.name),
        // SETE acoes e o teto num celular de 360 dp — medido, nao
        // estimado: a oitava faz a Row da AppBar estourar e o Flutter
        // **corta em silencio** o que passa da borda. Com 11 acoes, o admin
        // nao alcancava Pulseiras, Equipes nem Quem-ve-o-mapa: os botoes
        // existiam, respondiam a teste e eram invisiveis no aparelho.
        //
        // O que fica como icone e o que se usa com o paciente na frente:
        // ler a pulseira, mapa, lista, fila, chat. O resto vai para o menu,
        // com nome escrito — mais achavel que um icone a adivinhar.
        // `test/appbar_cabe_no_celular_test.dart` trava o teto.
        actions: [
          const BotaoInicio(),
          // Primeiro icone depois da saida, de proposito: e o celular que
          // encosta na pulseira, e identificar o paciente e o caminho mais
          // curto que esta tela precisa ter. Antes estava dois toques
          // fundo, dentro de Participantes.
          IconButton(
            icon: const Icon(Icons.nfc),
            tooltip: 'Ler tag / QR da pulseira',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => LerTagScreen(top: widget.top),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.map_outlined),
            tooltip: 'Mapa do Top',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => MapaTopScreen(
                  top: widget.top,
                  hakunaProfiles: _hakunaProfiles,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.groups),
            tooltip: 'Participantes do Top',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ParticipantsListScreen(top: widget.top),
              ),
            ),
          ),
          // Fila do aparelho. Badge vermelho quando ha registro recusado:
          // quarentena sem ninguem saber e perda silenciosa de dado, e um
          // atendimento recusado tem de incomodar quem escreveu.
          _BotaoFilaOffline(),
          IconButton(
            icon: const Icon(Icons.forum_outlined),
            tooltip: 'Chats do Top',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => TeamChatsScreen(top: widget.top),
              ),
            ),
          ),
          _MenuDoTop(
            top: widget.top,
            isHakuna: isHakuna,
            podeEditarTop: podeEditarTop,
            hakunaProfiles: _hakunaProfiles,
          ),
        ],
      ),
      bottomNavigationBar: BarraInferior(
        // Editar o Top e so pra quem administra. Coordenador de equipe
        // edita a equipe dele, nao o Top — por isso aqui e admin/master.
        aoEditar: podeEditarTop
            ? () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AdminTopFormScreen(top: widget.top),
                ),
              )
            : null,
        rotuloEditar: 'Editar Top',
      ),
      body: Column(
        children: [
          if (_profileLoadFailed)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Não foi possível carregar seu perfil. Verifique a internet.',
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() => _profileLoadFailed = false);
                      _loadProfile();
                    },
                    child: const Text('Tentar de novo'),
                  ),
                ],
              ),
            ),
          // EMERGENCIA E DE TODOS, sem `if` nenhum. Decisao do dono em
          // 11/10/2026: "se alguma pessoa apertar emergencia todos devem
          // ver o lugar via GPS e quem esta chamando".
          //
          // Estava sob `if (isHakuna)` — ou seja, so Hakuna e admin. A
          // RLS havia sido aberta na v1.0.35 para `pertence_ao_top()`, e a
          // UI nunca foi: o membro da SEGURANCA, cuja funcao e exatamente
          // ver acidente, nao tinha o botao. O `CLAUDE.md` afirmava
          // "membro liberado de qualquer equipe" descrevendo a INTENCAO,
          // nao o app. Quem ve o acidente e quem esta por perto.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              onPressed: _sendAlert,
              icon: const Icon(Icons.warning_amber),
              label: const Text(
                'EMERGÊNCIA — acidente / atendimento crítico',
              ),
            ),
          ),
          // Compartilhar posicao tambem era so de Hakuna, e isso esvaziava
          // o alarme pela raiz: sem ninguem publicando ponto, "quem esta
          // mais perto" nao tem a quem responder e o GPS do socorro nao
          // existe. A RLS de INSERT em `hakuna_positions` sempre aceitou
          // qualquer um logado ("quem caminha gera o ponto").
          Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              onPressed: widget.top.status.name == 'active'
                  ? _toggleTracking
                  : null,
              icon: Icon(_tracking ? Icons.location_off : Icons.location_on),
              label: Text(
                _tracking
                    ? 'Parar de compartilhar posição'
                    : 'Compartilhar minha posição',
              ),
            ),
          ),
          if (isHakuna)
            _MyStatsCard(topId: widget.top.id, weightKg: _myProfile?.weightKg),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _readNfc,
                    icon: const Icon(Icons.nfc),
                    label: const Text('Ler tag NFC'),
                  ),
                ),
              ],
            ),
          ),
          if (_nfcMessage != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_nfcMessage!),
            ),
          const Divider(),
          Expanded(
            child: StreamBuilder<List<HakunaPosition>>(
              stream: SupabaseService.instance.watchTopPositions(widget.top.id),
              builder: (context, snapshot) {
                final positions = snapshot.data ?? [];
                if (positions.isEmpty) {
                  return const Center(
                    child: Text('Nenhuma posição de Hakuna disponível ainda.'),
                  );
                }
                return ListView.builder(
                  itemCount: positions.length,
                  itemBuilder: (context, index) {
                    final p = positions[index];
                    final label =
                        _hakunaProfiles[p.profileId]?.displayLabel ??
                        p.profileId;
                    return ListTile(
                      leading: const Icon(Icons.medical_services),
                      title: Text(label),
                      subtitle: Text(
                        'lat: ${p.latitude.toStringAsFixed(5)}, lng: ${p.longitude.toStringAsFixed(5)}\n'
                        'atualizado às ${p.recordedAt.toLocal()}',
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Distância percorrida, velocidade média e gasto calórico estimado do
/// próprio Hakuna no Top, calculados localmente a partir da trilha de GPS
/// já salva em hakuna_positions — sem nenhuma API externa.
class _MyStatsCard extends StatelessWidget {
  const _MyStatsCard({required this.topId, required this.weightKg});

  final String topId;
  final double? weightKg;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<HakunaPosition>>(
      stream: SupabaseService.instance.watchMyPositionHistory(topId),
      builder: (context, snapshot) {
        final positions = snapshot.data ?? [];
        final stats = StatsService.compute(positions, weightKg: weightKg);
        if (positions.length < 2) return const SizedBox.shrink();

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _StatItem(
                      icon: Icons.route,
                      label: 'Distância',
                      value: '${stats.distanceKm.toStringAsFixed(2)} km',
                    ),
                    _StatItem(
                      icon: Icons.speed,
                      label: 'Vel. média',
                      value: '${stats.avgSpeedKmh.toStringAsFixed(1)} km/h',
                    ),
                    _StatItem(
                      icon: Icons.local_fire_department,
                      label: 'Calorias*',
                      value: '${stats.calories.round()} kcal',
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  stats.caloriesIsEstimate
                      ? '* estimativa aproximada (informe seu peso no perfil pra ficar mais precisa)'
                      : '* estimativa aproximada',
                  style: Theme.of(context).textTheme.labelSmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20),
        const SizedBox(height: 4),
        Text(value, style: Theme.of(context).textTheme.titleMedium),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

/// Botao da fila do aparelho, com badge quando ha registro recusado.
///
/// Stateful e com o proprio Future porque a contagem muda sozinha — o
/// SyncService roda em segundo plano — e nao faria sentido reconstruir a
/// tela inteira do Top por causa disso.
class _BotaoFilaOffline extends StatefulWidget {
  @override
  State<_BotaoFilaOffline> createState() => _BotaoFilaOfflineState();
}

class _BotaoFilaOfflineState extends State<_BotaoFilaOffline> {
  int _recusados = 0;
  int _pendentes = 0;
  StreamSubscription<SyncStatus>? _sub;

  @override
  void initState() {
    super.initState();
    _contar();
    // Reconta quando o sync muda de estado, em vez de ficar consultando o
    // banco em timer e gastando bateria numa trilha de horas.
    _sub = SyncService.instance.statusStream.listen((_) => _contar());
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _contar() async {
    try {
      final recusados = await Outbox.instance.quarantinedCount();
      final pendentes = await Outbox.instance.pendingCount();
      if (!mounted) return;
      setState(() {
        _recusados = recusados;
        _pendentes = pendentes;
      });
    } catch (_) {
      // Sem banco local a tela do Top continua funcionando.
    }
  }

  @override
  Widget build(BuildContext context) {
    final temRecusado = _recusados > 0;
    final botao = IconButton(
      icon: Icon(temRecusado ? Icons.cloud_off : Icons.cloud_queue),
      tooltip: temRecusado
          ? '$_recusados registro(s) recusado(s) pelo servidor'
          : _pendentes > 0
          ? '$_pendentes registro(s) esperando sinal'
          : 'Fila do aparelho',
      onPressed: () async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const FilaOfflineScreen()),
        );
        await _contar();
      },
    );

    if (!temRecusado && _pendentes == 0) return botao;

    return Badge(
      label: Text('${temRecusado ? _recusados : _pendentes}'),
      backgroundColor: temRecusado
          ? Theme.of(context).colorScheme.error
          : Theme.of(context).colorScheme.secondary,
      child: botao,
    );
  }
}

/// Menu do Top: o que nao se usa com o paciente na frente.
///
/// Separado em widget para o `build` da tela nao crescer e para cada item
/// carregar o motivo de estar aqui e nao na barra. A regra de corte e
/// "quantas vezes isto e tocado durante a trilha": emitir pulseira e
/// montar equipe se faz sentado, antes do evento.
class _MenuDoTop extends StatelessWidget {
  const _MenuDoTop({
    required this.top,
    required this.isHakuna,
    required this.podeEditarTop,
    required this.hakunaProfiles,
  });

  final Top top;
  final bool isHakuna;
  final bool podeEditarTop;
  final Map<String, Profile> hakunaProfiles;

  void _abrir(BuildContext context, Widget Function() tela) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => tela()));
  }

  @override
  Widget build(BuildContext context) {
    // Membro de midia ou producao nao e Hakuna nem admin: para ele o menu
    // nao tem UM item. `PopupMenuButton.showButtonMenu` protege com
    // `if (items.isNotEmpty)`, entao o botao aparecia, respondia ao toque
    // e nao fazia nada — que e pior que nao existir. Achado por revisao
    // em 11/10/2026.
    if (!isHakuna && !podeEditarTop) return const SizedBox.shrink();

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      tooltip: 'Mais opcoes do Top',
      onSelected: (valor) {
        switch (valor) {
          case 'vitais':
            _abrir(context, () => TopSenderistasScreen(top: top));
          case 'chat_hakunas':
            _abrir(
              context,
              () => TopChatScreen(top: top, hakunaProfiles: hakunaProfiles),
            );
          case 'pulseiras':
            _abrir(context, () => AdminTagsScreen(top: top));
          case 'equipes':
            _abrir(
              context,
              () => AdminEquipesScreen(top: top, souAdmin: true),
            );
          case 'mapa_permissoes':
            _abrir(context, () => AdminMapaPermissoesScreen(top: top));
          case 'importar':
            _abrir(context, () => AdminImportarScreen(top: top));
        }
      },
      itemBuilder: (context) => [
        if (isHakuna)
          const PopupMenuItem(
            value: 'vitais',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.monitor_heart),
              title: Text('Sinais vitais'),
            ),
          ),
        if (isHakuna)
          const PopupMenuItem(
            value: 'chat_hakunas',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.medical_services_outlined),
              title: Text('Chat com os Hakunas'),
            ),
          ),
        if (isHakuna && podeEditarTop) const PopupMenuDivider(),
        if (podeEditarTop)
          const PopupMenuItem(
            value: 'pulseiras',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.style_outlined),
              title: Text('Emitir pulseiras'),
              subtitle: Text('gravar e revogar tag'),
            ),
          ),
        if (podeEditarTop)
          const PopupMenuItem(
            value: 'equipes',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.groups_2_outlined),
              title: Text('Equipes do Top'),
            ),
          ),
        if (podeEditarTop)
          const PopupMenuItem(
            value: 'mapa_permissoes',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.visibility_outlined),
              title: Text('Quem ve o mapa'),
            ),
          ),
        if (podeEditarTop)
          const PopupMenuItem(
            value: 'importar',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.table_view_outlined),
              title: Text('Importar lista'),
              subtitle: Text('planilha CSV, XLSX ou TXT'),
            ),
          ),
      ],
    );
  }
}
