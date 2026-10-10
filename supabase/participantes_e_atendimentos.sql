-- ============================================================================
-- Aplicado em producao (projeto jitfbambhmfnqiatwoud) em 09/10/2026.
--
-- Documenta o que ja foi executado. Rodar de novo num banco que ja tem isso
-- da erro de objeto duplicado - os ADD COLUMN usam IF NOT EXISTS, mas o
-- CREATE TABLE/TYPE nao.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- PARTE 1 - Ficha completa do participante
--
-- top_participants ja existia com nome, telefone, nascimento, contato de
-- emergencia e tag_uid, mas sem nada do que a ficha clinica mostra.
-- Estas colunas cobrem a FICHA DO PARTICIPANTE inteira.
--
-- Decisao importante: `comorbidades` guarda SO condicao clinica, porque e
-- essa lista que TriageService conta pra decidir a cor da triagem. No app
-- oficial, "PLANO DE SAUDE: UNIMED" e "ALERGICO: ..." apareciam dentro de
-- COMORBIDADES; herdar isso faria alguem sem nenhuma doenca ser contado
-- como tendo uma e subir de verde pra amarelo. Por isso plano, alergia,
-- medicacao e restricao ficam em colunas proprias.
-- ----------------------------------------------------------------------------

alter table public.top_participants
  add column if not exists familia                  text,
  add column if not exists cidade                   text,
  add column if not exists estado                   text,
  add column if not exists height_cm                numeric,
  add column if not exists weight_kg                numeric,
  add column if not exists blood_type               text,
  add column if not exists biotipo                  text,
  add column if not exists cirurgias                text,
  add column if not exists observacao_hakuna        text,
  add column if not exists atividade_fisica_semanal text,
  add column if not exists comorbidades             text[] not null default '{}',
  add column if not exists alergias                 text,
  add column if not exists plano_saude              text,
  add column if not exists medicamentos_continuos   text,
  add column if not exists restricoes_fisicas       text;

-- A lista de participantes busca por nome/sobrenome/pedaco do nome e por
-- familia. Sem indice, 215+ registros por Top ficam lentos.
create index if not exists idx_participants_familia
  on public.top_participants (top_id, familia);
create index if not exists idx_participants_nome
  on public.top_participants (top_id, lower(full_name));


-- ----------------------------------------------------------------------------
-- PARTE 2 - Registro de atendimento
--
-- atendimentos ja tinha participante, GPS, status e os 6 timestamps do
-- fluxo. Faltavam o numero visivel do registro, os sinais vitais aferidos
-- na hora e o client_id que permite criar o atendimento offline.
--
-- O registro e append-only: toda abertura gera um numero novo e nada e
-- editado. Dois Hakunas atendendo a mesma pessoa viram dois registros, e
-- por isso nao existe conflito de sincronizacao - decisao do usuario,
-- tomada em 09/10/2026.
-- ----------------------------------------------------------------------------

alter table public.atendimentos
  add column if not exists numero_registro integer,
  add column if not exists client_id       text,
  add column if not exists systolic_bp     integer,
  add column if not exists diastolic_bp    integer,
  add column if not exists glicemia_mg_dl  integer,
  add column if not exists spo2            integer,
  add column if not exists heart_rate      integer,
  add column if not exists temperature_c   numeric,
  add column if not exists feridas         text;

-- client_id unico: o mesmo atendimento reenviado apos queda de rede nao
-- pode virar dois registros no historico clinico.
create unique index if not exists idx_atendimentos_client_id
  on public.atendimentos (client_id) where client_id is not null;
create index if not exists idx_atendimentos_participante
  on public.atendimentos (top_id, participant_id, opened_at desc);


-- ----------------------------------------------------------------------------
-- PARTE 3 - Fotos do atendimento
--
-- Foto do paciente, da ferida ou do estado no momento. Tabela propria e
-- nao um array em atendimentos porque cada foto precisa do proprio
-- controle de quando saiu da pasta do celular e chegou no Storage: no mato
-- a foto e tirada offline e so sobe horas depois.
-- ----------------------------------------------------------------------------

create table if not exists public.atendimento_fotos (
  id             uuid primary key default gen_random_uuid(),
  atendimento_id uuid not null references public.atendimentos(id) on delete cascade,
  top_id         uuid not null references public.tops(id) on delete cascade,
  client_id      text unique,
  local_path     text,   -- pasta do proprio celular, enquanto nao subiu
  storage_path   text,   -- Supabase Storage, depois que subiu
  taken_at       timestamptz not null default now(),
  uploaded_at    timestamptz,
  taken_by       uuid references public.profiles(id)
);

alter table public.atendimento_fotos enable row level security;

-- Foto de atendimento e dado clinico: mesma regra de quem ve o atendimento.
-- Quem tirou sempre ve a propria; Hakuna liberado no Top ve as do Top;
-- admin ve tudo.
create policy atendimento_fotos_select on public.atendimento_fotos
for select using (
  taken_by = auth.uid()
  or is_admin()
  or exists (
    select 1 from public.top_hakunas h
    where h.top_id = atendimento_fotos.top_id
      and h.profile_id = auth.uid()
      and h.released = true
  )
);

create policy atendimento_fotos_insert on public.atendimento_fotos
for insert with check (
  taken_by = auth.uid()
  and (
    is_admin()
    or exists (
      select 1 from public.top_hakunas h
      where h.top_id = atendimento_fotos.top_id
        and h.profile_id = auth.uid()
        and h.released = true
    )
  )
);

-- Sem UPDATE nem DELETE de proposito: foto de atendimento e registro
-- clinico, nao se altera nem se apaga. Remocao, se for mesmo necessaria,
-- passa pelo admin direto no banco e fica no audit_log.
