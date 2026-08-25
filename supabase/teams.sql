-- Hakuna Connect — Equipes de "Legendários 3 Colinas".
--
-- 9 equipes: ADM, LOGISTICA, HAKUNAS, VOZ, INTERCESSAO, PRODUCAO, MIDIA,
-- EVENTOS, SEGURANCA — isoladas entre si, cada uma com admin próprio que
-- libera quem participa. Mais o canal geral "LEGENDARIOS 3 COLINAS",
-- aberto a todos automaticamente.
--
-- HAKUNAS mantém toda a infraestrutura já existente (top_hakunas, chat,
-- atendimento, despacho etc.) sem nenhuma mudança — este arquivo só cobre
-- as 8 equipes novas + o canal geral, pra não arriscar quebrar o que já
-- está testado em produção. Ver Team.hasOwnInfrastructure no app.

create type public.team_key as enum (
  'adm', 'logistica', 'voz', 'intercessao', 'producao', 'midia', 'eventos', 'seguranca', 'geral'
);

-- ============ vínculo pessoa <-> equipe, por Top ============
--
-- Igual ao padrão já usado em top_hakunas: "released" é quem o admin da
-- equipe efetivamente liberou pra participar. is_team_admin marca quem
-- administra ESSA equipe especificamente (não é o admin global do app) —
-- só o admin global ou um admin já existente da equipe pode conceder isso,
-- então o admin global precisa ser quem bootstrapa o primeiro admin de
-- cada equipe nova.
create table public.top_team_members (
  id bigint generated always as identity primary key,
  top_id uuid not null references public.tops (id) on delete cascade,
  team public.team_key not null,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  is_team_admin boolean not null default false,
  released boolean not null default false,
  created_at timestamptz not null default now(),
  unique (top_id, team, profile_id)
);

create index top_team_members_lookup_idx on public.top_team_members (top_id, team, profile_id);

alter table public.top_team_members enable row level security;

-- Funções auxiliares (security definer) — mesmo padrão de is_admin() em
-- schema.sql: bypassam RLS na consulta interna pra não causar recursão
-- (top_team_members referenciando a própria RLS de top_team_members).
create or replace function public.is_team_admin(p_top_id uuid, p_team public.team_key)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.top_team_members m
    where m.top_id = p_top_id
      and m.team = p_team
      and m.profile_id = auth.uid()
      and m.is_team_admin = true
      and m.released = true
  );
$$;

create or replace function public.is_team_member(p_top_id uuid, p_team public.team_key)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.top_team_members m
    where m.top_id = p_top_id
      and m.team = p_team
      and m.profile_id = auth.uid()
      and m.released = true
  );
$$;

-- Usado pelo canal geral (aberto a todo perfil aprovado, sem precisar de
-- linha em top_team_members) e como checagem de "faz parte da comunidade".
create or replace function public.is_approved()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (select 1 from public.profiles p where p.id = auth.uid() and p.approved = true);
$$;

-- SELECT: minha própria linha (pra saber meu status), ou linha de gente da
-- MESMA equipe liberada (roster), ou admin daquela equipe (pendentes +
-- liberados), ou admin global do app.
create policy "top_team_members_select" on public.top_team_members
  for select using (
    profile_id = auth.uid()
    or public.is_team_admin(top_id, team)
    or (released = true and public.is_team_member(top_id, team))
    or public.is_admin()
  );

-- Só admin daquela equipe (ou admin global) libera/promove/remove gente —
-- ninguém se auto-libera nem se auto-promove.
create policy "top_team_members_write" on public.top_team_members
  for all using (public.is_team_admin(top_id, team) or public.is_admin())
  with check (public.is_team_admin(top_id, team) or public.is_admin());

