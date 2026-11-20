import '../models/top.dart';
import '../offline/cache_local.dart';
import 'supabase_service.dart';

/// Frase da faixa quando a lista mostrada é a do disco porque a rede não
/// respondeu. Curta de propósito: a lista está logo abaixo e é ela que
/// importa — o aviso longo de servidor fora fica para quando NÃO há lista.
const avisoListaDoAparelho =
    'Sem conexão com o servidor. Mostrando os Tops guardados neste '
    'aparelho.';

/// Frase da faixa quando o servidor respondeu com erro (não de rede) e
/// há lista no disco.
const avisoListaNaoAtualizou =
    'Não foi possível atualizar a lista agora. Mostrando a última que '
    'este aparelho recebeu.';

/// Frase para erro que não é de rede e sem nada no disco.
const avisoSemListaDeTops =
    'Não foi possível carregar os Tops agora. Puxe a lista para baixo '
    'para tentar de novo. Se continuar, avise o administrador.';

/// O que a tela inicial mostra: a lista, e uma frase (ou nenhuma).
class TelaDeTops {
  final List<Top> tops;

  /// Com [tops] preenchida, vai numa faixa acima da lista. Com [tops]
  /// vazia, ocupa o lugar dela. Nunca é o texto cru da exceção: era
  /// "Erro ao carregar tops: ClientException ... Failed host lookup" que
  /// aparecia, e ninguém sabia o que fazer com aquilo.
  final String? aviso;

  /// Só gira quando não há nada para mostrar ainda. Com lista no disco,
  /// a tela já mostra a lista e a rede atualiza por baixo.
  final bool carregando;

  const TelaDeTops({required this.tops, this.aviso, this.carregando = false});
}

/// Combina o disco e a rede numa decisão de tela.
///
/// Fora do `State` para ter teste direto, no mesmo espírito de
/// `acesso_as_equipes.dart`: regra de tela que erra calada precisa de
/// teste que não dependa de montar a árvore.
///
/// - [daRede] não nulo: o servidor respondeu e manda, mesmo com lista
///   vazia — o disco não pode desmentir o servidor sobre a que Tops a
///   pessoa pertence.
/// - [erroDaRede] com disco: a lista do disco, com faixa curta.
/// - [erroDaRede] sem disco: só a frase — [avisoServidorFora] se for rede.
/// - nenhum dos dois ainda: mostra o disco; gira só se o disco estiver
///   vazio ou ainda não tiver sido lido ([doDisco] nulo).
TelaDeTops telaDeTops({
  required List<Top>? doDisco,
  List<Top>? daRede,
  Object? erroDaRede,
}) {
  if (daRede != null) return TelaDeTops(tops: daRede);
  final disco = doDisco ?? const <Top>[];
  if (erroDaRede != null) {
    final deRede = pareceErroDeRede(erroDaRede.toString());
    if (disco.isNotEmpty) {
      return TelaDeTops(
        tops: disco,
        aviso: deRede ? avisoListaDoAparelho : avisoListaNaoAtualizou,
      );
    }
    return TelaDeTops(
      tops: const [],
      aviso: deRede ? avisoServidorFora : avisoSemListaDeTops,
    );
  }
  return TelaDeTops(tops: disco, carregando: disco.isEmpty);
}

/// Fachada da lista de Tops, no padrão de `DadosDoTop`: a rede alimenta
/// o disco, o disco alimenta a tela.
class ListaDeTops {
  ListaDeTops._();

  static final ListaDeTops instance = ListaDeTops._();

  /// A última lista guardada para [uid]. Falha de disco vira lista vazia:
  /// a tela segue para a rede em vez de parar num erro de SQLite.
  Future<List<Top>> doDisco(String? uid) async {
    if (uid == null || uid.isEmpty) return const [];
    try {
      return await CacheLocal.instance.tops(uid);
    } catch (_) {
      return const [];
    }
  }

  /// Busca no servidor e grava no disco desta conta. O erro da rede sobe
  /// para a tela decidir a frase; o erro do disco não — a lista já veio.
  Future<List<Top>> daRede(String? uid) async {
    final tops = await SupabaseService.instance.fetchMyTops();
    if (uid != null && uid.isNotEmpty) {
      try {
        await CacheLocal.instance.salvarTops(uid, tops);
      } catch (_) {
        // Sem disco, a próxima abertura sem rede não terá lista — mas
        // esta, com rede, tem, e é ela que a pessoa está vendo agora.
      }
    }
    return tops;
  }
}
