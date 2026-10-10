/// Normalização de texto para busca.
///
/// Resolve um problema real: `toLowerCase()` sozinho faz `JOAO` **não
/// encontrar** `JOÃO`. Numa lista de 215 nomes brasileiros isso falha o
/// tempo todo — e o Hakuna que não acha o paciente pelo nome não tem
/// plano B quando a pulseira falha.
///
/// O valor normalizado é gravado numa coluna no momento do cache, não
/// calculado a cada tecla: remover acento de 215 nomes a cada letra
/// digitada é trabalho repetido à toa.
abstract final class TextoBusca {
  /// Mapa de caracteres acentuados para o equivalente sem acento.
  ///
  /// Feito à mão em vez de usar pacote: são 60 entradas, cobrem português
  /// inteiro, e evitam mais uma dependência num app que já tem 26.
  static const _acentos = {
    'á': 'a',
    'à': 'a',
    'ã': 'a',
    'â': 'a',
    'ä': 'a',
    'å': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'õ': 'o',
    'ô': 'o',
    'ö': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
    'ñ': 'n',
    'ý': 'y',
    'ÿ': 'y',
    'Á': 'a',
    'À': 'a',
    'Ã': 'a',
    'Â': 'a',
    'Ä': 'a',
    'Å': 'a',
    'É': 'e',
    'È': 'e',
    'Ê': 'e',
    'Ë': 'e',
    'Í': 'i',
    'Ì': 'i',
    'Î': 'i',
    'Ï': 'i',
    'Ó': 'o',
    'Ò': 'o',
    'Õ': 'o',
    'Ô': 'o',
    'Ö': 'o',
    'Ú': 'u',
    'Ù': 'u',
    'Û': 'u',
    'Ü': 'u',
    'Ç': 'c',
    'Ñ': 'n',
    'Ý': 'y',
  };

  /// Minúsculo, sem acento, espaços colapsados.
  ///
  /// `"JOÃO  DA  SILVA"` e `"joao da silva"` viram a mesma coisa.
  static String normalizar(String? texto) {
    if (texto == null || texto.isEmpty) return '';
    final buffer = StringBuffer();
    // `split('')` em vez de `characters`: todo acento do portugues cabe num
    // unico code unit UTF-16, entao nao ha grafema composto pra quebrar.
    for (final char in texto.split('')) {
      buffer.write(_acentos[char] ?? char.toLowerCase());
    }
    return buffer.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Junta os campos pelos quais se busca numa string só, já normalizada.
  /// É esse valor que vai para a coluna `busca_normalizada`.
  static String chaveDe({
    String? nome,
    String? apelido,
    String? familia,
    String? codigo,
  }) {
    return [
      normalizar(nome),
      normalizar(apelido),
      normalizar(familia),
      normalizar(codigo),
    ].where((s) => s.isNotEmpty).join(' ');
  }
}
