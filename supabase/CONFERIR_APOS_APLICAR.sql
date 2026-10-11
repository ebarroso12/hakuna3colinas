-- ============================================================================
-- CONFERÊNCIA — rode DEPOIS de aplicar os três arquivos
-- ============================================================================
--
-- Ordem de aplicação:
--   1. team_key_as_nove_equipes.sql    (as 9 equipes no enum)
--   2. admin_ve_todas_as_equipes.sql   (admin lê e escreve nas 9)
--   3. alarme_para_todo_o_top.sql      (emergência para todo o Top)
--
-- Este arquivo NÃO altera nada. Ele só pergunta — e cada resposta vem com
-- o valor esperado ao lado, porque guarda que não é verificada é pior que
-- guarda nenhuma: ela dá a impressão de cobertura.
--
-- Rode cada bloco e LEIA o resultado. Se algum vier diferente do esperado,
-- pare e me diga o número do bloco.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- BLOCO 1 — As 9 equipes existem no enum?
-- ----------------------------------------------------------------------------
-- esperado: valores = 10 · tem_hakunas = true · tem_saude = false
--
-- 10 e não 9 porque `geral` não é equipe, é o canal de todo aprovado.
-- `saude` foi um erro meu de nomenclatura, RENOMEADO para `hakunas`. Se
-- ele aparecer, o rename não pegou e há duas equipes de salvamento.
select
  count(*)                                    as valores,
  bool_or(e.enumlabel = 'hakunas')            as tem_hakunas,
  coalesce(bool_or(e.enumlabel = 'saude'), false) as tem_saude
from pg_enum e
join pg_type t on t.oid = e.enumtypid
join pg_namespace n on n.oid = t.typnamespace
where t.typname = 'team_key' and n.nspname = 'public';


-- ----------------------------------------------------------------------------
-- BLOCO 2 — Na ordem certa, para bater com o app
-- ----------------------------------------------------------------------------
-- esperado, nesta sequência:
--   adm · logistica · voz · intercessao · producao · midia · eventos
--   · seguranca · hakunas · geral
select e.enumlabel, e.enumsortorder
from pg_enum e
join pg_type t on t.oid = e.enumtypid
where t.typname = 'team_key'
order by e.enumsortorder;


-- ----------------------------------------------------------------------------
-- BLOCO 3 — O admin lê e escreve nas 9?
-- ----------------------------------------------------------------------------
-- esperado: as duas linhas novas presentes
--   team_messages_insert_admin  INSERT
--   team_messages_select_admin  SELECT
--
-- E AS ANTIGAS TÊM DE CONTINUAR NA LISTA. Se elas desapareceram, algo as
-- apagou e os membros comuns perderam o chat — me avise antes de usar.
select policyname, cmd
from pg_policies
where schemaname = 'public' and tablename = 'team_messages'
order by cmd, policyname;


-- ----------------------------------------------------------------------------
-- BLOCO 4 — A policy do alarme trocou?
-- ----------------------------------------------------------------------------
-- esperado: top_alerts_insert_todo_o_top · top_alerts_select_todo_o_top
-- e NENHUMA com "qualquer_equipe" ou "hakuna" no nome (foram substituídas)
select policyname, cmd
from pg_policies
where schemaname = 'public' and tablename = 'top_alerts'
order by cmd, policyname;


-- ----------------------------------------------------------------------------
-- BLOCO 5 — A coluna do nome entrou?
-- ----------------------------------------------------------------------------
-- esperado: 1 linha — sender_name · text
select column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name = 'top_alerts'
  and column_name = 'sender_name';


-- ----------------------------------------------------------------------------
-- BLOCO 6 — A PERGUNTA QUE IMPORTA: quantos recebem um alarme?
-- ----------------------------------------------------------------------------
-- É a pergunta que ninguém havia feito, e a razão de tudo isto existir.
--
-- Troque <TOP_ID> pelo id do Top (o 1782). Para achá-lo:
--   select id, name, top_number, status from public.tops order by starts_at desc;
--
-- esperado: `recebiam_antes` perto de 1 · `recebem_agora` = todos os
-- aprovados. Se `recebiam_antes` vier 1, isto acabou de transformar o
-- alarme de inútil em funcional — e o número merece ir para o CHANGELOG.
with alvo as (select '<TOP_ID>'::uuid as top_id)
select
  (
    select count(*) from public.profiles p
    where p.approved = true
      and exists (select 1 from public.tops t, alvo a
                  where t.id = a.top_id and t.status <> 'draft')
  ) as recebem_agora,
  (
    select count(*) from public.profiles p, alvo a
    where p.role = 'admin'
       or p.id in (select profile_id from public.top_hakunas
                   where top_id = a.top_id and released = true)
       or p.id in (select profile_id from public.top_team_members
                   where top_id = a.top_id
                     and released = true and blocked = false)
  ) as recebiam_antes;


-- ----------------------------------------------------------------------------
-- BLOCO 7 — Por que as 9 equipes estão vazias
-- ----------------------------------------------------------------------------
-- esperado hoje: 0 linhas, ou poucas.
--
-- Isto NÃO é defeito do app — é dado operacional que falta. A tela agora
-- diz isso em vez de ficar vazia, mas quem resolve é você em
-- ⋮ → Equipes do Top → Incluir alguém → LIBERAR.
--
-- Atenção ao `released`: incluir sem liberar NÃO dá acesso
-- (`is_team_member` exige `released = true AND blocked = false`).
select
  team,
  count(*)                                  as pessoas,
  count(*) filter (where released)           as liberadas,
  count(*) filter (where not released)       as esperando_liberacao,
  count(*) filter (where blocked)            as bloqueadas
from public.top_team_members
group by team
order by team;


-- ----------------------------------------------------------------------------
-- BLOCO 8 — Quantos veem a posição dos outros
-- ----------------------------------------------------------------------------
-- Não mudou nesta rodada, de propósito (ver CLAUDE.md). Vale olhar porque
-- é o número que decide se "Quem está mais perto" responde a alguém.
--
-- Troque <TOP_ID>. Se vier 1, só você enxerga — e o botão vai aparecer
-- para todos respondendo vazio para quase todos.
select count(*) as veem_posicao_dos_outros
from public.profiles p
where p.role = 'admin'
   or p.id in (select profile_id from public.top_hakunas
               where top_id = '<TOP_ID>'::uuid and released = true)
   or p.id in (select profile_id from public.top_team_members
               where top_id = '<TOP_ID>'::uuid
                 and released = true and blocked = false
                 and (team_role in ('coordenador','subcoordenador')
                      or team in ('seguranca','hakunas')));
