-- ===========================================================================
-- `atendimentos.participant_id` E AS DUAS FUNÇÕES DE EXCLUSÃO
--
-- Peças 12, 10 e 11 da série de objetos que só existiam em produção.
-- Achadas em 23/11/2026, exercitando o app pelos caminhos reais em vez de
-- conferir objeto por objeto — que é como as doze primeiras passaram.
--
-- ---------------------------------------------------------------------------
-- 1. `atendimentos.participant_id` — O MÓDULO CLÍNICO INTEIRO
--
-- A tabela viva tem `senderista_id` (aponta para `profiles`) e NÃO tem
-- `participant_id` (aponta para a FICHA, `top_participants`). O app usa a
-- segunda, nas duas direções e sem tolerar nulo:
--
--     participantId: map['participant_id'] as String      // fromMap
--     'participant_id': participantId,                    // toMap
--
-- Então, hoje: **registrar atendimento falha** (PostgREST não acha a
-- coluna) e **ler o histórico do servidor levanta exceção** (cast de null
-- para String). A função mais importante do app — triagem e prontuário de
-- gente real — não funciona, e o `painel_do_top` morre junto, porque
-- conta `count(distinct participant_id)`.
--
-- Não é renomear `senderista_id`. São dois vínculos diferentes e os dois
-- existem de propósito: a FICHA existe para quem não tem conta (é o que
-- faz o prontuário funcionar antes de a pessoa se cadastrar), e o PERFIL
-- existe só para quem se cadastrou. Ligar o atendimento no perfil deixaria
-- sem prontuário exatamente quem chega sem conta — a maioria, no começo
-- do evento.
--
-- NULÁVEL de propósito, apesar de o app exigir valor: é o que permite o
-- `on delete set null`. A garantia de que não aparece nulo não está na
-- coluna, está na trava de exclusão abaixo — apagar ficha com atendimento
-- é recusado justamente para não deixar prontuário órfão. Ver
-- `exclusao_protegida.sql:76`.
--
-- ---------------------------------------------------------------------------
-- 2. `dependencias_do_perfil` / `dependencias_do_senderista`
--
-- As duas são chamadas por `ExclusaoService` (`lib/services/
-- exclusao_service.dart:103` e `:133`) e por `acesso/apagar_usuarios`
-- (`index.ts:936`), e NADA no repositório as cria — `exclusao_protegida.sql`
-- só cria as duas policies de delete. Sem elas, **o admin master não apaga
-- ninguém**: a Edge Function para em
--
--     Could not find the function public.dependencias_do_perfil(p_ids)
--
-- antes de qualquer verificação. Confirmado chamando de verdade.
--
-- O CONTRATO NÃO FOI INVENTADO. Cada coluna aqui é exigida por nome por
-- quem consome:
--
--   `dependencias_do_perfil`  -> profile_id, pode_apagar,
--      atendimentos_feitos, atendimentos_fechados, afericoes_feitas,
--      afericoes_proprias, auditoria, tags_emitidas, alarmes
--   `dependencias_do_senderista` -> participante_id, pode_apagar,
--      atendimentos
--
-- `outros_vinculos` é adição minha, e é necessária para a função não
-- MENTIR. O `ExclusaoService` monta o motivo a partir das sete contagens
-- e, se não houver nenhuma e ainda assim estiver bloqueado, escreve "é o
-- administrador master". Mas há nove outras referências bloqueantes a
-- `profiles` sem rótulo próprio (`anotacoes.autor_id`,
-- `top_participants.registered_by`, `atendimento_fotos.taken_by`,
-- `tag_leituras.lida_por`, `top_imagens.enviado_por`,
-- `participant_tags.revoked_by`, `top_permissoes.definido_por`,
-- `tops.access_code_set_by`, `access_requests.handled_by`). Sem contá-las,
-- quem fosse bloqueado por uma delas apareceria na tela como "é o
-- administrador master" — e o admin tentaria de novo para sempre.
--
-- `security definer` é obrigatório: as contagens atravessam `atendimentos`
-- e `audit_log`, que a RLS fecha. Quem pode CHAMAR é só admin — a checagem
-- está no corpo, porque contar prontuário de terceiros é oráculo sobre
-- dado clínico.
--
-- ---------------------------------------------------------------------------
-- A TRAVA TEM DE DEIXAR O `service_role` PASSAR, E `auth.uid()` NÃO SERVE
--
-- A primeira versão desta trava era `if not is_admin() then raise`, e
-- quebrou a Edge Function: `acesso/apagar_usuarios` chama pelo cliente de
-- `service_role`, onde `auth.uid()` é NULO — então `is_admin()` dá falso e
-- a exclusão morria em "apenas administradores" mesmo pedida pelo admin
-- master. É a mesma armadilha que o `CLAUDE.md` registra para o trigger de
-- `profiles`: "`auth.uid() is null` passa direto. É `service_role`".
--
-- Mas "deixar passar quem tem `auth.uid()` nulo" seria ERRADO aqui: a
-- chave ANÔNIMA também produz `auth.uid()` nulo, e ela está dentro do APK.
-- Quem passa é quem se apresenta como `service_role` no JWT.
--
-- `current_user` não serve: dentro de `security definer` ele é o DONO da
-- função, não quem chamou. `session_user` é o papel da conexão do
-- PostgREST. O que sobrevive até aqui é o claim do JWT.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. A coluna que liga o atendimento à FICHA
-- ---------------------------------------------------------------------------
alter table public.atendimentos
  add column if not exists participant_id uuid
    references public.top_participants (id) on delete set null;

