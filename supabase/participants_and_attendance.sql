-- Hakuna Connect — Fase 1 (modelo/banco) da evolução pra plataforma
-- operacional. NÃO aplicado em produção ainda — só a migração.
--
-- Decisão arquitetural (ver auditoria): "Senderista" (profiles.role =
-- 'senderista') já É o conceito de "participante" do produto, mas
-- profiles.id referencia auth.users.id 1:1 — todo Senderista hoje PRECISA
-- de conta de login completa antes de existir. Isso impede o "cadastro
-- rápido de participante" que o Hakuna precisa fazer em campo (centenas de
-- pessoas por Top, a imensa maioria nunca vai abrir o app).
--
-- Em vez de afrouxar profiles.id -> auth.users.id (mudaria RLS de TODAS as
-- tabelas existentes e o app inteiro assume profile.id == auth.uid() —
-- risco alto demais pra uma migração de uma tacada só, especialmente logo
-- depois de resolver o bug de login), criamos top_participants: um cadastro
-- leve, SEM exigir conta, com vínculo opcional a um profiles real (quando o
-- participante depois cria conta própria ou já é um Senderista cadastrado).
-- Não duplica dado: linked_profile_id resolve "esse participante é a
-- mesma pessoa que o Senderista X" quando aplicável.
--
-- Rodar DEPOIS de schema.sql, admin_master_and_triage.sql e
-- fix_profiles_rls_recursion.sql já terem sido aplicados.

-- ============ participantes (cadastro rápido, sem exigir login) ============

