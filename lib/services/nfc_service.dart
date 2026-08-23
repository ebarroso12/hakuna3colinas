import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/ndef_record.dart';
import 'package:nfc_manager_ndef/nfc_manager_ndef.dart';

/// Leitura e gravação de tags NFC (NDEF), disponível em Android e iOS.
///
/// A emulação de cartão (transformar o aparelho em um cartão / "clonar")
/// é exclusiva do Android e vive em `nfc_hce_service.dart`, pois a Apple
/// não permite HCE genérico para apps de terceiros.
class NfcService {
  NfcService._();

  static final NfcService instance = NfcService._();

  Future<NfcAvailability> checkAvailability() => NfcManager.instance.checkAvailability();

  /// Lê a primeira tag aproximada e retorna o texto do primeiro registro
  /// NDEF de texto encontrado (ex: id gravado numa pulseira de senderista).
  Future<String?> readTagText() async {
    final completer = Completer<String?>();

    await NfcManager.instance.startSession(
      pollingOptions: {NfcPollingOption.iso14443, NfcPollingOption.iso15693},
      onDiscovered: (NfcTag tag) async {
        try {
          final ndef = Ndef.from(tag);
          final message = ndef?.cachedMessage;
          if (message == null || message.records.isEmpty) {
            completer.complete(null);
            return;
          }
          completer.complete(_decodeTextRecord(message.records.first));
        } catch (e, st) {
          // Sem este catch, uma tag NDEF malformada faz o Completer nunca
          // resolver e a tela de leitura fica travada pra sempre.
          if (!completer.isCompleted) completer.completeError(e, st);
        } finally {
          await NfcManager.instance.stopSession();
        }
      },
    );

    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        NfcManager.instance.stopSession();
        throw TimeoutException('Nenhuma tag foi aproximada a tempo');
      },
    );
  }

  /// Grava um texto (ex: id do senderista/hakuna) em uma tag NDEF gravável.
  Future<void> writeTagText(String text) async {
    final completer = Completer<void>();

    await NfcManager.instance.startSession(
      pollingOptions: {NfcPollingOption.iso14443, NfcPollingOption.iso15693},
      onDiscovered: (NfcTag tag) async {
        try {
          final ndef = Ndef.from(tag);
          if (ndef == null || !ndef.isWritable) {
            throw StateError('Tag não encontrada ou não é gravável');
          }
          await ndef.write(message: NdefMessage(records: [_encodeTextRecord(text)]));
          completer.complete();
        } catch (e, st) {
          completer.completeError(e, st);
        } finally {
          await NfcManager.instance.stopSession();
        }
      },
    );

    return completer.future;
  }

  /// Monta um registro NDEF de texto (RTD Text), conforme o NFC Forum.
  NdefRecord _encodeTextRecord(String text, {String languageCode = 'pt'}) {
    final languageBytes = ascii.encode(languageCode);
    final textBytes = utf8.encode(text);
    final payload = Uint8List.fromList([
      languageBytes.length, // status byte: UTF-8, length do código de idioma
      ...languageBytes,
      ...textBytes,
    ]);
    return NdefRecord(
      typeNameFormat: TypeNameFormat.wellKnown,
      type: Uint8List.fromList([0x54]), // 'T'
      identifier: Uint8List(0),
      payload: payload,
    );
  }

  String? _decodeTextRecord(NdefRecord record) {
    if (record.payload.isEmpty) return null;
    final languageCodeLength = record.payload.first & 0x3f;
    final textBytes = record.payload.sublist(1 + languageCodeLength);
    return utf8.decode(textBytes);
  }
}
