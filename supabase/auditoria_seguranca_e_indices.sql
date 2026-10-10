-- ============================================================================
-- Aplicado em producao em 09/10/2026, a partir dos advisors do Supabase.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. SEGURANCA
--
-- cleanup_expired_messages() e SECURITY DEFINER e NAO checa quem chama.
-- Exposta em /rest/v1/rpc/, qualquer anonimo podia disparar o DELETE das
-- mensagens. E manutencao: so service_role deve rodar.
--
-- handle_new_user() e funcao de TRIGGER, nao deveria ser endpoint. Revogar
-- nao quebra o cadastro: o Postgres nao checa EXECUTE ao disparar trigger
-- (confirmado - on_auth_user_created segue ativo).
--
-- ARMADILHA: revogar do papel `anon` NAO basta. Funcoes nascem com EXECUTE
-- concedido a PUBLIC e anon/authenticated herdam dai. O primeiro revoke que
-- rodei nao teve efeito nenhum; so apareceu conferindo
-- has_function_privilege depois.
-- ----------------------------------------------------------------------------

revoke execute on function public.cleanup_expired_messages() from public;
revoke execute on function public.handle_new_user() from public;
grant  execute on function public.cleanup_expired_messages() to service_role;

-- NAO revogadas, de proposito:
--
-- is_admin / is_team_member / is_approved / etc sao chamadas DENTRO das
-- policies de RLS - revoga-las quebraria o app inteiro. E sao seguras:
-- devolvem booleano sobre QUEM CHAMA, entao anonimo sempre recebe false.
--
-- searchable_profiles e member_names_for_team apareceram no advisor mas sao
-- falso-positivo: apesar de SECURITY DEFINER, checam is_admin() /
-- is_team_member() internamente, entao anonimo recebe ZERO LINHAS.
-- Verificado lendo a definicao das duas.


-- ----------------------------------------------------------------------------
-- 2. DESEMPENHO - foreign keys sem indice
--
-- FK sem indice faz o Postgres varrer a tabela a cada join e a cada DELETE
-- do lado pai. hakuna_positions ganha uma linha a cada 15 m caminhados,
-- entao isso cresce junto com a trilha.
-- ----------------------------------------------------------------------------

create index if not exists idx_positions_profile
  on public.hakuna_positions (profile_id, recorded_at desc);
create index if not exists idx_atendimentos_opened_by
  on public.atendimentos (opened_by);
create index if not exists idx_atendimentos_assigned_to
  on public.atendimentos (assigned_to) where assigned_to is not null;
create index if not exists idx_fotos_atendimento
  on public.atendimento_fotos (atendimento_id);
create index if not exists idx_fotos_top
  on public.atendimento_fotos (top_id);
create index if not exists idx_participants_registrado_por
  on public.top_participants (registered_by);
create index if not exists idx_participants_perfil
  on public.top_participants (linked_profile_id) where linked_profile_id is not null;
create index if not exists idx_team_members_perfil
  on public.top_team_members (profile_id);
create index if not exists idx_team_messages_sender
  on public.team_messages (sender_id);
create index if not exists idx_tags_top
  on public.participant_tags (top_id);
create index if not exists idx_leituras_por
  on public.tag_leituras (lida_por, lida_em desc);
create index if not exists idx_hakunas_perfil
  on public.top_hakunas (profile_id);
create index if not exists idx_vitals_perfil
  on public.vital_signs (profile_id, recorded_at desc);


-- ----------------------------------------------------------------------------
-- 3. DESEMPENHO - auth.uid() reavaliado linha a linha
--
-- `auth.uid()` solto numa policy e recalculado A CADA LINHA. Envolvido em
-- `(select auth.uid())`, o Postgres calcula uma vez e reusa.
--
-- Corrigido so nas tabelas que mais crescem. As outras ~35 policies com o
-- mesmo padrao ficaram: sao tabelas pequenas, e mexer em controle de acesso
-- sem necessidade e risco que nao paga o ganho.
-- ----------------------------------------------------------------------------

drop policy if exists hakuna_positions_insert_self on public.hakuna_positions;
create policy hakuna_positions_insert_self on public.hakuna_positions
for insert with check (profile_id = (select auth.uid()));

drop policy if exists atendimentos_insert_self on public.atendimentos;
create policy atendimentos_insert_self on public.atendimentos
for insert with check (
  opened_by = (select auth.uid())
  and exists (
    select 1 from public.top_hakunas h
    where h.top_id = atendimentos.top_id
      and h.profile_id = (select auth.uid())
      and h.released = true
  )
);

drop policy if exists tag_leituras_insert on public.tag_leituras;
create policy tag_leituras_insert on public.tag_leituras
for insert with check (lida_por = (select auth.uid()));

drop policy if exists tag_leituras_select on public.tag_leituras;
create policy tag_leituras_select on public.tag_leituras
for select using (lida_por = (select auth.uid()) or is_admin());

drop policy if exists atendimento_fotos_insert on public.atendimento_fotos;
create policy atendimento_fotos_insert on public.atendimento_fotos
for insert with check (
  taken_by = (select auth.uid())
  and (
    is_admin()
    or exists (
      select 1 from public.top_hakunas h
      where h.top_id = atendimento_fotos.top_id
        and h.profile_id = (select auth.uid())
        and h.released = true
    )
  )
);

drop policy if exists atendimento_fotos_select on public.atendimento_fotos;
create policy atendimento_fotos_select on public.atendimento_fotos
for select using (
  taken_by = (select auth.uid())
  or is_admin()
  or exists (
    select 1 from public.top_hakunas h
    where h.top_id = atendimento_fotos.top_id
      and h.profile_id = (select auth.uid())
      and h.released = true
  )
);


-- ----------------------------------------------------------------------------
-- 4. DIVIDA REGISTRADA, nao resolvida
--
-- nfc_tags foi superada por participant_tags (token opaco e revogavel em
-- vez do tag_uid clonavel). Esta vazia e sem uso no app, mas segue com 3
-- policies e duas permissivas duplicadas no INSERT. Dropar e irreversivel
-- e precisa de decisao do usuario.
-- ----------------------------------------------------------------------------
