import 'dart:async';

import 'package:flutter/material.dart';

import '../models/profile.dart';
import '../offline/cache_local.dart';
import '../offline/tabelas.dart';
import '../services/alarme_service.dart';
import '../services/entrada_sem_servidor.dart';
import '../services/supabase_service.dart';
import 'login_screen.dart';
import 'pending_approval_screen.dart';
import 'tops_screen.dart';
import '../services/push_service.dart';

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
    final uid = SupabaseService.instance.currentUser?.id;
    final Profile profile;
    try {
      // Com teto: sem ele, sessão vencida + servidor fora davam 36 s de
      // rodinha (medido). O TimeoutException cai em `pareceErroDeRede` e
      // segue o mesmo caminho de qualquer falha de rede.
      profile = await SupabaseService.instance.fetchMyProfile().timeout(
        tempoMaximoParaEntrar,
      );
    } catch (erro) {
      // Servidor fora (projeto pausado, sem rede): quem já foi aprovado
      // neste aparelho continua entrando. A RLS segue sendo a fronteira —
      // offline só se vê o que já está no disco do próprio aparelho — e o
      // perfil real só volta a mandar na próxima abertura do app com rede
      // (ou nos botões das telas de erro/espera): esta checagem só roda de
      // novo quando o usuário muda. Qualquer outro caso (erro que
      // não é de rede, outra conta, não aprovado, sem cache, disco falhou)
      // relança e cai na tela de erro. A regra está em `entraNaFalha`,
      // que tem teste próprio; aqui só se lê o disco e se age.
      //
      // O disco só é lido quando a falha é de rede e há sessão: num erro
      // qualquer não há motivo para tocar no SQLite.
      if (uid != null && pareceErroDeRede(erro.toString())) {
        final guardado = await _aprovacaoGuardada();
        if (entraNaFalha(erro: erro, uid: uid, guardado: guardado)) {
          // Não conecta agora; a escuta pega quando a rede voltar. Sem
          // push: registrar exige o servidor.
          AlarmeService.instance.escutar();
          return true;
        }
      }
      rethrow;
    }
    // Liga a escuta de alarmes AQUI, e não no `build`.
    //
    // No build era chamado a cada rebuild do StreamBuilder. O
    // `if (_assinatura != null) return` de `escutar` tornava isso inócuo,
    // mas efeito colateral dentro de build é bomba armada: basta alguém
    // remover a guarda para o app abrir uma assinatura por frame.
    //
    // Só depois de aprovado: antes disso a RLS devolveria lista vazia de
    // qualquer forma, e assinar à toa gasta conexão de quem está no mato.
    if (profile.approved) {
      AlarmeService.instance.escutar();
      // Registra o aparelho para receber alarme com o app FECHADO.
      //
      // Depois do login, porque sem `profile_id` não há onde gravar o
      // token — e token sem dono não dispara nada. Sem `await`: push é
      // conveniência sobre o alarme que já funciona, e não pode atrasar a
      // tela de quem acabou de entrar.
      unawaited(PushService.instance.registrar());
    }
    return profile.approved;
  }

  /// O texto cru guardado; `entraNaFalha` o decodifica.
  Future<String?> _aprovacaoGuardada() async {
    try {
      return await CacheLocal.instance.lerEstado(
        ColunasEstado.aprovacaoConhecida,
      );
    } catch (_) {
      // Disco indisponível: o atalho simplesmente não se aplica.
      return null;
    }
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
          // Tira o aparelho da lista. Sem isto, em celular compartilhado,
          // o próximo dono receberia alarme clínico de um Top ao qual não
          // pertence.
          unawaited(PushService.instance.esquecer());
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
              // Rodinha sozinha em fundo branco é lida como "travou". Com
              // texto, a pessoa sabe que o app está trabalhando e espera os
              // poucos segundos até a resposta ou o aviso de servidor fora.
              return const Scaffold(
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Conectando ao servidor…'),
                    ],
                  ),
                ),
              );
            }
            if (approvalSnapshot.hasError) {
              // Antes era só o texto cru do erro, sem botão nenhum: com o
              // servidor fora do ar (projeto pausado em 20/11/2026), quem
              // já estava logado abria o app e ficava preso aqui. Agora a
              // tela diz o que houve e dá as duas saídas possíveis.
              final erro = approvalSnapshot.error!;
              final texto = pareceErroDeRede(erro.toString())
                  ? avisoServidorFora
                  : 'Não foi possível carregar o seu perfil.\n\n$erro';
              return Scaffold(
                body: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(Icons.cloud_off, size: 56),
                        const SizedBox(height: 16),
                        Text(texto, textAlign: TextAlign.center),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: () => setState(
                            () => _approvalFuture = _checkApproval(),
                          ),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Tentar de novo'),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          // A sessão local sai antes da chamada de rede; sem
                          // servidor, o erro da chamada não importa.
                          onPressed: () => SupabaseService.instance
                              .signOut()
                              .catchError((_) {}),
                          child: const Text('Sair e entrar com outra conta'),
                        ),
                      ],
                    ),
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
