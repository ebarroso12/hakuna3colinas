import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import 'screens/auth_gate.dart';
import 'offline/chat_repositorio.dart';
import 'offline/sync_service.dart';
import 'services/alarme_service.dart';
import 'services/anotacao_service.dart';
import 'services/atendimento_service.dart';
import 'services/auditoria_service.dart';
import 'services/location_service.dart';
import 'services/participante_service.dart';
import 'services/sinais_vitais_service.dart';
import 'services/supabase_service.dart';
import 'widgets/faixa_de_alarme.dart';

/// Credenciais do Supabase são passadas em tempo de build, nunca commitadas:
///   flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=xxxxx
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Recebe o push com o app FECHADO ou em segundo plano.
///
/// `@pragma('vm:entry-point')` é obrigatório: o Android acorda o processo
/// num isolate separado, e sem a anotação o tree-shaking do release
/// remove esta função — o push chegaria e nada aconteceria, só no APK de
/// release, que é o pior lugar para descobrir.
///
/// Fica vazia de propósito. A notificação em si é desenhada pelo próprio
/// Android a partir do bloco `notification` que a Edge Function manda;
/// aqui só caberia trabalho extra, e trabalho em isolate de background
/// com o app fechado é onde se criam travamentos difíceis de reproduzir.
@pragma('vm:entry-point')
Future<void> _pushEmSegundoPlano(RemoteMessage mensagem) async {}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase antes do Supabase: o handler de background precisa estar
  // registrado antes de qualquer push poder chegar.
  //
  // Tolerante a falha de propósito. Sem `google-services.json` ou sem
  // Play Services isto estoura — e o app TEM de abrir mesmo assim. Push
  // é conveniência sobre o alarme que já funciona com a tela aberta;
  // derrubar o app por causa dele seria trocar o essencial pelo
  // acessório.
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(_pushEmSegundoPlano);
  } catch (_) {}

  await SupabaseService.initialize(
    url: _supabaseUrl,
    anonKey: _supabaseAnonKey,
  );

  // Liga a fila offline: atendimentos e fotos registrados sem sinal sobem
  // sozinhos quando a conexao volta.
  AtendimentoService.instance.registrarUploaders();
  LocationService.instance.registrarUploader();
  AuditoriaService.instance.registrarUploaders();
  AlarmeService.instance.registrarUploader();
  SinaisVitaisService.instance.registrarUploader();
  ParticipanteService.instance.registrarUploader();
  AnotacaoService.instance.registrarUploader();
  ChatRepositorio.instance.registrarUploaders();
  unawaited(SyncService.instance.start());

  // Religa o rastreamento se o app deveria estar rastreando e foi morto
  // pelo sistema. Não somos donos do Foreground Service (ele é do plugin
  // geolocator), então não há `START_STICKY` para o Android recriá-lo: é o
  // app, ao abrir, que retoma. Fica um buraco na trilha do tamanho do tempo
  // em que o processo esteve morto — isso é limite da arquitetura, não bug.
  //
  // Depois do runApp seria tarde para a notificação voltar antes da
  // primeira tela; antes dele atrasaria a abertura. Fica solto aqui.
  unawaited(LocationService.instance.retomarSeDevia());

  runApp(const HakunaConnectApp());
}

/// Acesso ao `Navigator` de dentro do `MaterialApp.builder`.
///
/// A faixa de alarme vive no `builder`, que embrulha o Navigator — ou seja,
/// o contexto dela está ACIMA dele. `Navigator.of(context)` dali não acha
/// nada, e `showModalBottomSheet` (o "quem está mais perto") estouraria com
/// "No Navigator widget found". Esta chave é o caminho de volta para
/// dentro.
///
/// É global porque o alarme é global: não pertence a nenhuma tela.
final navegadorDoApp = GlobalKey<NavigatorState>();

class HakunaConnectApp extends StatelessWidget {
  const HakunaConnectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Legendario Connect',
      navigatorKey: navegadorDoApp,
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      // A faixa de alarme fica ACIMA do Navigator, não dentro de uma tela:
      // é o que faz o alarme aparecer onde o Hakuna estiver, em vez de só
      // na tela de detalhe do Top. Ver `FaixaDeAlarme`.
      builder: (context, child) =>
          FaixaDeAlarme(child: child ?? const SizedBox.shrink()),
      home: const AuthGate(),
    );
  }
}
