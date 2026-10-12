-- ===========================================================================
-- APLICAR v1.0.39 — COLE ISTO INTEIRO NO SQL EDITOR DO SUPABASE
-- ===========================================================================
--
-- Arquivo GERADO, por conveniencia: e a concatenacao, na ordem correta, de
--   1. supabase/team_key_as_nove_equipes.sql
--   2. supabase/admin_ve_todas_as_equipes.sql
--   3. supabase/alarme_para_todo_o_top.sql
--
-- Os tres sao idempotentes: rodar de novo num banco ja certo nao faz nada.
-- A CONFERENCIA fica de fora de proposito — ela e so leitura e precisa que
-- voce troque <TOP_ID>. Rode `supabase/CONFERIR_APOS_APLICAR.sql` depois.
--
-- SE DER ERRO, me diga em qual PARTE.
--
-- Erro possivel na PARTE 1, em Postgres antigo:
--   "ALTER TYPE ... ADD VALUE cannot be executed inside a transaction block"
--   -> rode o bloco `do $$ ... $$;` sozinho, depois cada `alter type` um
--      a um. O Supabase atual nao deve dar isso.
--
-- Erro possivel na PARTE 3:
--   "function public.pertence_ao_top(uuid) does not exist"
--   -> rode `supabase/equipes_alarme_mapa_e_blocos.sql` antes. Ela foi
--      criada na v1.0.35; se nao existe, aquela migracao nao foi aplicada.
-- ===========================================================================


-- ###########################################################################
-- PARTE 1 de 3
-- ###########################################################################
-- ============================================================================
-- 11/10/2026 — AS 9 EQUIPES EXISTEM EM PRODUÇÃO E NÃO EXISTEM NO REPOSITÓRIO
-- ============================================================================
--
-- O dono do projeto abriu o app e não achou as 9 equipes. A correção da
-- TELA está em `lib/screens/team_chats_screen.dart` (ela listava só as
-- equipes em que a pessoa já era membro liberado, e `top_team_members`
-- nasce vazia, então todo mundo via zero). Este arquivo trata do outro
-- lado do mesmo problema.
--
-- O ACHADO: nada no repositório cria o enum `team_key`.
--
--   $ grep -rn "create type.*team_key" supabase/     ->  nada
--
-- O valor `hakunas` — a 9ª equipe, a de salvamento — entrou em produção
-- por dois comandos rodados à mão, e eles estão registrados apenas como
-- COMENTÁRIO em `supabase/equipes_alarme_mapa_e_blocos.sql:17-18`:
--
--     alter type public.team_key add value 'saude';           -- erro meu
--     alter type public.team_key rename value 'saude' to 'hakunas';
--
-- Comentário não roda. Num schema reconstruído a partir deste
-- repositório, `team_key` sai com 8 equipes + `geral` e a equipe de
-- salvamento desaparece de novo — sem chat, sem bloco de anotações, e
-- sem nada falhando alto o suficiente para alguém notar. É o mesmo
-- padrão de `top_imagens`, que ficou só em produção por um dia.
--
-- ESTE ARQUIVO É IDEMPOTENTE: rodar de novo num banco que já está certo
-- não faz nada. Pode ser rodado em produção para conferir.
--
-- O QUE ELE NÃO FAZ, E É PROPOSITAL
--
-- Não recria `top_team_members` nem `team_messages`. As duas também estão
-- fora do repositório (`grep -rn "create table.*top_team_members"` não
-- acha nada), mas eu não tenho acesso de leitura ao banco nesta sessão
-- para conferir colunas, defaults, constraints e policies. Escrever um
-- `create table` de memória produziria um arquivo que PARECE a fonte da
-- verdade e divergiria da produção em silêncio — pior que a ausência,
-- porque a ausência pelo menos não mente.
--
-- PENDÊNCIA, para quem tiver as credenciais: extrair o DDL real das duas
-- tabelas (`pg_dump --schema-only -t public.top_team_members
-- -t public.team_messages`) e versionar aqui.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. O enum, com as 9 equipes + o canal `geral`
-- ----------------------------------------------------------------------------
--
-- `geral` NÃO é equipe — é o canal que todo participante aprovado do Top
-- enxerga. Daí `TeamKeyUi.equipes` devolver 9 e não 10
-- (`lib/models/team.dart`, travado por `test/models/team_test.dart`).
--
-- A ordem é a da produção: as 8 originais, `hakunas` (acrescentada depois,
-- então no fim) e `geral`. Enum em Postgres ordena pela posição de
-- declaração, e `ADD VALUE` sem `BEFORE`/`AFTER` acrescenta no fim — é
-- como `hakunas` entrou lá. Mantendo igual aqui, `order by team` dá o
-- mesmo resultado nos dois lugares.
do $$
begin
  if not exists (
    select 1 from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'team_key' and n.nspname = 'public'
  ) then
    create type public.team_key as enum (
      'adm',
      'logistica',
      'voz',
      'intercessao',
      'producao',
      'midia',
      'eventos',
      'seguranca',
      'hakunas',
      'geral'
    );
  end if;
