-- ============================================================================
-- 11/10/2026 — A EQUIPE HAKUNAS, ALARME PARA TODOS, MAPA POR CARGO
-- ============================================================================
--
-- 1. A EQUIPE DE SALVAMENTO FALTAVA NO ENUM
--
-- `team_key` tinha 8 equipes + `geral`. O dono do projeto corrigiu: sao 9
-- equipes, e a de salvamento se chama HAKUNAS. Ela nao existia no enum —
-- por isso nao tinha chat de equipe nem bloco de anotacoes como as outras,
-- so o chat clinico em `top_hakuna_messages`, numa tabela separada.
--
-- Eu havia adicionado 'saude' por conta propria antes de ele dizer o nome.
-- Corrigido com RENAME VALUE em vez de "adiciona o certo e deixa o
-- errado": valor orfao num enum reaparece em todo dropdown e em toda
-- migracao futura.
--
--   alter type public.team_key add value 'saude';          -- erro meu
--   alter type public.team_key rename value 'saude' to 'hakunas';
--
-- `hakuna` continua sendo tambem um PAPEL (`user_role`). Sao dimensoes
-- diferentes: a equipe e onde a pessoa trabalha, o papel e o que ela pode
-- fazer no app.
--
-- ============================================================================
-- 2. ALARME: TODOS DISPARAM E RECEBEM
--
-- Decisao do dono. Antes `top_alerts` exigia `top_hakunas.released` nas
-- duas pontas, e a seguranca — cuja funcao e exatamente isso — ficava de
-- fora. Quem ve um acidente e quem esta por perto, nao quem tem o papel
-- certo.
--
-- A fronteira e `pertence_ao_top()`: membro liberado de QUALQUER equipe,
-- Hakuna liberado, ou admin. Nao e "qualquer pessoa logada".
-- ============================================================================
create or replace function public.pertence_ao_top(p_top_id uuid)
returns boolean language sql stable security definer
set search_path = public as $$
  select
    is_admin()
    or exists (select 1 from public.top_hakunas h
               where h.top_id = p_top_id and h.profile_id = auth.uid()
                 and h.released = true)
    or exists (select 1 from public.top_team_members m
               where m.top_id = p_top_id and m.profile_id = auth.uid()
                 and m.released = true and m.blocked = false);
$$;

create policy top_alerts_insert_qualquer_equipe on public.top_alerts
  for insert to authenticated
  with check (sender_id = auth.uid() and pertence_ao_top(top_id));

create policy top_alerts_select_qualquer_equipe on public.top_alerts
  for select to authenticated using (pertence_ao_top(top_id));

-- ============================================================================
-- 3. MAPA: POR CARGO, E O ADMIN SOBREPOE PESSOA POR PESSOA
--
-- Mais restrito que o alarme DE PROPOSITO: alarme e emergencia, posicao e
-- vigilancia continua. 200 pessoas vendo a localizacao de todas as outras
-- nao e necessario para midia, producao ou intercessao trabalharem.
--
-- Regra automatica: admin · Hakuna liberado · coordenacao/subcoordenacao
-- de qualquer equipe · membros de `seguranca` e `hakunas`.
--
-- `top_permissoes` sobrepoe, com TRES estados:
--   sem linha        -> vale a regra automatica
--   ver_mapa = true  -> LIBERADO mesmo que a regra nao liberasse
--   ver_mapa = false -> BLOQUEADO mesmo que a regra liberasse
--
-- O terceiro estado e o que faz a tabela ser "editar" e nao so
-- "conceder": sem ele, tirar o mapa de um coordenador exigiria rebaixa-lo
-- de cargo.
-- ============================================================================
create table if not exists public.top_permissoes (
  top_id       uuid not null references public.tops(id) on delete cascade,
  profile_id   uuid not null references public.profiles(id) on delete cascade,
  ver_mapa     boolean not null,
  definido_por uuid references public.profiles(id),
  definido_em  timestamptz not null default now(),
  primary key (top_id, profile_id)
);
alter table public.top_permissoes enable row level security;

create policy top_permissoes_admin on public.top_permissoes
  for all to authenticated using (is_admin()) with check (is_admin());

-- A propria pessoa le a SUA linha: saber se enxerga o mapa, e nao
-- descobrir no escuro quando a tela vem vazia.
create policy top_permissoes_select_propria on public.top_permissoes
  for select to authenticated
  using (profile_id = auth.uid() or is_admin());

