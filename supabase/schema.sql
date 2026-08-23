-- Hakuna Connect - schema inicial (Supabase / Postgres + PostGIS)
-- Conceito: Legendários promove eventos ("Tops"). Cada Top tem médicos
-- responsáveis ("Hakunas") e participantes externos ("Senderistas").
-- A funcionalidade central é rastrear a posição dos Hakunas em tempo real,
-- com acesso liberado por Top (evento).

-- Perfil de usuário (1:1 com auth.users)
create type public.user_role as enum ('admin', 'hakuna', 'senderista');

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null,
  role public.user_role not null default 'senderista',
  phone text,
  medical_registry text, -- CRM, apenas para hakunas
  created_at timestamptz not null default now()
);

-- Eventos ("Top")
create type public.top_status as enum ('draft', 'active', 'finished');

create table public.tops (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  status public.top_status not null default 'draft',
  starts_at timestamptz,
  ends_at timestamptz,
  created_at timestamptz not null default now()
);

-- Hakunas liberados/vinculados a um Top específico
create table public.top_hakunas (
  top_id uuid not null references public.tops (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  released boolean not null default false, -- "liberado por top"
  assigned_at timestamptz not null default now(),
  primary key (top_id, profile_id)
);

-- Senderistas inscritos em um Top
create table public.top_senderistas (
  top_id uuid not null references public.tops (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  registered_at timestamptz not null default now(),
  primary key (top_id, profile_id)
);

-- Posições em tempo real dos Hakunas (histórico + última posição).
-- lat/lng em colunas simples (em vez de PostGIS geography) para que o
-- Realtime do Supabase entregue os valores prontos, sem parsing de WKB.
create table public.hakuna_positions (
  id bigint generated always as identity primary key,
  top_id uuid not null references public.tops (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  latitude double precision not null,
  longitude double precision not null,
  recorded_at timestamptz not null default now()
);

create index hakuna_positions_top_profile_idx
  on public.hakuna_positions (top_id, profile_id, recorded_at desc);

-- Tags NFC (pulseiras/cartões de identificação de senderista/hakuna)
create table public.nfc_tags (
  id uuid primary key default gen_random_uuid(),
  tag_uid text not null unique,
  owner_profile_id uuid references public.profiles (id) on delete set null,
  top_id uuid references public.tops (id) on delete set null,
  payload jsonb,
  created_at timestamptz not null default now()
);

-- ============ RLS ============

alter table public.profiles enable row level security;
alter table public.tops enable row level security;
alter table public.top_hakunas enable row level security;
alter table public.top_senderistas enable row level security;
alter table public.hakuna_positions enable row level security;
alter table public.nfc_tags enable row level security;

-- profiles: cada um vê/edita o próprio; admin vê todos
create policy "profiles_select_own_or_admin" on public.profiles
  for select using (
    id = auth.uid()
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
  );

-- with check impede o usuário de trocar a própria "role" (ex: senderista
-- virar admin) — sem isso, RLS de UPDATE só valida a linha, não o conteúdo.
create policy "profiles_update_own" on public.profiles
  for update using (id = auth.uid())
  with check (
    id = auth.uid()
    and role = (select role from public.profiles where id = auth.uid())
  );

-- tops: qualquer usuário autenticado vinculado ao top (hakuna ou senderista) pode ver
create policy "tops_select_linked" on public.tops
  for select using (
    exists (select 1 from public.top_hakunas th where th.top_id = id and th.profile_id = auth.uid())
    or exists (select 1 from public.top_senderistas ts where ts.top_id = id and ts.profile_id = auth.uid())
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
  );

-- top_hakunas/top_senderistas precisam de policy própria: RLS sem nenhuma
-- policy nega tudo por padrão, inclusive quando a tabela é referenciada
-- dentro de subquery de outra policy (como acima e abaixo) — sem isso,
-- tops_select_linked e hakuna_positions_* nunca liberam nada pra ninguém.
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

-- hakuna_positions: só hakunas/admins do MESMO top liberado veem posições
-- (o núcleo do "liberado por top" + privacidade do senderista)
create policy "hakuna_positions_select_same_top" on public.hakuna_positions
  for select using (
    exists (
      select 1 from public.top_hakunas th
      where th.top_id = hakuna_positions.top_id
        and th.profile_id = auth.uid()
        and th.released = true
    )
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
  );

-- só o próprio hakuna insere a própria posição, e só se estiver liberado no top ativo
create policy "hakuna_positions_insert_self" on public.hakuna_positions
  for insert with check (
    profile_id = auth.uid()
    and exists (
      select 1 from public.top_hakunas th
      join public.tops t on t.id = th.top_id
      where th.top_id = hakuna_positions.top_id
        and th.profile_id = auth.uid()
        and th.released = true
        and t.status = 'active'
    )
  );

-- nfc_tags: dono do tag ou admin
create policy "nfc_tags_select_owner_or_admin" on public.nfc_tags
  for select using (
    owner_profile_id = auth.uid()
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
  );

create policy "nfc_tags_insert_admin" on public.nfc_tags
  for insert with check (
    exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
  );

-- Habilita Realtime na tabela de posições
alter publication supabase_realtime add table public.hakuna_positions;
