-- ===========================================================================
-- O COORDENADOR TINHA PODER SOBRE A EQUIPE E NÃO CONSEGUIA VER NINGUÉM
--
-- Achado em 23/11/2026, medindo capacidade por capacidade com contas de
-- verdade. O coordenador de uma equipe:
--
--   . INCLUI membro na equipe dele ............ funciona (201)
--   . retira a liberação de um membro ......... **não funciona**
--   . bloqueia um membro ...................... **não funciona**
--   . remove um membro ........................ **não funciona**
--
-- E não dá erro. As três voltam **204**, que é sucesso — com zero linhas
-- afetadas. Esse é o detalhe que faz o defeito passar: quem testa pelo
-- código de resposta conclui que funcionou. Só olhando o dado depois é que
-- aparece que nada mudou.
--
-- ---------------------------------------------------------------------------
-- A CAUSA: A POLICY DE LEITURA DESFAZ AS DE ESCRITA
--
-- As policies de escrita dão o poder, explicitamente:
--
--   top_team_members_update  using (is_team_coordenador(top_id, team) or is_admin())
--   top_team_members_delete  using (is_team_coordenador(top_id, team) or is_admin())
--   top_team_members_insert  check ((is_team_admin(top_id, team) or is_admin()) and ...)
--
-- E a de leitura tira:
--
--   top_team_members_select  using (profile_id = auth.uid() or is_admin())
--
-- O coordenador vê **só a própria linha**. E um `update ... where` ou
-- `delete ... where` precisa LER as linhas para achar quais alterar — a
-- policy de SELECT se aplica a essa leitura. Sem ver, não altera. As
-- policies de UPDATE e DELETE para coordenador eram letra morta: davam um
-- poder que a leitura tornava inalcançável.
--
-- Pior que o efeito no banco é o efeito na tela: a equipe aparece **vazia**
-- para quem a coordena. Ele monta a equipe, fecha o app, abre de novo e não
-- vê ninguém — nem quem ele mesmo acabou de incluir.
--
-- É a mesma família do defeito das 9 equipes que o `CLAUDE.md` registra, de
-- cabeça para baixo: lá a tela fechava porta que o banco deixava aberta;
-- aqui o banco fecha com uma policy o que abre com outras três.
--
-- ---------------------------------------------------------------------------
-- A CORREÇÃO, E POR QUE `is_team_admin` E NÃO `is_team_coordenador`
--
-- `is_team_admin(top, team)` é verdadeiro para **coordenador e
-- subcoordenador**; `is_team_coordenador`, só para coordenador. A policy de
-- INSERT já usa `is_team_admin` — ou seja, o subcoordenador pode incluir
-- membro. Deixá-lo incluir e não deixá-lo ver seria repetir o defeito num
-- degrau abaixo.
--
-- `top_id` e `team` na chamada são **da linha que está sendo lida**, então
-- o alcance é por equipe: o coordenador de logística vê a logística e nada
-- mais. Verificado — tentar mexer em `midia` continua dando 403.
--
-- ---------------------------------------------------------------------------
-- NÃO HÁ RECURSÃO, E ISSO PRECISA SER DITO
--
-- `is_team_admin` LÊ `top_team_members`, e está sendo chamada de dentro de
-- uma policy DESSA tabela. Não entra em laço porque a função é
-- `security definer`: roda como o dono e não passa pela RLS. É o mesmo
-- arranjo que `top_team_members_update` já usa em produção com
-- `is_team_coordenador`.
--
-- O que **não** se pode fazer aqui é trocar a função por um `exists (select
-- ... from top_team_members ...)` escrito dentro da policy: aí a leitura
-- interna passaria pela própria policy e o laço seria real.
-- ===========================================================================

drop policy if exists top_team_members_select on public.top_team_members;

create policy top_team_members_select
  on public.top_team_members for select
  using (
    -- A própria linha: é assim que cada um sabe em que equipe está, se foi
    -- liberado e se está bloqueado. `fetchMyTeams(somenteAtivas: false)`
    -- depende disto.
    profile_id = auth.uid()
    -- Admin vê as 9, decisão do dono em 11/10/2026.
    or public.is_admin()
    -- Quem coordena vê quem coordena. Sem isto as policies de UPDATE e
    -- DELETE dele não alcançam linha nenhuma.
    or public.is_team_admin(top_id, team)
  );

-- Conferência (com um coordenador de verdade, não com admin):
--   GET  /rest/v1/top_team_members?select=profile_id,team  -> a equipe dele
--   PATCH .../top_team_members?profile_id=eq.<X>&team=eq.<dele>
--         {"released": false}                              -> tem de MUDAR
--   PATCH .../top_team_members?...&team=eq.<outra>          -> 403
--
-- E confira pelo DADO, não pelo status: 204 com zero linhas é sucesso.
