/// Quem já entrou neste aparelho continua entrando com o servidor fora.
///
/// Em 20/11/2026 o projeto do Supabase foi pausado e `fetchMyProfile`
/// passou a falhar para todo mundo — inclusive para quem estava aprovado e
/// só queria abrir o app. A aprovação conhecida fica no disco do aparelho
/// e vale SÓ enquanto a rede não responde.
///
/// A RLS continua sendo a fronteira de segurança: sem servidor a pessoa só
/// enxerga o que já está no disco do próprio aparelho, e o perfil real
/// só volta a mandar na próxima vez que o app abrir com rede (ou nos
/// botões "Tentar de novo" / "Verificar" das telas de erro e de espera):
/// a checagem não roda sozinha enquanto a conta é a mesma.
library;

/// Decide se dá para entrar sem consultar o servidor.
///
/// Só entra quando o que está guardado é DESTA conta e era "aprovado".
/// Outro usuário no mesmo aparelho, conta não aprovada ou ausência de cache
/// caem na tela de erro com "Tentar de novo" / "Sair".
bool podeEntrarSemServidor({
  required String uid,
  required String? uidGuardado,
  required bool? aprovadoGuardado,
}) {
  return uid.isNotEmpty &&
      uidGuardado != null &&
      uidGuardado == uid &&
      aprovadoGuardado == true;
}

/// Formato guardado em `ColunasEstado.aprovacaoConhecida`: `<uid>|1` ou
/// `<uid>|0`. Uma chave só, para o par nunca ficar pela metade (uid de uma
/// conta com aprovação de outra).
String codificarAprovacao(String uid, bool aprovado) =>
    '$uid|${aprovado ? 1 : 0}';

/// Inverso de [codificarAprovacao]. Qualquer coisa fora do formato vira
/// "sem cache" — na dúvida, não abre a porta.
({String? uid, bool? aprovado}) lerAprovacaoGuardada(String? bruto) {
  if (bruto == null) return (uid: null, aprovado: null);
  final corte = bruto.lastIndexOf('|');
  if (corte <= 0) return (uid: null, aprovado: null);
  final uid = bruto.substring(0, corte);
  final flag = bruto.substring(corte + 1);
  if (flag != '1' && flag != '0') return (uid: null, aprovado: null);
  return (uid: uid, aprovado: flag == '1');
}

/// Se a mensagem crua é de falha de rede (DNS, conexão, timeout), e não
/// uma recusa do servidor.
///
/// Motivo de existir: em 20/11/2026 o projeto do Supabase estava pausado,
/// o endereço `<ref>.supabase.co` deixou de resolver, e a tela de login
/// mostrava `ClientException with SocketException: Failed host lookup`.
/// Ninguém entrava e ninguém sabia por quê.
///
/// Mora aqui, e não em `supabase_service.dart` (que o reexporta), porque
/// [entraNaFalha] depende dele e este arquivo tem de continuar puro: sem
/// Supabase, sem disco, testável direto.
bool pareceErroDeRede(String mensagem) {
  final m = mensagem.toLowerCase();
  const sinais = [
    // A biblioteca de login do Supabase embrulha TODA falha de rede nesta
    // exceção ("retryable" = vale tentar de novo, não houve resposta). Com
    // o projeto pausado e sessão vencida, era o erro que chegava aqui, e
    // não sendo reconhecido a entrada sem servidor nunca se aplicava.
    'authretryablefetchexception',
    'proxy failed',
    'failed host lookup',
    'socketexception',
    'connection refused',
    'connection reset',
    'connection closed',
    'network is unreachable',
    'timeoutexception',
    'timed out',
    'xmlhttprequest error',
    'failed to fetch',
    'handshakeexception',
  ];
  return sinais.any(m.contains);
}

/// Quanto a tela de abertura espera o perfil antes de desistir do servidor.
///
/// Sem teto, medido em 21/11/2026 com o projeto pausado: 36 s de rodinha
/// sem texto, porque a sessão vencida faz a biblioteca do Supabase tentar
/// renovar várias vezes antes de falhar. Para quem segura o celular isso é
/// "o app travou" — e a pessoa fecha antes de ver a mensagem. 8 s cobre
/// uma resposta lenta de 3G e ainda parece espera, não travamento.
const tempoMaximoParaEntrar = Duration(seconds: 8);

/// A decisão do `catch` de `AuthGate._checkApproval`: o perfil não veio,
/// a pessoa entra mesmo assim?
///
/// Fora da tela para ter teste direto. Ali dentro, um `&&` trocado por
/// `||` ou um uid esquecido abriria a porta para quem não devia, e só se
/// verificaria montando a árvore e fingindo o Supabase.
///
/// Entra só com as três coisas juntas: a falha é de REDE (recusa do
/// servidor é resposta, e resposta manda), há sessão ([uid] não nulo) e o
/// [guardado] em disco diz que ESTA conta estava aprovada.
bool entraNaFalha({
  required Object erro,
  required String? uid,
  required String? guardado,
}) {
  if (uid == null) return false;
  if (!pareceErroDeRede(erro.toString())) return false;
  final g = lerAprovacaoGuardada(guardado);
  return podeEntrarSemServidor(
    uid: uid,
    uidGuardado: g.uid,
    aprovadoGuardado: g.aprovado,
  );
}
