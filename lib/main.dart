import 'package:flutter/material.dart';

import 'screens/auth_gate.dart';
import 'services/supabase_service.dart';

/// Credenciais do Supabase são passadas em tempo de build, nunca commitadas:
///   flutter run --dart-define=SUPABASE_URL=https://xxx.supabase.co \
///               --dart-define=SUPABASE_ANON_KEY=xxxxx
const _supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const _supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseService.initialize(url: _supabaseUrl, anonKey: _supabaseAnonKey);
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
