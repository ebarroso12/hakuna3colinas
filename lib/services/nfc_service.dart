import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:ndef/ndef.dart' as ndef;

/// Falha de NFC já traduzida para quem está com o celular na mão.
///
/// O plugin devolve `PlatformException(408, "Polling tag timeout")` e
/// companhia. Jogado na tela, vira
/// "Não foi possível ler a tag: PlatformException(408, polling tag
/// timeout, null, null)" — e o caso 408 é o **mais comum de todos**: é
/// simplesmente ninguém ter encostado a pulseira em 30 segundos. Mostrar
/// código de erro para quem está atendendo alguém no mato é inútil.
///
/// O serviço anterior (`nfc_manager`) lançava `TimeoutException` com texto
/// em português; a troca de plugin tirou isso sem reposição. Achado por
/// revisão em 11/10/2026.
class ErroDeNfc implements Exception {
  const ErroDeNfc(this.mensagem, {this.codigo});

  /// Texto pronto para a tela. Sem código, sem nome de classe.
  final String mensagem;

  /// Código do plugin, para log e para quem investiga depois.
  final String? codigo;

  @override
  String toString() => mensagem;
}

/// Estado do leitor NFC no aparelho.
///
/// Enum próprio em vez do `NFCAvailability` do plugin: a tela não precisa
/// conhecer o pacote de NFC, e trocar de plugin (já aconteceu uma vez) não
/// deve obrigar a mexer em tela.
enum DisponibilidadeNfc {
  /// Aparelho sem leitor NFC, ou plataforma sem suporte (web).
  semLeitor,

  /// Tem leitor, está desligado nas Configurações do sistema.
  desligado,

  /// Pronto para encostar.
  pronto,
}

/// O que saiu de uma aproximação de tag.
///
/// Guarda **tudo** que o chip entregou, não só o conteúdo gravado. É isso
/// que permite a tela dizer "cartão MIFARE Classic em branco, UID
/// 04:A2:…" em vez de "não foi possível ler" — a diferença entre o Hakuna
/// saber que a pulseira está virgem e ele achar que o celular quebrou.
@immutable
class LeituraNfc {
  const LeituraNfc({
    required this.uid,
    required this.tipo,
    required this.padrao,
    required this.temNdef,
    required this.gravavel,
    this.conteudo,
  });

  /// Número de série do chip, em hex. Vazio quando o chip não o entrega.
  ///
  /// **UID identifica, não autentica.** Ele é lido por qualquer celular
  /// sem senha nenhuma e se copia com hardware de dezenas de reais. Serve
  /// para reconhecer um cartão que não aceita gravação; não serve como
  /// prova de que a pessoa é quem diz ser. Por isso o token NDEF — 128
  /// bits aleatórios e revogável — continua sendo o caminho preferencial.
  final String uid;

  /// Tipo segundo o plugin (`iso7816`, `mifareClassic`, `iso15693`…).
  final String tipo;

  /// Padrão que o chip declara, ou `unknown`.
  final String padrao;

  final bool temNdef;
  final bool gravavel;

  /// Texto do primeiro registro NDEF aproveitável, se houver.
  final String? conteudo;

  /// UID em grupos de dois dígitos, como se lê num cartão.
  String get uidLegivel {
    if (uid.isEmpty) return '';
    final pares = <String>[];
    for (var i = 0; i + 1 < uid.length; i += 2) {
      pares.add(uid.substring(i, i + 2).toUpperCase());
    }
    return pares.join(':');
  }

  /// Nada identificável saiu da aproximação.
  bool get vazia => (conteudo == null || conteudo!.isEmpty) && uid.isEmpty;
}