end
$$;


-- ----------------------------------------------------------------------------
-- 2. Os valores que faltarem, um a um
-- ----------------------------------------------------------------------------
--
-- Caso o tipo já exista com menos valores — que é exatamente o estado de
-- um banco criado a partir deste repositório antes de 11/10/2026.
--
-- `add value if not exists` é de PG 12+; o Supabase está muito à frente
-- disso. Cada `alter type` vai sozinho de propósito: em Postgres o valor
-- novo não pode ser USADO na mesma transação em que foi criado, e juntar
-- tudo num bloco com os `insert`/`update` de outro arquivo dá o erro
-- "unsafe use of new value of enum type", que não é óbvio de ler.
alter type public.team_key add value if not exists 'adm';
alter type public.team_key add value if not exists 'logistica';
alter type public.team_key add value if not exists 'voz';
alter type public.team_key add value if not exists 'intercessao';
alter type public.team_key add value if not exists 'producao';
alter type public.team_key add value if not exists 'midia';
alter type public.team_key add value if not exists 'eventos';
alter type public.team_key add value if not exists 'seguranca';
-- A que faltava. É esta a linha que este arquivo existe para garantir.
alter type public.team_key add value if not exists 'hakunas';
alter type public.team_key add value if not exists 'geral';


-- ----------------------------------------------------------------------------
-- 3. CONFERÊNCIA — tem de devolver 10, e tem de conter 'hakunas'
-- ----------------------------------------------------------------------------
--
-- Rode isto depois. Guarda que não é verificada é pior que guarda nenhuma:
-- ela dá a impressão de cobertura.
--
--   select count(*) as valores, bool_or(e.enumlabel = 'hakunas') as tem_hakunas
--   from pg_enum e
--   join pg_type t on t.oid = e.enumtypid
--   join pg_namespace n on n.oid = t.typnamespace
--   where t.typname = 'team_key' and n.nspname = 'public';
--
--   -- esperado:  valores = 10   tem_hakunas = true
--
-- E para ver se sobrou lixo do erro de nomenclatura (o valor `saude`, que
-- foi RENOMEADO e não deve existir — valor órfão num enum reaparece em
-- todo dropdown e em toda migração futura):
--
--   select e.enumlabel, e.enumsortorder
--   from pg_enum e
--   join pg_type t on t.oid = e.enumtypid
--   where t.typname = 'team_key'
--   order by e.enumsortorder;
--
--   -- 'saude' NÃO pode aparecer. Se aparecer, o rename não foi aplicado
--   -- e há duas equipes de salvamento no banco.
-- ----------------------------------------------------------------------------

-- ###########################################################################
-- PARTE 2 de 3
-- ###########################################################################
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

-- ###########################################################################
-- PARTE 3 de 3
-- ###########################################################################
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
