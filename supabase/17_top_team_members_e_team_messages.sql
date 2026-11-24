-- ===========================================================================
-- AS DUAS TABELAS QUE SÓ EXISTIAM EM PRODUÇÃO
--
-- `top_team_members` e `team_messages` eram as duas últimas da lista dos
-- "objetos que só existiam em produção" do `CLAUDE.md`. O arquivo dizia,
-- desde 11/10/2026:
--
--   > Não as escrevi de memória de propósito — `create table` inventado
--   > parece fonte da verdade e diverge calado. Extrair com
--   > `pg_dump --schema-only` e versionar.
--
-- Feito em 24/11/2026. **Nada aqui foi escrito de memória**: colunas,
-- tipos, defaults, constraints, índices e as 12 policies saíram do catálogo
-- do banco em produção (`information_schema.columns`, `pg_constraint`,
-- `pg_get_indexdef`, `pg_get_expr` sobre `pg_policy`) e estão transcritas
-- como o Postgres as devolveu.
--
-- Por que isso importa: a reconstrução de 23/11/2026 provou que o
-- repositório não descrevia o esquema inteiro — 13 objetos eram chamados
-- pelo app e nenhum arquivo os criava. Com estas duas, o chat das 9 equipes
-- e o próprio conceito de equipe deixam de depender de um banco que já foi
-- apagado uma vez.
--
-- ---------------------------------------------------------------------------
-- TRÊS COISAS QUE NÃO SÃO ÓBVIAS E NÃO PODEM SER "ARRUMADAS"
--
-- 1. **`is_team_admin` é coluna GERADA**, não um campo comum. Inserir um
--    valor nela levanta 428C9 — foi o que invalidou um teste de coordenador
--    em 23/11/2026. Ela existe para `is_team_admin(top_id, team)` não
--    precisar repetir a regra do cargo em cada policy.
--
-- 2. **`team_messages.client_id` tem índice único NÃO PARCIAL.** É o que
--    faz `upsert(onConflict: 'client_id')` da fila funcionar: índice
--    parcial quebra o `ON CONFLICT` na forma simples (bug da v1.0.29). Não
--    trocar por parcial "para economizar" — `client_id` nulo é de linha
--    antiga, e um único NULL não conflita com outro em Postgres.
--
-- 3. **As policies de `team_messages` são TRÊS por comando, somadas.**
--    `..._admin`, `..._geral` e `..._membro` são OR entre si, de propósito:
--    `admin_ve_todas_as_equipes.sql` foi escrito aditivo justamente porque
--    esta tabela não estava no repositório e não havia como reescrever suas
--    regras sem apagar alguma que ninguém sabia que existia. Agora que está
--    aqui, continuam separadas — juntar as três numa expressão só é
--    refatoração de controle de acesso a prontuário, e não se faz de
--    graça.
--
-- Idempotente: `if not exists` em tudo e `drop policy if exists` do próprio
-- nome antes de cada `create policy`. Rodado duas vezes seguidas, sem erro.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- top_team_members — quem está em qual equipe, com qual cargo
-- ---------------------------------------------------------------------------
create table if not exists public.top_team_members (
  id         bigint generated always as identity primary key,
  top_id     uuid        not null references public.tops (id) on delete cascade,
  profile_id uuid        not null references public.profiles (id) on delete cascade,
  team       public.team_key  not null,
  team_role  public.team_role not null default 'membro'::public.team_role,
  -- `released`: o vínculo existe mas ainda não vale. `is_team_member` exige
  -- released, e quem cai neste estado fica sem chat e sem anotações sem
  -- saber o que pedir — daí a tela ter texto próprio para ele.
  released   boolean     not null default false,
  blocked    boolean     not null default false,
  created_at timestamptz not null default now(),
  -- GERADA: não inserir. Ver nota 1 do cabeçalho.
  is_team_admin boolean generated always as (
    team_role = any (array['coordenador'::public.team_role,
                           'subcoordenador'::public.team_role])
  ) stored,
  constraint top_team_members_top_id_team_profile_id_key
    unique (top_id, team, profile_id)
);

create index if not exists idx_team_members_profile
  on public.top_team_members (profile_id);
create index if not exists idx_team_members_top_team
  on public.top_team_members (top_id, team);

alter table public.top_team_members enable row level security;

drop policy if exists top_team_members_admin_write on public.top_team_members;
create policy top_team_members_admin_write
  on public.top_team_members for all
  using (public.is_admin()) with check (public.is_admin());

-- SELECT inclui `is_team_admin(top_id, team)`: sem isso o coordenador tinha
-- poder sobre a equipe e NÃO VIA NINGUÉM — `update ... where` e
-- `delete ... where` precisam LER as linhas, e essa leitura passa pela
-- policy de SELECT. Achado em 23/11/2026; ver `12_coordenador_ve_a_equipe_dele.sql`.
-- Não há recursão: `is_team_admin` é `security definer` e não passa pela RLS.
drop policy if exists top_team_members_select on public.top_team_members;
create policy top_team_members_select
  on public.top_team_members for select
  using (
    profile_id = auth.uid()
    or public.is_admin()
    or public.is_team_admin(top_id, team)
  );

