-- ============================================================================
-- Aplicado em producao (projeto jitfbambhmfnqiatwoud) em 09/10/2026.
--
-- Este arquivo documenta o que ja foi executado, para que o schema possa
-- ser reconstruido do zero. Rodar de novo num banco que ja tem isso vai
-- dar erro de objeto duplicado - e esperado.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- PARTE 1 - Coordenador e subcoordenador nas equipes
--
-- Antes: top_team_members.is_team_admin era um booleano, um nivel so. Nao
-- dava pra distinguir quem coordena a equipe de quem apenas ajuda a
-- coordenar.
--
-- Agora:
--   coordenador     -> adiciona E remove membros, manda alerta
--   subcoordenador  -> adiciona membros, manda alerta, NAO remove
--   membro          -> participa do chat da equipe
--
-- Promover alguem a coordenador/subcoordenador e exclusivo do admin
-- (master ou geral), nunca do proprio coordenador.
-- ----------------------------------------------------------------------------

create type team_role as enum ('coordenador','subcoordenador','membro');

alter table public.top_team_members
  add column team_role team_role not null default 'membro';

-- quem era is_team_admin vira coordenador (o nivel mais alto)
update public.top_team_members set team_role = 'coordenador' where is_team_admin = true;

-- is_team_admin deixa de ser editavel e passa a ser derivado de team_role,
-- pra nao existir estado inconsistente entre os dois.
alter table public.top_team_members drop column is_team_admin;
alter table public.top_team_members
  add column is_team_admin boolean
  generated always as (team_role in ('coordenador','subcoordenador')) stored;


-- "admin da equipe" = coordenador OU subcoordenador. Mantem o nome porque
-- e o que as policies de team_messages ja usam.
create or replace function public.is_team_admin(p_top_id uuid, p_team team_key)
returns boolean language sql stable security definer set search_path to 'public' as $$
  select exists (
    select 1 from public.top_team_members m
    where m.top_id = p_top_id and m.team = p_team
      and m.profile_id = auth.uid()
      and m.team_role in ('coordenador','subcoordenador')
      and m.released = true and m.blocked = false
  );
$$;

-- So o coordenador remove/edita membros.
create or replace function public.is_team_coordenador(p_top_id uuid, p_team team_key)
returns boolean language sql stable security definer set search_path to 'public' as $$
  select exists (
    select 1 from public.top_team_members m
    where m.top_id = p_top_id and m.team = p_team
      and m.profile_id = auth.uid()
      and m.team_role = 'coordenador'
      and m.released = true and m.blocked = false
  );
$$;

-- Correcao de seguranca: antes is_team_member ignorava `blocked`, entao um
-- membro bloqueado continuava lendo o chat da equipe.
create or replace function public.is_team_member(p_top_id uuid, p_team team_key)
returns boolean language sql stable security definer set search_path to 'public' as $$
  select exists (
    select 1 from public.top_team_members m
    where m.top_id = p_top_id and m.team = p_team
      and m.profile_id = auth.uid()
      and m.released = true and m.blocked = false
  );
$$;


-- A policy unica de ALL vira tres, pra separar quem adiciona de quem remove.
drop policy if exists top_team_members_write on public.top_team_members;

create policy top_team_members_insert on public.top_team_members
for insert with check (
  (is_team_admin(top_id, team) or is_admin())
  and (team_role = 'membro' or is_admin())
);

create policy top_team_members_update on public.top_team_members
for update using (is_team_coordenador(top_id, team) or is_admin())
with check (
  (is_team_coordenador(top_id, team) or is_admin())
  and (team_role = 'membro' or is_admin())
);

create policy top_team_members_delete on public.top_team_members
for delete using (is_team_coordenador(top_id, team) or is_admin());


-- ----------------------------------------------------------------------------
-- PARTE 2 - Regras de triagem v2
--
-- A configuracao anterior (ids 1-6) tinha uma regra "41+, 0..999
-- comorbidades -> vermelho" com priority 1. Por ser a de maior prioridade,
-- ela atropelava todas as outras. Duas consequencias:
--
--   1. acima de 40 o numero de comorbidades deixava de influenciar a cor;
--      alguem de 41 sem nenhuma comorbidade e alguem de 65 com tres eram
--      indistinguiveis, e a triagem perdia a capacidade de priorizar
--      justamente na faixa com mais participantes;
--   2. alguem saudavel pulava de verde aos 40 para vermelho aos 41 - dois
--      niveis em um ano, sem passar pelo amarelo.
--
-- As regras antigas ficaram com active=false em vez de apagadas: reverter
-- e so inverter a flag nos dois conjuntos.
--
-- Matriz resultante:
--
--    idade |  0 comorb   1 comorb   2+ comorb
--    ------+---------------------------------
--     0-25 |     azul      verde     vermelho
--    26-40 |    verde    amarelo     vermelho
--      41+ |  amarelo   vermelho     vermelho
--
-- Faixas explicitas, sem sobreposicao e sem buraco. Verificado
-- exaustivamente em test/services/triage_service_test.dart (0-110 anos x
-- 0-8 comorbidades), incluindo a garantia de que a gravidade nunca diminui
-- quando a idade ou o numero de comorbidades aumenta.
--
-- IMPORTANTE: o fixture `_producao` daquele teste e uma copia destas
-- regras. Mudou aqui, muda la.
-- ----------------------------------------------------------------------------

update public.triage_rules set active = false where active = true;

insert into public.triage_rules
  (color, label, min_age, max_age, min_comorbidities, max_comorbidities, priority, active)
values
  ('blue',   'Azul - ate 25 anos, sem comorbidade',          0,  25, 0,   0, 1, true),
  ('green',  'Verde - ate 25 anos, 1 comorbidade',           0,  25, 1,   1, 2, true),
  ('red',    'Vermelho - ate 25 anos, 2+ comorbidades',      0,  25, 2, 999, 3, true),
  ('green',  'Verde - 26 a 40 anos, sem comorbidade',       26,  40, 0,   0, 4, true),
  ('yellow', 'Amarelo - 26 a 40 anos, 1 comorbidade',       26,  40, 1,   1, 5, true),
  ('red',    'Vermelho - 26 a 40 anos, 2+ comorbidades',    26,  40, 2, 999, 6, true),
  ('yellow', 'Amarelo - acima de 40 anos, sem comorbidade', 41, null, 0,  0, 7, true),
  ('red',    'Vermelho - acima de 40 anos, 1+ comorbidade', 41, null, 1, 999, 8, true);
