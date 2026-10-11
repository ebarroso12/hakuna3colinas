-- ============================================================================
-- 11/10/2026 — O ADMIN VÊ E ACESSA AS 9 EQUIPES
-- ============================================================================
--
-- Decisão do dono do projeto, dita nestas palavras: "como administrador
-- devo ver e ter acesso a todas as equipes".
--
-- A UI já foi corrigida (`lib/screens/team_chats_screen.dart` mostra as 9
-- e abre todas para quem é admin). Este arquivo garante o lado do banco,
-- que é onde a fronteira de verdade mora — se a RLS recusar, a tela
-- mostra chat vazio e a mensagem enviada cai na QUARENTENA da fila, o que
-- é pior que o botão não existir.
--
-- POR QUE ESTE ARQUIVO É ADITIVO, E NÃO UM `DROP POLICY` + `CREATE`
--
-- `team_messages` não existe em nenhum arquivo deste repositório: a tabela
-- e as policies dela foram criadas direto em produção. Eu não tenho acesso
-- de leitura ao banco para ver os nomes e os corpos das policies atuais,
-- então não posso reescrevê-las sem apagar regra que eu não sei que existe.
--
-- A saída é somar, não substituir: **policies do mesmo comando são OR
-- entre si** no Postgres. Uma policy nova de SELECT que só diz
-- `is_admin()` amplia o acesso do admin e não tira nada de ninguém. É a
-- operação segura possível sem enxergar o banco.
--
-- As colunas usadas aqui estão CONFERIDAS contra o código que lê e grava
-- a tabela, não supostas:
--   `top_id`, `team`, `sender_id`, `body`, `created_at`, `is_alert`,
--   `client_id`, `edited_at`, `id`
--   -> `TeamMessage.fromMap` em `lib/models/team_message.dart`
--   -> `SupabaseService.enviarMensagemEquipe` / `watchTeamMessages`
--
-- `is_admin()` já é usada por todo o resto do projeto com este mesmo
-- sentido (ver `anotacoes_das_equipes.sql`, `team_roles_and_triage_v2.sql`,
-- `equipes_alarme_mapa_e_blocos.sql`), e é `security definer`, então não
-- recai em recursão de RLS sobre `profiles`.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. LER o chat de qualquer equipe
-- ----------------------------------------------------------------------------
drop policy if exists team_messages_select_admin on public.team_messages;

create policy team_messages_select_admin on public.team_messages
  for select to authenticated
  using (is_admin());


-- ----------------------------------------------------------------------------
-- 2. ESCREVER no chat de qualquer equipe, inclusive como alerta
-- ----------------------------------------------------------------------------
--
-- `sender_id = auth.uid()` fica mesmo sendo admin, e não é zelo excessivo:
-- é o que impede escrever mensagem no NOME de um colega. Admin pode falar
-- em qualquer equipe; não pode falar como outra pessoa. Mesmo cuidado da
-- policy de `autor_id` em `anotacoes` e de `closed_by` em `atendimentos`.
--
-- `is_alert` não é restringido aqui de propósito: o destaque para a equipe
-- inteira é justamente o que o admin precisa poder dar. `TeamRoleUi.
-- podeAlertar` e `team_message.dart` já descrevem "admin da equipe ou
-- admin geral" — isto torna a segunda metade verdadeira no banco.
drop policy if exists team_messages_insert_admin on public.team_messages;

create policy team_messages_insert_admin on public.team_messages
  for insert to authenticated
  with check (is_admin() and sender_id = auth.uid());


-- ----------------------------------------------------------------------------
-- 3. `anotacoes` já libera o admin — nada a fazer
-- ----------------------------------------------------------------------------
--
-- Conferido em `supabase/anotacoes_das_equipes.sql:87` e `:107`: as duas
-- policies começam por `is_admin()`. O bloco de anotações das 9 equipes
-- já estava aberto para o admin; era só a TELA que não oferecia a porta.
-- Registrado aqui para o próximo que vier não "corrigir" duas vezes.


-- ----------------------------------------------------------------------------
-- 4. CONFERÊNCIA — rode depois, e leia o resultado
-- ----------------------------------------------------------------------------
--
-- a) As policies entraram?
--
--   select policyname, cmd, qual, with_check
--   from pg_policies
--   where schemaname = 'public' and tablename = 'team_messages'
--   order by cmd, policyname;
--
--   -- esperado: as duas novas (`..._select_admin`, `..._insert_admin`)
--   -- MAIS as que já existiam. Se as antigas desapareceram, algo as
--   -- apagou e os membros comuns perderam o chat — restaure antes de usar.
--
-- b) O admin lê mesmo as 9? Rodando COMO ele (não com service_role, que
--    ignora RLS e responderia "sim" sempre — foi assim que um teste deste
--    projeto já passou validando nada):
--
--   select team, count(*)
--   from public.team_messages
--   where top_id = '<id do top>'
--   group by team
--   order by team;
--
-- c) Hoje isso devolve pouco ou nada, e não é defeito: `top_team_members`
--    está vazia e ninguém escreveu em chat de equipe ainda. Prova de
--    leitura com a tabela vazia não prova nada — escreva uma mensagem de
--    teste numa equipe pelo app, com uma conta de membro, e releia como
--    admin.
-- ----------------------------------------------------------------------------
