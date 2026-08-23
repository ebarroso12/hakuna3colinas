-- CORREÇÕES CRÍTICAS (P0) — rodar uma vez no SQL Editor do projeto Supabase
-- (https://supabase.com/dashboard/project/jitfbambhmfnqiatwoud/sql/new)
--
-- Sem isso: (1) Hakunas e Senderistas não conseguem usar o app de verdade
-- (RLS bloqueia tudo por padrão), e (2) qualquer usuário logado consegue
-- virar admin sozinho.

-- P0 fix 1: top_hakunas e top_senderistas tinham RLS ativado sem NENHUMA
-- policy, o que bloqueava (fail-closed) as subqueries de outras policies que
-- dependem dessas tabelas (tops_select_linked, hakuna_positions_*, atendimentos_*).
create policy "top_hakunas_select_own_or_admin" on public.top_hakunas
  for select using (
    profile_id = auth.uid()
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
  );

create policy "top_senderistas_select_own_or_admin" on public.top_senderistas
  for select using (
    profile_id = auth.uid()
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
  );

-- P0 fix 2: profiles_update_own permitia trocar a própria coluna "role"
-- (ex: senderista virar admin), pois só validava o dono da linha, nunca o
-- conteúdo. Adiciona with check impedindo alteração de role pelo próprio usuário.
drop policy if exists "profiles_update_own" on public.profiles;
create policy "profiles_update_own" on public.profiles
  for update using (id = auth.uid())
  with check (
    id = auth.uid()
    and role = (select role from public.profiles where id = auth.uid())
  );
