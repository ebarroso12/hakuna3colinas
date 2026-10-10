import 'package:flutter/foundation.dart';

import '../models/participant_tag.dart';

/// Por que a leitura de QR não funciona agora.
enum MotivoQrIndisponivel {
  /// Navegador: a câmera existe, mas o app no web é ambiente de
  /// desenvolvimento, não de campo.
  web,

  /// Permissão de câmera negada.
  semPermissao,

  /// Permissão negada permanentemente — só resolve nas Configurações.
  negadaParaSempre,

  /// Aparelho sem câmera.
  semCamera,
}

/// O que uma leitura de QR produziu, antes de resolver o token.
sealed class LeituraQr {
  const LeituraQr();
}

/// QR legível e com token no formato do sistema.
class QrComToken extends LeituraQr {
  final String token;
  const QrComToken(this.token);
}

/// QR legível, mas não é pulseira deste sistema — QR de nota fiscal, de
/// wi-fi, de link. Estado explícito para a tela dizer "este QR não é de
/// pulseira" em vez de "não encontrado", que mandaria o Hakuna procurar
/// pelo nome por nada.
class QrDeOutroSistema extends LeituraQr {
  /// O conteúdo lido, truncado. Serve para a tela mostrar o que leu e o
  /// Hakuna perceber que encostou no QR errado.
  final String amostra;
  const QrDeOutroSistema(this.amostra);
}

/// Token do QR, isolado da camada de câmera.
///
/// **Contingência do NFC**, pedida para dois casos reais: aparelho sem
/// sensor NFC, e pulseira cujo chip parou de responder. Nos dois, o Hakuna
/// está na frente de alguém e precisa identificar.
///
/// **Decisão central:** o QR carrega exatamente a mesma URL que vai no
/// NDEF da pulseira — `https://legendarios.app/t/<token de 128 bits>`.
/// Nada aqui é um formato novo. Consequências:
///
///  - a resolução reaproveita `TagService.resolver` inteiro: cache em
///    disco, fallback, auditoria e revogação valem igual;
///  - revogar uma pulseira revoga o QR dela no mesmo ato, porque é o mesmo
///    token. Um formato separado teria dois ciclos de vida para manter em
///    sincronia, e o que fica esquecido é o que continua valendo depois de
///    perdido.
///
/// **Risco que o QR adiciona e o NFC não tem:** QR se copia com uma foto.
/// Quem fotografar a pulseira de alguém consegue um QR idêntico. Isso não
/// vira acesso ao sistema — ler tag não autentica, e a RLS de
/// `participant_tags` só responde a Hakuna liberado no Top —, mas permite
/// um Hakuna identificar a pessoa errada de boa-fé. É aceitável para
/// contingência e **não** deve virar o caminho principal.
abstract final class QrTokenService {
  /// Extrai o token de um QR lido. Mesma validação do NDEF.
  static LeituraQr interpretar(String? conteudo) {
    final token = TagNdef.tokenDe(conteudo);
    if (token != null) return QrComToken(token);
    final cru = (conteudo ?? '').trim();
    return QrDeOutroSistema(
      cru.length <= 40 ? cru : '${cru.substring(0, 40)}…',
    );
  }

  /// O conteúdo que deve ser codificado no QR impresso da pulseira.
  ///
  /// Idêntico ao gravado no NDEF de propósito — ver a doc da classe.
  static String conteudoPara(String token) => TagNdef.urlPara(token);

  /// A plataforma suporta leitura por câmera?
  ///
  /// Web fica de fora: `mobile_scanner` funciona em navegador, mas o app
  /// no web é ambiente de desenvolvimento (ver CLAUDE.md) e exibir um
  /// leitor lá sugeriria que o fluxo de campo foi testado no navegador.
  static bool get suportado {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }
}
