import 'package:flutter/material.dart';

import '../services/alarme_service.dart';
import '../services/supabase_service.dart';
import 'login_screen.dart';
import 'pending_approval_screen.dart';
import 'tops_screen.dart';

/// Decide entre login, "aguardando aprovação" e tela principal, reagindo a
/// mudanças reais de sessão (login, logout, expiração de token) — sem
/// precisar de navegação manual em cada tela que faz signOut/signIn.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  Future<bool>? _approvalFuture;
  String? _checkedForUserId;

  /// Busca o próprio perfil e retorna se está aprovado. Guardado em
  /// [_approvalFuture] pra não refazer a query em todo rebuild.
  Future<bool> _checkApproval() async {
    final profile = await SupabaseService.instance.fetchMyProfile();
    // Liga a escuta de alarmes AQUI, e não no `build`.
    //
    // No build era chamado a cada rebuild do StreamBuilder. O
    // `if (_assinatura != null) return` de `escutar` tornava isso inócuo,
    // mas efeito colateral dentro de build é bomba armada: basta alguém
    // remover a guarda para o app abrir uma assinatura por frame.
    //
    // Só depois de aprovado: antes disso a RLS devolveria lista vazia de
    // qualquer forma, e assinar à toa gasta conexão de quem está no mato.
    if (profile.approved) AlarmeService.instance.escutar();
    return profile.approved;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: SupabaseService.instance.authStateChanges,
      builder: (context, snapshot) {
        final userId = SupabaseService.instance.currentUser?.id;
        if (userId == null) {
          _approvalFuture = null;
          _checkedForUserId = null;
          // Encerra a escuta de alarmes no logout. Sem isto a assinatura
          // do usuário anterior continuaria viva e o próximo a logar no
          // mesmo aparelho receberia alarme de Top que não é dele.
          AlarmeService.instance.parar();
          return const LoginScreen();
        }

        // Só dispara uma nova checagem se o usuário logado mudou — evita
        // refazer a query em todo rebuild deste StreamBuilder.
        if (_checkedForUserId != userId) {
          _checkedForUserId = userId;
          _approvalFuture = _checkApproval();
        }

        return FutureBuilder<bool>(
          future: _approvalFuture,
          builder: (context, approvalSnapshot) {
            if (approvalSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (approvalSnapshot.hasError) {
              return Scaffold(
                body: Center(
                  child: Text(
                    'Erro ao carregar perfil: ${approvalSnapshot.error}',
                  ),
                ),
              );
            }
            final approved = approvalSnapshot.data ?? false;
            if (!approved) {
              return PendingApprovalScreen(
                onRecheck: () async {
                  final result = await _checkApproval();
                  setState(() => _approvalFuture = Future.value(result));
                  return result;
                },
              );
            }
            return const TopsScreen();
          },
        );
      },
    );
  }
}
