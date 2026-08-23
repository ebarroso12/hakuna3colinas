-- Sinal de alarme: qualquer Hakuna liberado no Top pode disparar em caso de
-- acidente ou atendimento crítico. Todos os Hakunas/admin do mesmo Top veem
-- em tempo real enquanto estiverem com a tela do Top aberta (não há push
-- notification neste momento — é uma limitação conhecida, não um bug).

create table public.top_alerts (
  id bigint generated always as identity primary key,
  top_id uuid not null references public.tops (id) on delete cascade,
  sender_id uuid not null references public.profiles (id),
  message text,
  latitude double precision,
  longitude double precision,
  created_at timestamptz not null default now()
);

create index top_alerts_top_idx on public.top_alerts (top_id, created_at desc);

alter table public.top_alerts enable row level security;

create policy "top_alerts_select_same_top" on public.top_alerts
  for select using (
    exists (
      select 1 from public.top_hakunas hk
      where hk.top_id = top_alerts.top_id
        and hk.profile_id = auth.uid()
        and hk.released = true
    )
    or public.is_admin()
  );

create policy "top_alerts_insert_hakuna" on public.top_alerts
  for insert with check (
    sender_id = auth.uid()
    and exists (
      select 1 from public.top_hakunas hk
      where hk.top_id = top_alerts.top_id
        and hk.profile_id = auth.uid()
        and hk.released = true
    )
  );

alter publication supabase_realtime add table public.top_alerts;
