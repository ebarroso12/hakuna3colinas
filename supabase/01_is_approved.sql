-- ===========================================================================
-- `is_approved()` — A FUNÇÃO QUE NUNCA ESTEVE NO REPOSITÓRIO
--
-- Achada em 23/11/2026, ao reconstruir o banco do zero depois que o projeto
-- Supabase foi apagado. Três policies a chamam e nenhum arquivo a cria:
--
--   alarme_para_todo_o_top.sql:53   dentro de `pode_alarmar_no_top()`
--   anotacoes_das_equipes.sql:92    leitura do bloco de anotações
--   anotacoes_das_equipes.sql:112   escrita do bloco de anotações
--
-- O estrago de ela faltar não é um erro na tela — é pior:
--
--   1. `pode_alarmar_no_top()` NÃO É CRIADA (a função não compila sem ela),
--      e sem essa função as policies de `top_alerts` que dependem dela não
--      entram. **A emergência não dispara e não chega em ninguém.**
--   2. `anotacoes` fica com RLS LIGADO E ZERO POLICIES. Isso não é "aberto",
--      é NEGADO PARA TODOS — o bloco de anotações das 9 equipes some sem
--      mensagem de erro, igual ao que aconteceu com o bucket `emblemas`.
--
-- É a mesma família de defeito que já mordeu este projeto três vezes:
-- objeto que só existia em produção, nunca versionado, e que ninguém sente
-- falta até reconstruir.
--
-- ---------------------------------------------------------------------------
-- POR QUE O CORPO É ESTE
--
-- `my_approved()` existe no repositório (`profiles_sem_escalada_de_privilegio.sql:93`)
-- e responde exatamente a mesma pergunta: "quem está chamando está aprovado?".
-- As duas convivem por história — nomes diferentes para a mesma régua. O
-- corpo aqui é cópia fiel do dela, não invenção.
--
-- `security definer` é obrigatório: a função lê `profiles`, e a RLS de
-- `profiles` só deixa cada um ver a própria linha. Sem `definer`, chamá-la
-- de dentro de outra policy daria falso em caso legítimo.
--
-- `stable` e não `volatile`: dentro de uma mesma consulta o resultado não
-- muda, e isso deixa o planejador reaproveitar.
-- ===========================================================================

create or replace function public.is_approved()
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$ select coalesce(approved, false) from public.profiles where id = auth.uid(); $$;

-- Responde sobre QUEM CHAMA, então pode ser executada por qualquer sessão
-- autenticada — não é oráculo sobre terceiros. (A `is_in_top_community`,
-- que recebia um perfil arbitrário, era oráculo e por isso foi trancada em
-- `revisao_10_10_correcoes.sql`.)
grant execute on function public.is_approved() to authenticated;

-- Conferência:
--   select public.is_approved();            -> false sem sessão, e é o certo
--   select count(*) from pg_proc p
--     join pg_namespace n on n.oid = p.pronamespace
--    where n.nspname = 'public' and p.proname = 'is_approved';   -> 1
