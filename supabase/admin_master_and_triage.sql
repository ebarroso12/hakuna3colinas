-- Hakuna Connect - Admin Master + edição de Top + sinais vitais + triagem
--
-- 1) Admin Master (Dr. Edson): um único usuário com poder total —
--    edita/deleta qualquer perfil, promove outros a admin, edita Top
--    (nome, número, local), gerencia atribuição de Hakunas/Senderistas.
--    Nenhum admin comum pode editar, deletar ou rebaixar o Admin Master —
--    isso é reforçado nas policies de RLS abaixo, não só na tela.
--
-- 2) Sinais vitais + triagem por cor, configurável pelo Admin Master.

-- Funções auxiliares (security definer) para não repetir a subquery de
-- "sou admin/master admin" em toda policy, e para evitar recursão de RLS.
create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and (p.role = 'admin' or p.is_master_admin)
  );
$$;

create or replace function public.is_master_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.profiles p where p.id = auth.uid() and p.is_master_admin
  );
$$;

-- ============ profiles: admin master + dados de triagem ============

alter table public.profiles add column is_master_admin boolean not null default false;
alter table public.profiles add column birth_date date;
-- Comorbidades relevantes pra triagem (ex: 'diabetes', 'hipertensao', 'cirurgia_previa').
-- Lista livre em vez de colunas fixas pra não exigir migração toda vez que
-- surgir uma comorbidade nova — a UI oferece opções pré-definidas.
alter table public.profiles add column comorbidities text[] not null default '{}';

-- Admin (comum ou master) pode editar qualquer perfil, MENOS o do admin
-- master — a não ser que quem está editando SEJA o admin master.
create policy "profiles_update_admin" on public.profiles
  for update using (
    public.is_admin()
    and (not profiles.is_master_admin or public.is_master_admin())
  )
  with check (
    -- só o admin master pode conceder papel 'admin' ou a flag de master admin
    (role <> 'admin' or public.is_master_admin())
    and (is_master_admin = false or public.is_master_admin())
  );

-- Mesma proteção pra delete: ninguém deleta o perfil do admin master.
create policy "profiles_delete_admin" on public.profiles
  for delete using (
    public.is_admin() and not profiles.is_master_admin
  );

-- ============ tops: número, local, e escrita por admin ============

alter table public.tops add column top_number text;
alter table public.tops add column location text;

create policy "tops_admin_insert" on public.tops
  for insert with check (public.is_admin());

create policy "tops_admin_update" on public.tops
  for update using (public.is_admin()) with check (public.is_admin());

create policy "tops_admin_delete" on public.tops
  for delete using (public.is_admin());

-- ============ top_hakunas / top_senderistas: gestão por admin ============
-- Hoje só existe policy de SELECT — admin não consegue liberar/atribuir
-- ninguém a um Top sem isso.

create policy "top_hakunas_admin_write" on public.top_hakunas
  for all using (public.is_admin()) with check (public.is_admin());

create policy "top_senderistas_admin_write" on public.top_senderistas
  for all using (public.is_admin()) with check (public.is_admin());

-- ============ sinais vitais ============

create table public.vital_signs (
  id bigint generated always as identity primary key,
  top_id uuid not null references public.tops (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  recorded_by uuid not null references public.profiles (id),
  heart_rate int,
  systolic_bp int,
  diastolic_bp int,
  spo2 int,
  temperature_c numeric,
  respiratory_rate int,
  notes text,
  recorded_at timestamptz not null default now()
);

create index vital_signs_top_profile_idx
  on public.vital_signs (top_id, profile_id, recorded_at desc);

alter table public.vital_signs enable row level security;

-- hakunas liberados (ou admin) do mesmo top veem os sinais; o próprio
-- paciente também vê os seus.
create policy "vital_signs_select_same_top_or_self" on public.vital_signs
  for select using (
    profile_id = auth.uid()
    or public.is_admin()
    or exists (
      select 1 from public.top_hakunas hk
      where hk.top_id = vital_signs.top_id
        and hk.profile_id = auth.uid()
        and hk.released = true
    )
  );

-- só hakuna liberado no top (registrando em nome próprio) ou admin insere.
create policy "vital_signs_insert_hakuna" on public.vital_signs
  for insert with check (
    recorded_by = auth.uid()
    and (
      public.is_admin()
      or exists (
        select 1 from public.top_hakunas hk
        where hk.top_id = vital_signs.top_id
          and hk.profile_id = auth.uid()
          and hk.released = true
      )
    )
  );

alter publication supabase_realtime add table public.vital_signs;

-- ============ regras de triagem (cor por idade + nº de comorbidades) ============
-- Avaliadas em ordem de priority (menor primeiro); a primeira regra cujo
-- paciente se encaixa (idade dentro da faixa E comorbidades <= max) decide
-- a cor. Editável só pelo admin master.

-- min/max_comorbidities são uma FAIXA fechada (ex: 0 a 0 = exatamente zero
-- comorbidades), não um teto solto — com "no máximo N" duas regras podem
-- reivindicar o mesmo paciente (ex: verde e amarelo ambos aceitando "até 1
-- comorbidade" nos mesmos 25-40 anos). Com faixa fechada cada combinação
-- de idade+comorbidades cai em UMA regra só, sem depender da ordem.
create table public.triage_rules (
  id bigint generated always as identity primary key,
  color text not null check (color in ('blue', 'green', 'yellow', 'red')),
  label text not null,
  min_age int not null default 0,
  max_age int, -- null = sem limite superior
  min_comorbidities int not null default 0,
  max_comorbidities int not null default 0,
  priority int not null,
  active boolean not null default true
);

alter table public.triage_rules enable row level security;

-- qualquer usuário autenticado lê as regras (precisa pra calcular a cor na tela)
create policy "triage_rules_select_authenticated" on public.triage_rules
  for select using (auth.role() = 'authenticated');

-- só o admin master edita as regras de triagem
create policy "triage_rules_write_master_admin" on public.triage_rules
  for all using (public.is_master_admin()) with check (public.is_master_admin());

-- Regras iniciais conforme definido pelo Dr. Edson (primeira regra que
-- bate, por priority crescente, decide a cor):
-- vermelho: acima de 40 anos, qualquer nº de comorbidades
-- azul: sem risco, até 25 anos, nenhuma comorbidade
-- verde: 25-40 anos sem comorbidade, OU até 25 anos com 1 comorbidade
-- amarelo: 25-40 anos com 1 comorbidade
-- vermelho (fallback): qualquer combinação não coberta acima (≥2
-- comorbidades em ≤40 anos) — em app médico, o padrão de segurança é
-- classificar pro lado mais cauteloso quando a regra não é clara.
insert into public.triage_rules (color, label, min_age, max_age, min_comorbidities, max_comorbidities, priority) values
  ('red', 'Vermelho — acima de 40 anos', 41, null, 0, 999, 1),
  ('blue', 'Azul — sem risco (até 25 anos, sem comorbidade)', 0, 25, 0, 0, 2),
  ('green', 'Verde — 25 a 40 anos sem comorbidade', 25, 40, 0, 0, 3),
  ('green', 'Verde — até 25 anos com 1 comorbidade', 0, 25, 1, 1, 4),
  ('yellow', 'Amarelo — 25 a 40 anos com 1 comorbidade', 25, 40, 1, 1, 5),
  ('red', 'Vermelho — 2 ou mais comorbidades (faixa não coberta acima)', 0, 40, 2, 999, 6);

-- Dr. Edson Barroso (número 203460) é o Admin Master do app.
update public.profiles set is_master_admin = true, role = 'admin'
where legendarios_number = '203460';
