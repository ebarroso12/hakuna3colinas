-- Corrige "infinite recursion detected in policy for relation profiles"
-- (Postgres 42P17). As policies profiles_select_own_or_admin,
-- profiles_update_own, top_hakunas_select_own_or_admin e
-- top_senderistas_select_own_or_admin consultavam a tabela profiles
-- diretamente por dentro de uma policy da própria profiles (ou de uma
-- tabela que a policy de profiles também consulta), causando recursão
-- infinita em QUALQUER select de profiles — login nunca completava.
-- Substitui os subselects diretos pelas funções SECURITY DEFINER que já
-- existiam (is_admin()) e cria my_profile_role() no mesmo padrão.

create or replace function public.my_profile_role()
returns public.user_role
language sql stable security definer set search_path = public
as $$
  select role from public.profiles where id = auth.uid();
$$;

alter policy "profiles_select_own_or_admin" on public.profiles
  using (id = auth.uid() or public.is_admin());

alter policy "profiles_update_own" on public.profiles
  using (id = auth.uid())
  with check (id = auth.uid() and role = public.my_profile_role());

alter policy "top_hakunas_select_own_or_admin" on public.top_hakunas
  using (profile_id = auth.uid() or public.is_admin());

alter policy "top_senderistas_select_own_or_admin" on public.top_senderistas
  using (profile_id = auth.uid() or public.is_admin());
