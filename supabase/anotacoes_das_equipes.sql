-- ============================================================================
-- ANOTACOES DAS EQUIPES — 11/10/2026
--
-- O app e dos LEGENDARIOS, nao so dos Hakunas. Esse mal-entendido durou a
-- sessao inteira e vinha do proprio CLAUDE.md, que abria com "app de
-- coordenacao da equipe medica (Hakunas)". Corrigido.
--
-- A diferenca real: o Hakuna tem PRONTUARIO (dado clinico, com cerca
-- propria em `atendimentos`), e as outras 8 equipes precisam do
-- equivalente nao-medico — um lugar para registrar o que aconteceu no
-- turno.
-- ============================================================================
--
-- AS TRES DIMENSOES DE QUEM E QUEM, que eu confundia:
--
--   user_role  = admin | hakuna | senderista          -> papel no sistema
--   team_key   = 9 valores                            -> equipe no Top
--   team_role  = coordenador | subcoordenador | membro -> posicao na equipe
--
-- `hakuna` NAO e equipe, e papel. As 9 chaves de `team_key`: adm,
-- logistica, voz, intercessao, producao, midia, eventos, seguranca, geral.
-- `geral` nao e equipe: e o canal que todo participante aprovado enxerga.
--
-- ============================================================================
-- DECISOES DE MODELAGEM E AS RAZOES
--
-- 1. APPEND-ONLY, lista cronologica, nao um bloco unico editavel.
--
--    O pedido foi "bloco de anotacao ... bloco de texto que salva". Um
--    bloco unico editavel offline PERDE TEXTO: duas pessoas da mesma
--    equipe editam sem sinal e a ultima a sincronizar sobrescreve a outra,
--    sem aviso e sem como recuperar. Com registros separados nada se
--    perde, e de brinde fica rastreavel quem anotou o que e quando — numa
--    ocorrencia de seguranca isso e metade do valor da anotacao.
--
--    Para corrigir, escreve-se outra. Mesmo desenho de `atendimentos`.
--    Se o dono do projeto preferir o bloco unico, e trocavel — mas o
--    risco de perda de texto offline passa a existir.
--
-- 2. `participante_id` OPCIONAL, cobrindo os dois usos com um modelo so:
--    com participante = anotacao SOBRE alguem ("saiu da trilha no km 8");
--    sem = anotacao do turno ("portao 2 sem cobertura das 14h as 15h").
--
--    SET NULL e nao CASCADE: apagar o cadastro de alguem nao deve apagar o
--    registro de que algo aconteceu.
--
-- 3. VISIVEL PARA A EQUIPE, nao para o Top inteiro. Anotacao da seguranca
--    nao e do interesse da midia, e o contrario tambem. Coordenador e
--    subcoordenador veem a da equipe deles — por isso a leitura e por
--    `is_team_member`/`is_team_admin`, nao por autoria.
--
-- 4. NAO E LUGAR DE DADO CLINICO, e a tela avisa isso FIXO em cima do
--    campo, nao num dialogo que se dispensa. Sintoma escrito aqui fica
--    fora da triagem e invisivel para quem vai atender — e o erro mais
--    provavel desta tela e o mais caro. O caminho do dado clinico e
--    `atendimentos`.
-- ============================================================================

create table if not exists public.anotacoes (
  id              uuid primary key default gen_random_uuid(),
  top_id          uuid not null references public.tops(id) on delete cascade,
  team            public.team_key not null,
  autor_id        uuid not null references public.profiles(id) on delete restrict,
  participante_id uuid references public.top_participants(id) on delete set null,
  texto           text not null check (length(trim(texto)) > 0),
  criada_em       timestamptz not null default now(),
  client_id       uuid
);

-- UNICO e NAO PARCIAL. `upsert(onConflict: 'client_id')` emite a forma
-- simples do ON CONFLICT, e o Postgres so infere indice parcial quando o
-- comando repete o predicado — foi o bug da v1.0.29, que mandou a fila
-- inteira para quarentena.
create unique index if not exists anotacoes_client_id_key
  on public.anotacoes (client_id);
create index if not exists idx_anotacoes_top_team
  on public.anotacoes (top_id, team, criada_em desc);
create index if not exists idx_anotacoes_participante
  on public.anotacoes (participante_id, criada_em desc)
  where participante_id is not null;

alter table public.anotacoes enable row level security;

create policy anotacoes_select_equipe on public.anotacoes
  for select to authenticated
  using (
    is_admin()
    or is_team_member(top_id, team)
    or is_team_admin(top_id, team)
    or (
      team = 'geral'::public.team_key
      and is_approved()
      and exists (
        select 1 from public.tops t
        where t.id = anotacoes.top_id and t.status <> 'draft'::public.top_status
      )
    )
  );

-- `autor_id = auth.uid()` impede anotar no NOME de um colega — o mesmo
-- cuidado da policy de `closed_by` em atendimentos.
create policy anotacoes_insert_equipe on public.anotacoes
  for insert to authenticated
  with check (
    autor_id = auth.uid()
    and (
      is_admin()
      or is_team_member(top_id, team)
      or is_team_admin(top_id, team)
      or (
        team = 'geral'::public.team_key
        and is_approved()
        and exists (
          select 1 from public.tops t
          where t.id = anotacoes.top_id
            and t.status <> 'draft'::public.top_status
        )
      )
    )
  );

-- SEM UPDATE e SEM DELETE, de proposito: append-only.

-- ============================================================================
-- PROVADO COM SESSAO SIMULADA (transacao revertida)
--
-- Dois usuarios de teste, um em `seguranca` e um em `midia`, ambos
-- LIBERADOS na equipe:
--
--   1. seguranca liberada anotou        -> OK
--   2. reenviado 2x gravou N linhas     -> 1
--   3. anotar no NOME de outro          -> bloqueado pela RLS
--   4. anotar em EQUIPE alheia          -> bloqueado pela RLS
--   5. seguranca LE a propria           -> 1
--   6. midia LE a da seguranca          -> 0
--
-- A PRIMEIRA tentativa deste teste FALHOU, e o motivo vale registrar:
-- `is_team_member` exige `released = true AND blocked = false`, e eu havia
-- inserido o vinculo sem liberar. **Estar na equipe nao basta — o admin
-- tem de liberar cada membro**, igual aos Hakunas. Sem isso, nem chat nem
-- anotacao funcionam para a pessoa.
-- ============================================================================