/// Leitura e gravação de tags NFC.
///
/// Usa `flutter_nfc_kit`, que no Android chama
/// `NfcAdapter.enableReaderMode`. Foi troca deliberada, em 11/10/2026,
/// saindo do `nfc_manager`, e o motivo é o que este app faz com a pulseira:
///
/// 1. **O UID vem sempre.** `poll()` devolve `tag.id` e `tag.standard`
///    mesmo em cartão sem NDEF. No caminho anterior, `Ndef.from(tag)`
///    devolvia null e a leitura virava um `null` sem explicação: cartão em
///    branco, cartão de outro sistema e MIFARE Classic que o chipset não
///    formata eram todos "não deu". Em campo é a diferença entre trocar a
///    pulseira e ficar batendo o celular nela.
/// 2. **Reader mode desliga o som e a vibração do sistema** por parâmetro
///    e ignora o despacho de NDEF do Android — nenhum outro app rouba a
///    tag no meio da leitura.
/// 3. É o mesmo caminho do app de NFC que já roda em campo nos Legendários
///    (`com.trixx.hakunanfc`, conferido no APK em 11/10/2026).
///
/// A emulação de cartão (HCE) **não** passa por aqui: vive em
/// `nfc_hce_service.dart`, por canal nativo, e é exclusiva do Android.
class NfcService {
  NfcService._();

  static final NfcService instance = NfcService._();

  /// Quanto tempo o leitor fica ligado esperando a tag.
  static const _esperaDaTag = Duration(seconds: 30);

  Future<DisponibilidadeNfc> checkAvailability() async {
    // No web o canal nativo não existe e `invokeMethod` lança. Resolver
    // antes de chamar evita a exceção virar "erro ao ler tag" na tela.
    if (kIsWeb) return DisponibilidadeNfc.semLeitor;
    try {
      final estado = await FlutterNfcKit.nfcAvailability;
      return switch (estado) {
        NFCAvailability.available => DisponibilidadeNfc.pronto,
        NFCAvailability.disabled => DisponibilidadeNfc.desligado,
        NFCAvailability.not_supported => DisponibilidadeNfc.semLeitor,
      };
    } catch (_) {
      return DisponibilidadeNfc.semLeitor;
    }
  }

  /// Encosta na tag e devolve tudo que ela entregou.
  ///
  /// A sessão é **sempre** encerrada, inclusive no erro: reader mode
  /// deixado aberto consome bateria e impede a próxima leitura de começar.
  ///
  /// Ordem de preferência do conteúdo: registro de **texto**, que é o que
  /// este app grava, e depois registro de **URI**, o formato que qualquer
  /// outro programa de NFC usaria para a mesma URL. Ler os dois custa nada
  /// e evita que uma pulseira gravada fora do app seja recusada como
  /// "formato inválido".
  Future<LeituraNfc> lerTag() async {
    await _exigirLeitor();

    try {
      final NFCTag tag;
      try {
        tag = await FlutterNfcKit.poll(
          timeout: _esperaDaTag,
          // Som e vibração são do app, não do sistema: a tela de leitura
          // dá o retorno junto com o resultado, e o bipe do Android
          // chegava antes de se saber se a tag valia algo.
          androidPlatformSound: false,
          iosAlertMessage: 'Encoste o celular na pulseira',
          iosMultipleTagMessage: 'Mais de uma tag perto. Deixe só uma.',
        );
      } on PlatformException catch (e) {
        throw _traduzir(e);
      }

      String? conteudo;
      if (tag.ndefAvailable ?? false) {
        conteudo = await _primeiroTextoDoNdef();
      }

      return LeituraNfc(
        uid: tag.id,
        tipo: tag.type.name,
        padrao: tag.standard,
        temNdef: tag.ndefAvailable ?? false,
        gravavel: tag.ndefWritable ?? false,
        conteudo: conteudo,
      );
    } finally {
      await _encerrar();
    }
  }

  /// Compatibilidade: só o conteúdo gravado.
  ///
  /// Quem precisa saber do UID — e a tela de leitura precisa — usa
  /// [lerTag].
  Future<String?> readTagText() async => (await lerTag()).conteudo;

