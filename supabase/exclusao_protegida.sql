-- ============================================================================
-- APAGAR USUARIO E SENDERISTA — 11/10/2026
--
-- Pedido: permitir ao admin master apagar usuarios e senderistas, com
-- selecao nome a nome.
--
-- Migracoes aplicadas: `exclusao_protegida_pelo_prontuario`.
-- ============================================================================
--
-- DOIS ACHADOS NO BANCO, ANTES DE ESCREVER QUALQUER TELA
--
-- 1. `atendimentos.opened_by` tinha ON DELETE **CASCADE** para `profiles`.
--
--    Apagar um Hakuna APAGARIA TODOS OS ATENDIMENTOS QUE ELE REGISTROU. Um
--    clique de limpeza de cadastro destruindo o prontuario de dezenas de
--    pessoas, em silencio, sem aviso e sem volta. Se a tela de exclusao
--    tivesse sido escrita antes de olhar isto, o recurso teria saido
--    pronto para destruir dado clinico.
--
-- 2. `top_participants` nao tinha NENHUMA policy de DELETE.
--
--    Ninguem conseguia apagar senderista, nem o admin — e nao era
--    protecao pensada, era ausencia. Nao havia botao porque nao havia
--    permissao, e nao havia permissao porque ninguem tinha decidido nada.
--
-- A REGRA QUE FICOU: **apaga quem nao deixou rastro clinico; quem deixou,
-- desativa.** Cadastro de teste, duplicado e quem nao compareceu saem de
-- verdade. Quem atendeu ou foi atendido, nao — a historia fica.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. O prontuario deixa de depender de quem o registrou
--
-- RESTRICT e nao SET NULL porque `opened_by` e NOT NULL — e deve continuar:
-- atendimento sem autor nao serve como registro clinico.
--
-- Com RESTRICT, apagar um Hakuna que registrou atendimento FALHA. E o
-- comportamento certo. A saida e desativar a pessoa, nao apagar a historia
-- dela. A UI confere antes com `dependencias_do_perfil` e explica com
-- numeros, em vez de mostrar um erro 23503 que nao significa nada para
-- quem esta usando o app.
-- ----------------------------------------------------------------------------
alter table public.atendimentos
  drop constraint if exists atendimentos_opened_by_fkey;
alter table public.atendimentos
  add constraint atendimentos_opened_by_fkey
  foreign key (opened_by) references public.profiles(id) on delete restrict;


-- ----------------------------------------------------------------------------
-- 2. Quanto dado clinico esta amarrado a cada pessoa
--
-- Uma consulta para a lista toda, em vez de uma por nome: o admin marca 30
-- e a tela precisa responder antes de ele perder a paciencia.
--
-- SECURITY DEFINER porque conta linhas que o chamador pode nao ter direito
-- de ler uma a uma — a RLS de `atendimentos` so devolve atendimento de Top
-- onde a pessoa e Hakuna liberado.
-- ----------------------------------------------------------------------------
-- (corpo em `dependencias_do_perfil` / `dependencias_do_senderista`; ver a
--  migracao `exclusao_protegida_pelo_prontuario` para o SQL completo)
--
-- O que BLOQUEIA apagar um PERFIL:
--   atendimento registrado ou encerrado por ele  (prontuario)
--   afericao feita por ele, ou DELE              (prontuario)
--   linha em audit_log                           (rastro de seguranca)
--   pulseira emitida ou revogada por ele         (rastro de seguranca)
--   alarme disparado por ele                     (rastro de seguranca)
--   leitura de tag feita por ele                 (rastro de seguranca)
--   ser o admin master                           (nunca, nem por ele mesmo)
--
-- O que BLOQUEIA apagar um SENDERISTA:
--   ter atendimento no prontuario.
--
--   E so isso, e por um motivo especifico: `atendimentos.participant_id` e
--   SET NULL. Apagar o senderista NAO apaga o atendimento — deixa ele
--   ORFAO, um prontuario que ninguem sabe de quem e. Isso e PIOR que
--   apagar, porque o dado continua la parecendo valido.
--
--   Pulseira e leitura nao bloqueiam: a pulseira cai em cascata (e daquela
--   pessoa, faz sentido ir junto) e a leitura vira SET NULL, mas leitura de
--   pulseira sem participante ainda responde "quando e onde alguem passou",
--   que e para o que ela serve.


-- ----------------------------------------------------------------------------
-- 3. Quem pode apagar: so o admin master
--
-- Era `is_admin()` para profiles — qualquer admin — e NADA para
-- senderistas. Apagar pessoa de um evento medico nao e operacao de rotina.
-- ----------------------------------------------------------------------------
drop policy if exists profiles_delete_admin on public.profiles;
create policy profiles_delete_master on public.profiles
  for delete using (is_master_admin() and not is_master_admin);

create policy top_participants_delete_master on public.top_participants
  for delete using (is_master_admin());


-- ============================================================================
-- POR QUE USUARIO PASSA PELA EDGE FUNCTION E SENDERISTA NAO
--
-- `profiles.id` referencia `auth.users(id) ON DELETE CASCADE`. A direcao
-- importa:
--
--   apagar auth.users  -> o profile cai em cascata   (completo)
--   apagar profiles    -> o auth.users FICA          (orfao)
--
-- O orfao nao e inofensivo: a pessoa continua conseguindo fazer login, o
-- app busca o perfil, nao acha, e ela fica numa tela de erro sem saida.
-- `AdminService.deleteProfile` fazia exatamente isso. Entao a exclusao de
-- usuario tem de apagar o `auth.users`, e isso exige a chave service_role —
-- que nunca pode estar dentro do APK. Dai a acao `apagar_usuarios` na Edge
-- Function `acesso`.
--
-- Senderista nao tem conta de autenticacao: um `delete` pela RLS resolve, e
-- a policy acima e a fronteira.
--
-- A conferencia de prontuario e feita NOS DOIS LADOS. A tela confere para
-- poder explicar; a Edge Function confere de novo porque tela e
-- conveniencia e a fronteira e o servidor.
-- ============================================================================


-- ============================================================================
-- PROVADO COM SESSAO SIMULADA (transacao revertida)
--
--   quem registrou atendimento pode_apagar      -> false
--   atendimentos contados                        -> 1
--   delete do perfil com atendimento             -> bloqueado pelo RESTRICT
--   atendimentos que sobreviveram                -> 1
--   perfil sem rastro pode_apagar                -> true
--   apagando auth.users, o profile cai em cascata-> true
--
-- Antes desta migracao, o terceiro caso teria APAGADO o atendimento.
-- ============================================================================