create table public.top_participants (
  id uuid primary key default gen_random_uuid(),
  top_id uuid not null references public.tops (id) on delete cascade,
  -- Preenchido quando o participante é (ou depois vira) um Senderista com
  -- conta própria — null enquanto for só um cadastro rápido de campo.
  linked_profile_id uuid references public.profiles (id) on delete set null,
  participant_code text, -- número/código livre do participante, não único globalmente
  full_name text not null,
  nickname text,
  phone text,
  birth_date date,
  emergency_contact text,
  notes text,
  tag_uid text references public.nfc_tags (tag_uid) on delete set null,
  registered_by uuid not null references public.profiles (id),
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create index top_participants_top_idx on public.top_participants (top_id, active);
create unique index top_participants_tag_uid_idx on public.top_participants (tag_uid) where tag_uid is not null;

alter table public.top_participants enable row level security;

-- Hakunas liberados (ou admin) do mesmo Top veem/gerenciam os participantes.
create policy "top_participants_select_same_top" on public.top_participants
  for select using (
    exists (
      select 1 from public.top_hakunas th
      where th.top_id = top_participants.top_id
        and th.profile_id = auth.uid()
        and th.released = true
    )
    or public.is_admin()
  );

create policy "top_participants_insert_hakuna" on public.top_participants
  for insert with check (
    registered_by = auth.uid()
    and exists (
      select 1 from public.top_hakunas th
      where th.top_id = top_participants.top_id
        and th.profile_id = auth.uid()
        and th.released = true
    )
    or public.is_admin()
  );

create policy "top_participants_update_hakuna_or_admin" on public.top_participants
  for update using (
    exists (
      select 1 from public.top_hakunas th
      where th.top_id = top_participants.top_id
        and th.profile_id = auth.uid()
        and th.released = true
    )
    or public.is_admin()
  );

alter publication supabase_realtime add table public.top_participants;

-- ============ atendimentos: amplia o fluxo (tabela já existe, sem uso) ============
--
-- A tabela public.atendimentos já existe em produção (migração aplicada
-- antes, mas nenhuma tela do app a usa ainda). Em vez de recriar do zero,
-- estendemos o enum e adicionamos as colunas que faltam pro fluxo completo
-- pedido: NEW -> ... -> RESOLVED, prioridade, responsável e vínculo com
-- participante (além do já existente senderista_id, que aponta pra um
-- profile de Senderista com conta).

alter type public.atendimento_status add value if not exists 'reconhecido' after 'aberto';
alter type public.atendimento_status add value if not exists 'atribuido' after 'reconhecido';
alter type public.atendimento_status add value if not exists 'a_caminho' after 'atribuido';
alter type public.atendimento_status add value if not exists 'no_local' after 'a_caminho';
-- 'em_andamento' já existe (equivale a IN_PROGRESS)
alter type public.atendimento_status add value if not exists 'escalado' after 'em_andamento';
-- 'encerrado' já existe (equivale a RESOLVED)
alter type public.atendimento_status add value if not exists 'cancelado' after 'encerrado';

create type public.atendimento_priority as enum ('normal', 'atencao', 'urgencia');

alter table public.atendimentos
  add column if not exists priority public.atendimento_priority not null default 'normal',
  add column if not exists participant_id uuid references public.top_participants (id) on delete set null,
  add column if not exists assigned_to uuid references public.profiles (id) on delete set null,
  add column if not exists acknowledged_at timestamptz,
  add column if not exists assigned_at timestamptz,
  add column if not exists en_route_at timestamptz,
  add column if not exists on_scene_at timestamptz;

-- Quem apoia/está envolvido num atendimento além de quem abriu/foi atribuído.
create table public.attendance_members (
  attendance_id uuid not null references public.atendimentos (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  role text not null default 'apoio' check (role in ('responsavel', 'apoio')),
  joined_at timestamptz not null default now(),
  primary key (attendance_id, profile_id)
);

alter table public.attendance_members enable row level security;

create policy "attendance_members_select_same_top" on public.attendance_members
  for select using (
    exists (
      select 1 from public.atendimentos a
      join public.top_hakunas th on th.top_id = a.top_id
      where a.id = attendance_members.attendance_id
        and th.profile_id = auth.uid()
        and th.released = true
    )
    or public.is_admin()
  );

create policy "attendance_members_insert_self" on public.attendance_members
  for insert with check (
    profile_id = auth.uid()
    and exists (
      select 1 from public.atendimentos a
      join public.top_hakunas th on th.top_id = a.top_id
      where a.id = attendance_members.attendance_id
        and th.profile_id = auth.uid()
        and th.released = true
    )
  );

alter publication supabase_realtime add table public.attendance_members;

-- ============ notificações (preparação — sem FCM ainda, Fase 8) ============

create table public.notifications (
  id bigint generated always as identity primary key,
  top_id uuid not null references public.tops (id) on delete cascade,
  -- null = broadcast pra todos os Hakunas liberados do Top
  recipient_id uuid references public.profiles (id) on delete cascade,
  type text not null check (type in ('atendimento', 'apoio', 'urgencia', 'mensagem', 'sistema')),
  title text not null,
  body text,
  related_attendance_id uuid references public.atendimentos (id) on delete set null,
  related_alert_id bigint references public.top_alerts (id) on delete set null,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

create index notifications_recipient_idx on public.notifications (recipient_id, read_at, created_at desc);

alter table public.notifications enable row level security;

create policy "notifications_select_own_or_broadcast" on public.notifications
  for select using (
    recipient_id = auth.uid()
    or (
      recipient_id is null
      and exists (
        select 1 from public.top_hakunas th
        where th.top_id = notifications.top_id
          and th.profile_id = auth.uid()
          and th.released = true
      )
    )
    or public.is_admin()
  );

create policy "notifications_update_mark_read" on public.notifications
  for update using (recipient_id = auth.uid())
  with check (recipient_id = auth.uid());

alter publication supabase_realtime add table public.notifications;

-- ============ auditoria de ações críticas ============

create table public.audit_log (
  id bigint generated always as identity primary key,
  top_id uuid references public.tops (id) on delete set null,
  actor_id uuid not null references public.profiles (id),
  action text not null,
  entity_type text not null,
  entity_id text,
  metadata jsonb,
  created_at timestamptz not null default now()
);

create index audit_log_top_idx on public.audit_log (top_id, created_at desc);

alter table public.audit_log enable row level security;

-- Só admin lê auditoria (dado sensível de rastreabilidade, não operacional).
create policy "audit_log_select_admin" on public.audit_log
  for select using (public.is_admin());

-- Qualquer usuário autenticado pode registrar UMA ação em seu próprio nome
-- (actor_id = auth.uid()) — a app grava, nunca lê de volta pra si.
create policy "audit_log_insert_self" on public.audit_log
  for insert with check (actor_id = auth.uid());