  /// Grava o texto na pulseira.
  ///
  /// Grava registro de **texto**, não de URI, de propósito: a URL serve
  /// para a tag ser um NDEF válido, e com registro de texto o celular de
  /// um estranho que encoste na pulseira não abre navegador nenhum. Ver
  /// `TagNdef.prefixo`.
  Future<void> writeTagText(String text) async {
    await _exigirLeitor();

    try {
      final NFCTag tag;
      try {
        tag = await FlutterNfcKit.poll(
          timeout: _esperaDaTag,
          androidPlatformSound: false,
          iosAlertMessage: 'Encoste o celular na pulseira para gravar',
        );
      } on PlatformException catch (e) {
        throw _traduzir(e);
      }

      if (!(tag.ndefAvailable ?? false)) {
        throw StateError(
          'Esta tag não é NDEF (${tag.type.name}). Use uma pulseira NTAG '
          'ou formate o cartão antes.',
        );
      }
      if (!(tag.ndefWritable ?? false)) {
        throw StateError('Esta tag está protegida contra gravação.');
      }

      try {
        await FlutterNfcKit.writeNDEFRecords([
          ndef.TextRecord(text: text, language: 'pt'),
        ]);
      } on PlatformException catch (e) {
        throw _traduzir(e);
      }
    } finally {
      await _encerrar();
    }
  }

  /// Traduz o código do plugin para o que a pessoa precisa fazer.
  ///
  /// Os códigos vêm do canal nativo do `flutter_nfc_kit` (conferidos no
  /// fonte do plugin, 3.6.2). O que não estiver mapeado volta com o texto
  /// original anexado — melhor um código estranho na tela que uma
  /// mensagem genérica esconder a causa de quem for investigar.
  static ErroDeNfc _traduzir(PlatformException e) {
    final mensagem = switch (e.code) {
      '408' =>
        'Nenhuma pulseira foi encostada. Toque em LER TAG e encoste o '
            'celular na pulseira, nas costas do aparelho.',
      '406' => 'A tag saiu de perto antes de responder. Encoste de novo.',
      '503' => 'A tag saiu de perto no meio da leitura. Encoste de novo.',
      '405' =>
        'Esta tag não aceita o comando. Se é pulseira nova, emita por '
            '"Emitir pulseiras" no menu do Top.',
      '404' =>
        'NFC está desligado ou indisponível. Ative em Configurações > '
            'Conexões > NFC.',
      '400' =>
        'O conteúdo da tag está corrompido. Use o QR da pulseira, ou '
            'busque pelo nome.',
      '500' =>
        'Falha de comunicação com a tag. Encoste de novo, mais firme e '
            'por mais tempo.',
      _ => 'Falha de NFC (${e.code}): ${e.message ?? "sem detalhe"}',
    };
    return ErroDeNfc(mensagem, codigo: e.code);
  }

  Future<void> _exigirLeitor() async {
    final estado = await checkAvailability();
    if (estado == DisponibilidadeNfc.semLeitor) {
      throw StateError('Este aparelho não tem leitor NFC.');
    }
    if (estado == DisponibilidadeNfc.desligado) {
      throw StateError(
        'NFC está desligado. Ative em Configurações > Conexões > NFC.',
      );
    }
  }

  /// Fecha a sessão sem o erro de fechamento esconder o erro real.
  Future<void> _encerrar() async {
    try {
      await FlutterNfcKit.finish();
    } catch (_) {
      // Encerrar sessão que já caiu lança, e esse erro não interessa a
      // ninguém: o que importa é o da leitura, e ele está no `finally` de
      // quem chamou. Sem engolir aqui, uma tag afastada no meio da
      // gravação mostraria "erro ao encerrar sessão" em vez de "a tag saiu
      // de perto".
    }
  }

  /// Primeiro registro NDEF que renda texto: `TextRecord` ou `UriRecord`.
  Future<String?> _primeiroTextoDoNdef() async {
    try {
      final registros = await FlutterNfcKit.readNDEFRecords();
      for (final r in registros) {
        if (r is ndef.TextRecord) {
          final t = r.text;
          if (t != null && t.isNotEmpty) return t;
        }
      }
      for (final r in registros) {
        if (r is ndef.UriRecord) {
          final u = r.uriString;
          if (u != null && u.isNotEmpty) return u;
        }
      }
      return null;
    } catch (_) {
      // Tag NDEF malformada, ou que saiu de perto no meio da leitura.
      // Devolver null em vez de estourar: o UID já foi lido e identifica
      // o cartão, e a tela segue pela busca por nome.
      return null;
    }
  }
}
