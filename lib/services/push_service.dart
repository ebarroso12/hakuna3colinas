import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import 'supabase_service.dart';

/// Notificação com o app **fechado**.
///
/// ## O buraco que isto fecha
///
/// O alarme chega em qualquer tela, com som e vibração, mas **só com o
/// app aberto**: o Realtime é um WebSocket do processo, e processo morto
/// é conexão morta. Quem guardou o celular no bolso não recebia nada.
///
/// Quem acorda app fechado no Android é o **sistema**, a pedido do FCM.
/// Não há outro caminho — e é por isso que isto existe apesar de
/// acrescentar uma dependência pesada ao projeto.
///
/// ## O que o push NÃO resolve, e precisa ficar dito
///
/// **FCM exige internet.** No mato sem sinal ele não entrega nada, e
/// nenhuma configuração muda isso. Para quem está sem rede, o que vale é
/// a malha por rádio (`MalhaService`) e o rádio HT.
///
/// Push resolve o caso de quem está **com sinal e com o app fechado** —
/// no acampamento, dormindo, com o celular no bolso. É um caso real e
/// frequente, e é só esse.
///
/// ## Por que o token vai para o banco e não fica no aparelho
///
/// Quem dispara o push é o servidor, e ele precisa saber para onde
/// mandar. A tabela `dispositivos` guarda `(profile_id, fcm_token)`; o
/// disparo roda com `service_role` e varre os tokens de quem deve ser
/// avisado. Ver `supabase/dispositivos.sql`.
class PushService {
  PushService._();

  static final PushService instance = PushService._();

  /// Só para teste: evita tocar no canal de plataforma.
  @visibleForTesting
  static bool ligado = true;

  String? _ultimoToken;
  StreamSubscription<String>? _subRenovacao;

  /// O token deste aparelho, se já foi obtido nesta sessão.
  String? get token => _ultimoToken;

  /// Pede permissão, pega o token e grava em `dispositivos`.
  ///
  /// Chamar **depois do login**: sem `profile_id` não há onde gravar, e o
  /// token sem dono não serve para disparar nada.
  ///
  /// Nunca lança. Push é conveniência sobre o alarme que já existe — se
  /// falhar, o app continua inteiro e o alarme continua chegando com a
  /// tela aberta. Derrubar o login por causa disso seria trocar o
  /// essencial pelo acessório.
  Future<void> registrar() async {
    if (!ligado || kIsWeb) return;
    try {
      final messaging = FirebaseMessaging.instance;

      // No Android 13+ a permissão de notificação é explícita. Sem ela o
      // token até existe, mas a notificação não aparece — o pior dos dois
      // mundos, porque o servidor acha que entregou.
      final permissao = await messaging.requestPermission();
      if (permissao.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }

      final token = await messaging.getToken();
      if (token == null || token.isEmpty) return;
      await _gravar(token);

      // O FCM TROCA o token sozinho: reinstalação, restauração de backup,
      // limpeza de dados. Sem escutar isto, o aparelho some do alarme em
      // silêncio e ninguém percebe até a emergência em que não tocou.
      await _subRenovacao?.cancel();
      _subRenovacao = messaging.onTokenRefresh.listen(
        _gravar,
        onError: (_) {},
      );
    } catch (_) {
      // Firebase não configurado, sem Play Services, sem rede. Nada disso
      // pode impedir o app de abrir.
    }
  }

  Future<void> _gravar(String token) async {
    _ultimoToken = token;
    final uid = SupabaseService.instance.currentUserId;
    if (uid == null) return;
    try {
      await SupabaseService.instance.registrarDispositivo(
        fcmToken: token,
        plataforma: defaultTargetPlatform == TargetPlatform.iOS
            ? 'ios'
            : 'android',
      );
    } catch (_) {
      // Sem rede agora, grava na próxima abertura. Não vale enfileirar:
      // um token que subiu tarde demais não entrega alarme nenhum, e
      // token velho na fila é pior que token ausente.
    }
  }

  /// Tira este aparelho da lista. Chamar no logout.
  ///
  /// Sem isto, o celular continuaria recebendo alarme de um Top ao qual a
  /// pessoa não pertence mais — e em aparelho compartilhado isso
  /// entregaria notificação clínica a quem não deveria ver.
  Future<void> esquecer() async {
    final token = _ultimoToken;
    await _subRenovacao?.cancel();
    _subRenovacao = null;
    _ultimoToken = null;
    if (token == null) return;
    try {
      await SupabaseService.instance.esquecerDispositivo(token);
    } catch (_) {}
  }
}
