/// Quem já entrou neste aparelho continua entrando com o servidor fora.
///
/// Em 20/11/2026 o projeto do Supabase foi pausado e `fetchMyProfile`
/// passou a falhar para todo mundo — inclusive para quem estava aprovado e
/// só queria abrir o app. A aprovação conhecida fica no disco do aparelho
/// e vale SÓ enquanto a rede não responde.
///
/// A RLS continua sendo a fronteira de segurança: sem servidor a pessoa só
/// enxerga o que já está no disco do próprio aparelho, e na volta da rede
/// o perfil real manda (aprovação revogada derruba o acesso na próxima
/// checagem).
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
  return uidGuardado != null &&
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
