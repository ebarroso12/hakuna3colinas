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
  if (_supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty) {
    // Sem isso, o app tentava logar sem URL configurada e o Supabase
    // devolvia um "404 empty response" — indistinguível de um erro de
    // rede real, então trocamos por uma tela que aponta a causa certa.
    runApp(const _MissingSupabaseConfigApp());
    return;
  }
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

class _MissingSupabaseConfigApp extends StatelessWidget {
  const _MissingSupabaseConfigApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hakuna Connect',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.settings_outlined, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Supabase não configurado',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'SUPABASE_URL e/ou SUPABASE_ANON_KEY não foram passados '
                  'na build. Rode com:',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const SelectableText(
                    'flutter run \\\n'
                    '  --dart-define=SUPABASE_URL=https://SEU-PROJETO.supabase.co \\\n'
                    '  --dart-define=SUPABASE_ANON_KEY=SUA_ANON_KEY',
                    style: TextStyle(fontFamily: 'monospace', fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