comment on column public.atendimentos.participant_id is
  'A FICHA de quem foi atendido (`top_participants`), nao o perfil. '
  'Existe para quem nao tem conta, e e por isso que o prontuario funciona '
  'antes do autocadastro. `senderista_id` e outra coisa: o PERFIL, se '
  'houver. Nulavel so para permitir o `set null`; a trava de exclusao '
  'impede que isso aconteca.';

create index if not exists idx_atendimentos_participante
  on public.atendimentos (top_id, participant_id, opened_at desc);

-- ---------------------------------------------------------------------------
-- 2. O que seria perdido ao apagar um PERFIL
-- ---------------------------------------------------------------------------
create or replace function public.dependencias_do_perfil(p_ids uuid[])
returns table (
  profile_id            uuid,
  pode_apagar           boolean,
  atendimentos_feitos   bigint,
  atendimentos_fechados bigint,
  afericoes_feitas      bigint,
  afericoes_proprias    bigint,
  auditoria             bigint,
  tags_emitidas         bigint,
  alarmes               bigint,
  outros_vinculos       bigint
)
language plpgsql
stable
security definer
set search_path to 'public'
as $fn$
declare
  -- O claim do JWT sobrevive dentro do `security definer`; `current_user`
  -- nao (vira o dono da funcao). Ver a nota no cabecalho.
  v_papel text := nullif(current_setting('request.jwt.claims', true), '')::json ->> 'role';
begin
  if not (public.is_admin() or v_papel = 'service_role') then
    raise exception 'apenas administradores' using errcode = '42501';
  end if;

  return query
  with alvo as (select unnest(p_ids) as id),
  c as (
    select
      a.id as pid,
      (select count(*) from public.profiles pr
        where pr.id = a.id and pr.is_master_admin) as eh_master,
      (select count(*) from public.atendimentos t where t.opened_by = a.id) as at_feitos,
      (select count(*) from public.atendimentos t where t.closed_by = a.id) as at_fechados,
      (select count(*) from public.vital_signs v where v.recorded_by = a.id) as af_feitas,
      (select count(*) from public.vital_signs v where v.profile_id  = a.id) as af_proprias,
      (select count(*) from public.audit_log l where l.actor_id = a.id) as audit,
      (select count(*) from public.participant_tags g where g.issued_by = a.id) as tags,
      (select count(*) from public.top_alerts al where al.sender_id = a.id) as alarm,
      (
        (select count(*) from public.anotacoes an where an.autor_id = a.id)
      + (select count(*) from public.top_participants tp where tp.registered_by = a.id)
      + (select count(*) from public.atendimento_fotos f where f.taken_by = a.id)
      + (select count(*) from public.tag_leituras tl where tl.lida_por = a.id)
      + (select count(*) from public.top_imagens ti where ti.enviado_por = a.id)
      + (select count(*) from public.participant_tags g2 where g2.revoked_by = a.id)
      + (select count(*) from public.top_permissoes pp where pp.definido_por = a.id)
      + (select count(*) from public.tops tt where tt.access_code_set_by = a.id)
      + (select count(*) from public.access_requests ar where ar.handled_by = a.id)
      ) as outros
    from alvo a
  )
  select
    c.pid,
    -- Admin master nunca. Rastro clinico, de auditoria ou de pulseira
    -- nunca: a regra do projeto e "apaga quem nao deixou rastro; quem
    -- deixou, desativa".
    (c.eh_master = 0
      and c.at_feitos = 0 and c.at_fechados = 0
      and c.af_feitas = 0 and c.af_proprias = 0
      and c.audit = 0 and c.tags = 0 and c.alarm = 0
      and c.outros = 0),
    c.at_feitos, c.at_fechados, c.af_feitas, c.af_proprias,
    c.audit, c.tags, c.alarm, c.outros
  from c;
end;
$fn$;

revoke all on function public.dependencias_do_perfil(uuid[]) from public;
grant execute on function public.dependencias_do_perfil(uuid[]) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 3. O que seria perdido ao apagar um SENDERISTA (a ficha)
-- ---------------------------------------------------------------------------
create or replace function public.dependencias_do_senderista(p_ids uuid[])
returns table (
  participante_id uuid,
  pode_apagar     boolean,
  atendimentos    bigint
)
language plpgsql
stable
security definer
set search_path to 'public'
as $fn$
declare
  -- O claim do JWT sobrevive dentro do `security definer`; `current_user`
  -- nao (vira o dono da funcao). Ver a nota no cabecalho.
  v_papel text := nullif(current_setting('request.jwt.claims', true), '')::json ->> 'role';
begin
  if not (public.is_admin() or v_papel = 'service_role') then
    raise exception 'apenas administradores' using errcode = '42501';
  end if;

  return query
  with alvo as (select unnest(p_ids) as id),
  c as (
    select
      a.id as pid,
      (select count(*) from public.atendimentos t where t.participant_id = a.id) as ats
    from alvo a
  )
  -- SO atendimento trava, e e decisao registrada no app: pulseira cai em
  -- cascata (e daquela pessoa) e leitura vira `set null`, mas leitura sem
  -- participante ainda responde "quando e onde alguem passou", que e para
  -- o que ela serve. Atendimento orfao nao: e prontuario que ninguem sabe
  -- de quem e, pior que apagar.
  select c.pid, (c.ats = 0), c.ats from c;
end;
$fn$;

revoke all on function public.dependencias_do_senderista(uuid[]) from public;
grant execute on function public.dependencias_do_senderista(uuid[]) to authenticated, service_role;

-- Conferência:
--   select * from public.dependencias_do_perfil(array[]::uuid[]);  -> 0 linhas
--   select count(*) from information_schema.columns
--    where table_name='atendimentos' and column_name='participant_id'; -> 1