-- Admin de uma equipe (ou admin global) busca perfis aprovados por nome/
-- número do Legendários pra decidir quem convidar — só devolve identidade
-- básica, nunca dado médico (comorbidades, peso, registro), já que essas
-- equipes não são a Hakunas.
create or replace function public.searchable_profiles(p_top_id uuid, p_team public.team_key, p_query text default '')
returns table (id uuid, full_name text, legendarios_number text)
language sql stable security definer set search_path = public
as $$
  select p.id, p.full_name, p.legendarios_number
  from public.profiles p
  where (public.is_team_admin(p_top_id, p_team) or public.is_admin())
    and p.approved = true
    and (p_query = '' or p.full_name ilike '%' || p_query || '%' or p.legendarios_number ilike '%' || p_query || '%')
  order by p.full_name
  limit 50;
$$;

-- Resolve nome/número pra uma lista de ids dentro do contexto de uma
-- equipe (roster e chat) — quem chama precisa ser membro liberado, admin
-- daquela equipe, admin global, ou (pro canal geral) só precisa estar
-- aprovado. Mesma lógica de não vazar dado médico: só identidade básica.
create or replace function public.member_names_for_team(p_top_id uuid, p_team public.team_key, p_ids uuid[])
returns table (id uuid, full_name text, legendarios_number text)
language sql stable security definer set search_path = public
as $$
  select p.id, p.full_name, p.legendarios_number
  from public.profiles p
  where p.id = any(p_ids)
    and (
      (p_team = 'geral' and public.is_approved())
      or public.is_team_member(p_top_id, p_team)
      or public.is_team_admin(p_top_id, p_team)
      or public.is_admin()
    );
$$;

-- ============ chat por equipe ============
--
-- Uma equipe não vê a conversa da outra. O canal 'geral' é aberto a todo
-- aprovado, sem precisar de linha em top_team_members.
create table public.team_messages (
  id bigint generated always as identity primary key,
  top_id uuid not null references public.tops (id) on delete cascade,
  team public.team_key not null,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now()
);

create index team_messages_thread_idx on public.team_messages (top_id, team, created_at);

alter table public.team_messages enable row level security;

create policy "team_messages_select_member" on public.team_messages
  for select using (
    (
      team = 'geral'
      and public.is_approved()
      and exists (select 1 from public.tops t where t.id = top_id and t.status <> 'draft')
    )
    or public.is_team_member(top_id, team)
    or public.is_team_admin(top_id, team)
    or public.is_admin()
  );

create policy "team_messages_insert_member" on public.team_messages
  for insert with check (
    sender_id = auth.uid()
    and (
      (
        team = 'geral'
        and public.is_approved()
        and exists (select 1 from public.tops t where t.id = top_id and t.status <> 'draft')
      )
      or public.is_team_member(top_id, team)
      or public.is_team_admin(top_id, team)
    )
  );

alter publication supabase_realtime add table public.team_messages;

-- ============ fix: tops não ficava visível pra quem só está numa equipe ============
--
-- tops_select_linked (schema.sql) só considerava top_hakunas/top_senderistas
-- — quem só participa de uma equipe nova (ex: só SEGURANCA) nunca via o Top
-- na lista. Também abre visibilidade geral pra Tops não-draft (o canal
-- "aberto a todos" não faz sentido se ninguém sem outro vínculo consegue
-- nem ver que o Top existe) e corrige is_admin() (o original checava só
-- role='admin', perdendo quem é admin master sem essa role).
drop policy if exists "tops_select_linked" on public.tops;
create policy "tops_select_linked" on public.tops
  for select using (
    exists (select 1 from public.top_hakunas th where th.top_id = tops.id and th.profile_id = auth.uid())
    or exists (select 1 from public.top_senderistas ts where ts.top_id = tops.id and ts.profile_id = auth.uid())
    -- top_team_members tem sua própria coluna "id" (bigint) — sem
    -- qualificar como tops.id, o "id" nu resolvia pra tm.id (bigint) em
    -- vez do id (uuid) do Top, e dava "operator does not exist: uuid =
    -- bigint" na criação da policy.
    or exists (select 1 from public.top_team_members tm where tm.top_id = tops.id and tm.profile_id = auth.uid())
    or (status <> 'draft' and public.is_approved())
    or public.is_admin()
  );