-- Coordenação inclui MEMBRO; dar cargo é só do admin (o `team_role = 'membro'
-- or is_admin()`).
drop policy if exists top_team_members_insert on public.top_team_members;
create policy top_team_members_insert
  on public.top_team_members for insert
  with check (
    (public.is_team_admin(top_id, team) or public.is_admin())
    and (team_role = 'membro'::public.team_role or public.is_admin())
  );

drop policy if exists top_team_members_update on public.top_team_members;
create policy top_team_members_update
  on public.top_team_members for update
  using (public.is_team_coordenador(top_id, team) or public.is_admin())
  with check (
    (public.is_team_coordenador(top_id, team) or public.is_admin())
    and (team_role = 'membro'::public.team_role or public.is_admin())
  );

drop policy if exists top_team_members_delete on public.top_team_members;
create policy top_team_members_delete
  on public.top_team_members for delete
  using (public.is_team_coordenador(top_id, team) or public.is_admin());

-- ---------------------------------------------------------------------------
-- team_messages — o chat das 9 equipes e do canal `geral`
-- ---------------------------------------------------------------------------
create table if not exists public.team_messages (
  id          bigint generated always as identity primary key,
  top_id      uuid   not null references public.tops (id) on delete cascade,
  team        public.team_key not null,
  sender_id   uuid   not null references public.profiles (id) on delete cascade,
  -- Desnormalizado de propósito: `profiles` é fechada para quem recebe, o
  -- Realtime não passa por RPC e offline não há rede para buscar o nome.
  sender_name text,
  team_role   public.team_role,
  body        text   not null,
  is_alert    boolean not null default false,
  -- Hora DO APARELHO, nunca `now()` no servidor: offline a mensagem é
  -- escrita horas antes de subir.
  created_at  timestamptz not null default now(),
  edited_at   timestamptz,
  client_id   uuid
);

-- NÃO PARCIAL. Ver nota 2 do cabeçalho.
create unique index if not exists idx_team_messages_client_id
  on public.team_messages (client_id);
create index if not exists idx_team_messages_conversa
  on public.team_messages (top_id, team, created_at desc);
create index if not exists idx_team_messages_sender
  on public.team_messages (sender_id);

alter table public.team_messages enable row level security;

drop policy if exists team_messages_select_admin on public.team_messages;
create policy team_messages_select_admin
  on public.team_messages for select to authenticated
  using (public.is_admin());

drop policy if exists team_messages_select_membro on public.team_messages;
create policy team_messages_select_membro
  on public.team_messages for select
  using (public.is_team_member(top_id, team));

drop policy if exists team_messages_select_geral on public.team_messages;
create policy team_messages_select_geral
  on public.team_messages for select to authenticated
  using (
    team = 'geral'::public.team_key
    and public.is_approved()
    and exists (
      select 1 from public.tops t
      where t.id = team_messages.top_id
        and t.status <> 'draft'::public.top_status
    )
  );

drop policy if exists team_messages_insert_admin on public.team_messages;
create policy team_messages_insert_admin
  on public.team_messages for insert to authenticated
  with check (public.is_admin() and sender_id = auth.uid());

-- Membro comum manda mensagem; ALERTA é da coordenação. Membro marcando
-- alerta esvazia o significado do alerta para todo mundo.
drop policy if exists team_messages_insert_membro on public.team_messages;
create policy team_messages_insert_membro
  on public.team_messages for insert
  with check (
    sender_id = auth.uid()
    and public.is_team_member(top_id, team)
    and (is_alert = false or public.is_team_coordenador(top_id, team))
  );

drop policy if exists team_messages_insert_geral on public.team_messages;
create policy team_messages_insert_geral
  on public.team_messages for insert to authenticated
  with check (
    sender_id = auth.uid()
    and team = 'geral'::public.team_key
    and public.is_approved()
    and exists (
      select 1 from public.tops t
      where t.id = team_messages.top_id
        and t.status <> 'draft'::public.top_status
    )
    and is_alert = false
  );

drop policy if exists team_messages_update_propria on public.team_messages;
create policy team_messages_update_propria
  on public.team_messages for update
  using (sender_id = auth.uid())
  with check (sender_id = auth.uid());

-- ---------------------------------------------------------------------------
-- Realtime: sem isto o `.stream()` do app faz a leitura inicial e NADA MAIS
-- CHEGA — dois celulares lado a lado não se veem. Era um P0 em 23/11/2026.
-- ---------------------------------------------------------------------------
do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'team_messages'
  ) then
    alter publication supabase_realtime add table public.team_messages;
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- Conferência:
--   select count(*) from pg_policy p join pg_class c on c.oid=p.polrelid
--    where c.relname in ('top_team_members','team_messages');        -> 12
--   select tablename from pg_publication_tables
--    where pubname='supabase_realtime' and tablename='team_messages'; -> 1 linha
-- ---------------------------------------------------------------------------
