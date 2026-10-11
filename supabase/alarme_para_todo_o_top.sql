-- ============================================================================
-- 11/10/2026 — EMERGÊNCIA: TODOS DISPARAM, TODOS RECEBEM, COM GPS E NOME
-- ============================================================================
--
-- Decisão do dono do projeto, nestas palavras: "se alguma pessoa apertar
-- emergência todos devem ver o lugar via GPS e quem está chamando".
--
-- O ACHADO QUE MOTIVOU ISTO, e ele é grave
--
-- `pertence_ao_top()` — a guarda atual do alarme — exige ser admin, Hakuna
-- liberado em `top_hakunas`, OU membro liberado em `top_team_members`:
--
--   is_admin()
--   or exists (top_hakunas  ... released = true)
--   or exists (top_team_members ... released = true and blocked = false)
--
-- Conferido no repositório: `top_team_members` está vazia (é a razão pela
-- qual as 9 equipes não apareciam no app) e `CLAUDE.md` registra que há
-- **só 1 Hakuna liberado no Top 1782, o próprio admin**.
--
-- Some as duas coisas: HOJE, se alguém apertar emergência, o único que
-- recebe é o admin. A função mais crítica do app chega a uma pessoa.
--
-- Isso não é bug de código — é a guarda certa aplicada a um banco sem o
-- dado operacional que ela pressupõe. E é exatamente o tipo de falha que
-- não aparece em teste nenhum: a policy está correta, a fila funciona, o
-- som toca. Só não há ninguém do outro lado.
--
-- A REGRA NOVA
--
-- `pode_alarmar_no_top()`: qualquer pessoa **aprovada** cujo Top não está
-- em `draft`. É a MESMA régua que o projeto já usa para o chat geral (ver
-- `anotacoes_das_equipes.sql:91-97`), onde ela significa "todo
-- participante aprovado do Top enxerga". Não é "qualquer um logado":
-- `is_approved()` é o portão que o `AuthGate` já impõe, e Top em `draft`
-- continua fechado.
--
-- Mantém-se a escada por baixo (admin · Hakuna · membro de equipe) para o
-- caso de `approved` se tornar mais restrito algum dia — numa função de
-- emergência, a soma de caminhos é a favor de alguém ser avisado.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. Quem dispara e quem recebe o alarme
-- ----------------------------------------------------------------------------
create or replace function public.pode_alarmar_no_top(p_top_id uuid)
returns boolean language sql stable security definer
set search_path = public as $$
  select
    -- Caminho novo: todo aprovado de um Top que não está em draft.
    (
      is_approved()
      and exists (
        select 1 from public.tops t
        where t.id = p_top_id and t.status <> 'draft'::public.top_status
      )
    )
    -- A escada antiga continua, somada. Redundante hoje e de propósito.
    or public.pertence_ao_top(p_top_id);
$$;

revoke execute on function public.pode_alarmar_no_top(uuid) from public;
revoke execute on function public.pode_alarmar_no_top(uuid) from anon;
grant  execute on function public.pode_alarmar_no_top(uuid) to authenticated;


-- As policies da v1.0.35 são substituídas pelas novas. Aqui o `drop` é
-- seguro — ao contrário de `team_messages`, estas duas estão no
-- repositório (`equipes_alarme_mapa_e_blocos.sql`), então eu sei
-- exatamente o que estou tirando.
drop policy if exists top_alerts_insert_qualquer_equipe on public.top_alerts;
drop policy if exists top_alerts_select_qualquer_equipe on public.top_alerts;

-- `sender_id = auth.uid()` fica: qualquer um dispara, ninguém dispara no
-- NOME de outro. Alarme falso atribuído a um colega é acusação.
create policy top_alerts_insert_todo_o_top on public.top_alerts
  for insert to authenticated
  with check (sender_id = auth.uid() and pode_alarmar_no_top(top_id));

create policy top_alerts_select_todo_o_top on public.top_alerts
  for select to authenticated
  using (pode_alarmar_no_top(top_id));

-- A policy ORIGINAL, de antes da v1.0.35, exigia `top_hakunas.released`
-- e foi listada em `revisao_10_10_correcoes.sql:95` como "ninguém
-- consegue disparar alarme". Se ela ainda existir, some com as novas
-- (policies são OR) e não atrapalha — mas é lixo que confunde a próxima
-- auditoria.
drop policy if exists top_alerts_insert_hakuna on public.top_alerts;


