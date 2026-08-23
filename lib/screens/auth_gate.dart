import 'package:flutter/material.dart';

import '../services/supabase_service.dart';
import 'login_screen.dart';
import 'tops_screen.dart';

/// Decide entre tela de login e tela principal reagindo a mudanças reais
/// de sessão (login, logout, expiração de token) — sem precisar de
/// navegação manual em cada tela que faz signOut/signIn.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: SupabaseService.instance.authStateChanges,
      builder: (context, snapshot) {
        final isLoggedIn = SupabaseService.instance.currentUser != null;
        return isLoggedIn ? const TopsScreen() : const LoginScreen();
      },
    );
  }
}
