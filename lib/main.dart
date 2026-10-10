import 'dart:async';

import 'package:flutter/material.dart';

import 'screens/auth_gate.dart';
import 'offline/sync_service.dart';
import 'services/atendimento_service.dart';
import 'services/location_service.dart';
import 'services/supabase_service.dart';

/// Credenciais do Supabase são passadas em tempo de build, nunca commitadas:
///   flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=xxxxx
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.initialize(
    url: _supabaseUrl,
    anonKey: _supabaseAnonKey,
  );

  // Liga a fila offline: atendimentos e fotos registrados sem sinal sobem
  // sozinhos quando a conexao volta.
  AtendimentoService.instance.registrarUploaders();
  LocationService.instance.registrarUploader();
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

class HakunaConnectApp extends StatelessWidget {
  const HakunaConnectApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hakuna Connect',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const AuthGate(),
    );
  }
}