-- ----------------------------------------------------------------------------
-- 2. QUEM ESTÁ CHAMANDO — o nome viaja dentro do alarme
-- ----------------------------------------------------------------------------
--
-- `top_alerts` só tem `sender_id` (uuid), e `profiles` é fechada:
-- `profiles_select_own_or_admin` = `id = auth.uid() or is_admin()`
-- (ver `fix_profiles_rls_recursion.sql:18`). Ou seja, quem recebe o
-- alarme **não consegue** resolver o uuid em nome. A faixa vermelha
-- mostrava hora e mensagem, e quem chamava era um uuid que ela nem exibia.
--
-- Duas saídas possíveis. Escolhi a coluna, não a função:
--
--   (a) coluna `sender_name` no próprio alarme  <- esta
--   (b) função `security definer` que resolve o nome
--
-- (a) ganha por três motivos de campo:
--   1. O alarme chega por Realtime (`.stream()`), que não passa por RPC.
--      Com (b) seriam duas idas à rede no pior momento possível.
--   2. Funciona OFFLINE: o aparelho grava o alarme na fila com o nome já
--      dentro. Com (b), sem rede o nome não resolve.
--   3. Guarda o nome DO MOMENTO do disparo, que é o que um registro de
--      emergência precisa dizer seis meses depois.
--
-- O custo é desnormalização: trocar de nome não reescreve alarme antigo.
-- Para registro de emergência isso é a vantagem, não o defeito.
alter table public.top_alerts
  add column if not exists sender_name text;

comment on column public.top_alerts.sender_name is
  'Nome de quem disparou, no momento do disparo. Desnormalizado de '
  'propósito: `profiles` é fechada para quem recebe o alarme, o Realtime '
  'não passa por RPC, e o nome precisa existir offline. Pode ser null em '
  'alarme antigo ou disparado antes de o perfil carregar.';


-- ----------------------------------------------------------------------------
-- 3. CONFERÊNCIA — rode e leia
-- ----------------------------------------------------------------------------
--
-- a) A policy nova está valendo?
--
--   select policyname, cmd from pg_policies
--   where schemaname='public' and tablename='top_alerts' order by cmd;
--
--   -- esperado: top_alerts_insert_todo_o_top, top_alerts_select_todo_o_top
--
-- b) QUANTAS PESSOAS receberiam um alarme agora? É a pergunta que importa,
--    e a que ninguém havia feito:
--
--   select count(*) as receberiam
--   from public.profiles p
--   where p.approved = true;
--
--   -- Compare com o de ANTES da mudança, que é o número real de hoje:
--   select count(*) as recebiam_antes from public.profiles p
--   where p.id in (
--     select profile_id from public.top_hakunas
--      where top_id = '<id do top>' and released = true
--     union
--     select profile_id from public.top_team_members
--      where top_id = '<id do top>' and released = true and blocked = false
--   ) or p.role = 'admin';
--
--   -- A expectativa é "antes = 1". Se vier 1, este arquivo acabou de
--   -- transformar o alarme de inútil em funcional, e vale registrar o
--   -- número no CHANGELOG.
--
-- c) `sender_name` entrou?
--
--   select column_name, data_type from information_schema.columns
--   where table_schema='public' and table_name='top_alerts'
--     and column_name='sender_name';
--
-- d) TESTE DE VERDADE, com sessão simulada — não com service_role, que
--    ignora RLS e responderia "sim" sempre:
--
--    Logue como alguém que NÃO é admin, NÃO é Hakuna liberado e NÃO está
--    em equipe nenhuma. Dispare o alarme pelo app. Confirme que:
--      - o insert passou (a linha existe em `top_alerts`);
--      - uma segunda conta igualmente sem vínculo RECEBE a faixa;
--      - `sender_name` veio preenchido;
--      - `latitude`/`longitude` vieram preenchidos (exige permissão de
--        GPS concedida no aparelho — no navegador o usuário tem de
--        aceitar o pedido do browser).
-- ----------------------------------------------------------------------------
