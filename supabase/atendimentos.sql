-- Hakuna Connect - Atendimentos (comunicação em tempo real entre a equipe)
--
-- Conceito: quando um Hakuna abre um atendimento (socorro a um Senderista ou
-- Legendário), todos os outros Hakunas liberados no mesmo Top ficam cientes
-- na hora (via Realtime) e podem localizar o atendimento pelo GPS registrado
-- no momento da abertura.
--
-- Rodar DEPOIS de schema.sql já ter sido aplicado.

create type public.atendimento_status as enum ('aberto', 'em_andamento', 'encerrado');

create table public.atendimentos (
  id uuid primary key default gen_random_uuid(),
  top_id uuid not null references public.tops (id) on delete cascade,
  opened_by uuid not null references public.profiles (id) on delete cascade,
  senderista_id uuid references public.profiles (id) on delete set null, -- opcional: quem está sendo atendido, se cadastrado
  notes text,
  status public.atendimento_status not null default 'aberto',
  latitude double precision not null,
  longitude double precision not null,
  opened_at timestamptz not null default now(),
  closed_at timestamptz
);

create index atendimentos_top_status_idx
  on public.atendimentos (top_id, status, opened_at desc);

alter table public.atendimentos enable row level security;

-- Qualquer Hakuna liberado (ou admin) do mesmo Top vê todos os atendimentos
-- do Top — é isso que garante a comunicação entre a equipe.
create policy "atendimentos_select_same_top" on public.atendimentos
  for select using (
    exists (
      select 1 from public.top_hakunas th
      where th.top_id = atendimentos.top_id
        and th.profile_id = auth.uid()
        and th.released = true
    )
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
  );

-- Só um Hakuna liberado no Top ativo pode abrir atendimento, e só em nome
-- de si mesmo (opened_by = quem está autenticado).
create policy "atendimentos_insert_self" on public.atendimentos
  for insert with check (
    opened_by = auth.uid()
    and exists (
      select 1 from public.top_hakunas th
      join public.tops t on t.id = th.top_id
      where th.top_id = atendimentos.top_id
        and th.profile_id = auth.uid()
        and th.released = true
        and t.status = 'active'
    )
  );

-- Só quem abriu o atendimento (ou admin) pode atualizar status/encerrar.
create policy "atendimentos_update_owner_or_admin" on public.atendimentos
  for update using (
    opened_by = auth.uid()
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
  );

-- Habilita Realtime: é isso que dispara a notificação em tempo real pros
-- outros Hakunas quando um atendimento é aberto (enquanto o app estiver
-- aberto/em foreground). Notificação push com app fechado exigiria um
-- serviço adicional (ex: Firebase Cloud Messaging via Edge Function) — não
-- incluído aqui.
alter publication supabase_realtime add table public.atendimentos;
