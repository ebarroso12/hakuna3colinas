-- ===========================================================================
-- SEIS PARES DE ÍNDICES IDÊNTICOS, UM DE CADA PAR SOBRANDO
--
-- Achados em 24/11/2026 pelo advisor de performance do Supabase (`duplicate
-- index`), confirmados um por um com `pg_get_indexdef` antes de apagar.
--
-- A causa é a reconstrução do banco: arquivos diferentes de `supabase/`
-- criam o MESMO índice com nomes diferentes — um em português e outro em
-- inglês. Rodando todos, o Postgres obedece aos dois e fica com duas
-- estruturas iguais na mesma tabela. Índice duplicado não dá resposta
-- errada; custa escrita (todo insert/update mantém os dois) e confunde
-- quem lê o esquema depois.
--
-- ---------------------------------------------------------------------------
-- O QUE FOI CONFERIDO ANTES DE APAGAR — NENHUM DESTES PASSOS É OPCIONAL
--
-- 1. **Os pares são realmente idênticos**, inclusive o `WHERE` dos
--    parciais. Comparado por `pg_get_indexdef`, não pelo nome.
-- 2. **Nenhum é apoiado por constraint** (`pg_constraint.conindid` nulo nos
--    doze). Apagar índice que sustenta uma constraint falharia, ou pior,
--    derrubaria a constraint junto.
-- 3. **Nenhum é alvo de `onConflict`.** O app usa `id`, `client_id`,
--    `bloco_id`, `fcm_token`, `top_id,ordem` e `top_id,profile_id`; a Edge
--    Function usa `top_id,profile_id` e `version`. Nenhum dos pares abaixo
--    cobre essas colunas — e o `CLAUDE.md` registra que índice parcial
--    quebra `upsert(onConflict:)` (bug da v1.0.29), então era a primeira
--    coisa a conferir.
-- 4. **De cada par único, UM FICA.** `atendimentos.client_id` e
--    `(top_id, linked_profile_id)` continuam com unicidade garantida.
-- 5. **Nenhum nome aparece em `lib/` nem nas Edge Functions.** Índice
--    citado por nome em código viraria erro em tempo de execução.
--
-- ---------------------------------------------------------------------------
-- POR QUE ISTO NÃO BASTA, E OS ARQUIVOS HISTÓRICOS FORAM EDITADOS JUNTO
--
-- Todo nome dos doze é criado por algum arquivo de `supabase/`. Apagar só
-- aqui faria o duplicado VOLTAR na próxima reconstrução — o mesmo mecanismo
-- que ressuscitou a regra pega-tudo da triagem em 23/11/2026, quando
-- `schema.sql` foi reexecutado.
--
-- Então o conserto é nos dois lados: este arquivo apaga o que existe, e a
-- criação do nome descartado saiu do arquivo que a fazia. O nome que fica é
-- sempre o de `00_TABELAS_QUE_FALTAVAM.sql`, que é a base da reconstrução —
-- exceto em `atendimentos`, onde fica `idx_atendimentos_client_id`, criado
-- por três arquivos contra um.
-- ===========================================================================

-- atendimentos.client_id — os dois são UNIQUE; sobra o que 3 arquivos criam.
-- A unicidade continua, e ela é o que faz o reenvio da fila ser idempotente.
drop index if exists public.atendimentos_client_id_key;

-- audit_log (top_id, coalesce(occurred_at, created_at) desc)
-- Os DOIS eram criados por `00_TABELAS_QUE_FALTAVAM.sql`.
drop index if exists public.idx_audit_log_top_quando;

-- top_participants (linked_profile_id) where not null
drop index if exists public.idx_participants_linked_profile;

-- top_participants (registered_by)
drop index if exists public.idx_participants_registrado_por;

-- top_participants (top_id, linked_profile_id) where not null — UNIQUE.
-- Sobra `idx_participants_perfil_unico`. É esta unicidade que impede a
-- mesma conta de ficar ligada a duas fichas do mesmo Top.
drop index if exists public.idx_participants_profile_unico;

-- top_team_members (profile_id)
drop index if exists public.idx_team_members_perfil;

-- ---------------------------------------------------------------------------
-- Conferência — tem de voltar VAZIO (nenhum par idêntico sobrando):
--
--   select t.relname, array_agg(i.relname order by i.relname) as iguais
--     from pg_index ix
--     join pg_class i on i.oid = ix.indexrelid
--     join pg_class t on t.oid = ix.indrelid
--     join pg_namespace n on n.oid = t.relnamespace
--    where n.nspname = 'public'
--    group by t.relname, pg_get_expr(ix.indpred, ix.indrelid),
--             ix.indkey::text, ix.indisunique
--   having count(*) > 1;
--
-- E a unicidade que importa tem de continuar de pé:
--
--   select indexrelid::regclass from pg_index
--    where indrelid = 'public.atendimentos'::regclass and indisunique;
-- ---------------------------------------------------------------------------