create or replace function public.pode_ver_mapa(p_top_id uuid)
returns boolean language sql stable security definer
set search_path = public as $$
  select case
    -- Admin sempre: sem isto ele poderia se bloquear sem volta pelo app.
    when is_admin() then true
    when exists (select 1 from public.top_permissoes p
                 where p.top_id = p_top_id and p.profile_id = auth.uid())
      then (select p.ver_mapa from public.top_permissoes p
            where p.top_id = p_top_id and p.profile_id = auth.uid())
    else
      exists (select 1 from public.top_hakunas h
              where h.top_id = p_top_id and h.profile_id = auth.uid()
                and h.released = true)
      or exists (select 1 from public.top_team_members m
                 where m.top_id = p_top_id and m.profile_id = auth.uid()
                   and m.released = true and m.blocked = false
                   and (m.team_role in ('coordenador','subcoordenador')
                        or m.team in ('seguranca','hakunas')))
  end;
$$;

create policy hakuna_positions_select_coordenacao on public.hakuna_positions
  for select to authenticated
  using (
    -- A propria trilha sempre: ela alimenta distancia e calorias em
    -- StatsService.
    profile_id = auth.uid() or pode_ver_mapa(top_id)
  );

-- ============================================================================
-- 4. BLOCO DE ANOTACOES: UM POR MEMBRO, EDITAVEL
--
-- Era append-only na primeira versao, por medo de perda de texto. O dono
-- apontou que o medo nao se aplica: cada membro tem login proprio e o
-- bloco e dele, entao nao ha duas pessoas editando o mesmo.
--
-- A chave e `bloco_id`, TEXTO, calculada no aparelho:
--   <top_id>|<team>|<autor_id>|<participante_id ou ->
--
-- Nao e indice composto porque `participante_id` e nulo no bloco do turno,
-- e em Postgres NULL NAO CONFLITA COM NULL num indice unico — dois blocos
-- de turno da mesma pessoa nao colidiriam e virariam duplicata. Resolver
-- com indice PARCIAL quebraria o upsert (o Postgres nao infere parcial na
-- forma simples do ON CONFLICT: foi o bug da v1.0.29). O texto com '-' no
-- lugar do nulo nao tem esse problema, e o app calcula sem consultar nada.
--
-- No envio: `upsert(onConflict: 'bloco_id')` SEM `ignoreDuplicates` — o
-- bloco e editavel, e a segunda chegada tem de ATUALIZAR.
-- ============================================================================
alter table public.anotacoes
  add column if not exists bloco_id text,
  add column if not exists atualizado_em timestamptz not null default now();

update public.anotacoes
   set bloco_id = top_id::text || '|' || team::text || '|' || autor_id::text
                  || '|' || coalesce(participante_id::text, '-')
 where bloco_id is null;

alter table public.anotacoes alter column bloco_id set not null;
create unique index if not exists anotacoes_bloco_id_key
  on public.anotacoes (bloco_id);

-- ============================================================================
-- 5. TOP NOVO: FRANCA, 26 A 29/11/2026
--
-- Nasce em `draft` de proposito — e a trava que impede alguem se cadastrar
-- antes de o admin terminar de montar. `diretor_responsavel` e
-- `top_number` ficam NULOS: quem define o responsavel e o numero de um
-- evento e o dono dele, nao eu. Ja inventei um nome de diretor nesta base
-- uma vez, e apaguei.
-- ============================================================================
--   name:      'Comemoração de 1 ano'
--   cidade:    'Franca'
--   starts_at: 2026-11-26  ends_at: 2026-11-29
--   id:        80a04d46-1688-4f70-8dd8-2e14e6e2cbb9

-- ============================================================================
-- PROVADO COM SESSAO SIMULADA (transacao revertida)
--
-- Quatro usuarios liberados: midia/membro, seguranca/membro,
-- logistica/membro e midia/COORDENADOR.
--
--   1. MIDIA (membro) dispara alarme           -> conseguiu
--   2. MIDIA recebe alarme                     -> 1
--   3. MIDIA (membro) ve posicao de outro      -> 0
--   4. SEGURANCA (membro) ve posicao           -> 1
--   5. COORDENADOR de midia ve posicao         -> 1
--   6. LOGISTICA (membro) ve posicao           -> 0
--   7. LOGISTICA apos admin LIBERAR            -> 1
--   8. COORDENADOR apos admin BLOQUEAR         -> 0
--   9. MIDIA ve a PROPRIA trilha               -> 1
--
-- E a RLS das anotacoes, com dois usuarios em equipes diferentes:
--   anotar no NOME de outro   -> bloqueado pela RLS
--   anotar em EQUIPE alheia   -> bloqueado pela RLS
--   midia LE a da seguranca   -> 0
--
-- A primeira tentativa desse teste FALHOU porque `is_team_member` exige
-- `released = true AND blocked = false`: ESTAR NA EQUIPE NAO BASTA, o
-- admin tem de liberar cada membro. Sem isso nem chat nem anotacao
-- funcionam para a pessoa.
-- ============================================================================
