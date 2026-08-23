import 'dart:io';

import 'package:flutter/services.dart';

/// Emulação de cartão NFC (HCE) — exclusivo Android.
///
/// A Apple não permite HCE genérico para apps de terceiros no iOS, então
/// este serviço só tem efeito quando rodando em Android; nas outras
/// plataformas os métodos são no-op.
///
/// Limitação técnica do próprio Android: HCE emula cartões que respondem
/// por APDU (protocolo ISO-DEP / ISO 14443-4). Não é possível emular o
/// UID bruto de tags MIFARE Classic — isso não é uma limitação deste app,
/// é uma limitação da plataforma (nenhum app consegue fazer isso sem
/// hardware NFC especial do fabricante).
class NfcHceService {
  NfcHceService._();

  static final NfcHceService instance = NfcHceService._();

  static const _channel = MethodChannel('com.legendarios.hakuna_connect/hce');

  bool get isSupported => Platform.isAndroid;

  /// Define os bytes que o serviço HCE deve responder quando um leitor
  /// aproximar o aparelho (ex: payload lido/gravado de um cartão real via
  /// [NfcService], para "clonar" a credencial).
  Future<void> setEmulatedPayload(Uint8List payload) async {
    if (!isSupported) return;
    await _channel.invokeMethod('setPayload', payload);
  }

  Future<void> clearEmulatedPayload() async {
    if (!isSupported) return;
    await _channel.invokeMethod('clearPayload');
  }

  /// Notifica quando o leitor externo encerra a comunicação (aparelho
  /// afastado, ou outro app HCE assumiu). `reason` segue as constantes de
  /// `HostApduService.onDeactivated` (1 = link perdido, 2 = outra AID selecionada).
  void setOnDeactivatedListener(void Function(int reason) listener) {
    if (!isSupported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onDeactivated') {
        listener(call.arguments as int);
      }
    });
  }
}
