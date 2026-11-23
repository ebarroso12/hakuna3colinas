-- ===========================================================================
-- A CONTA QUE SE AUTOCADASTRA NÃO VIA NADA
--
-- Achado em 23/11/2026, cadastrando uma ficha de TESTE pelo caminho real
-- (`acesso/cadastrar`) e entrando com ela. A conta nasce `approved = true`,
-- o login por número funciona, o token sai — e a lista de Tops volta
-- VAZIA. Ou seja: as 216 pessoas se cadastrariam, entrariam e achariam o
-- app vazio, sem erro em tela nenhuma.
--
-- Não é um defeito, são dois, e os dois têm a mesma forma: **a régua de
-- "todo aprovado do Top" existe em algumas policies e falta em outras.**
--
-- ---------------------------------------------------------------------------
-- 1. `tops_select_linked` — A POLICY MAIS RESTRITIVA QUE TUDO O QUE A USA
--
-- A versão viva é a original do `schema.sql:264`: exige vínculo em
-- `top_hakunas` ou `top_senderistas`, ou `role = 'admin'`.
--
-- E `acesso/cadastrar` NÃO inscreve em `top_senderistas`. Ele vincula a
-- ficha (`top_participants.linked_profile_id`) e para aí. Quem insere em
-- `top_senderistas` é `colocarNoTop`, usado pelo caminho do ADMIN
-- (`liberar`) — não pelo autocadastro. Então o autocadastro produz conta
-- aprovada e sem nenhum dos dois vínculos que a policy pede.
--
-- O `CLAUDE.md` afirma, em `pedido_com_numero_do_top.sql:7`, que esta
-- policy "já abre todo Top não rascunho para conta aprovada". **O
-- repositório nunca teve essa cláusula** — conferido por busca em
-- `on public.tops`: só o `schema.sql` cria a policy, na forma antiga. A
-- cláusula existia apenas em produção, como as oito peças anteriores, e
-- aqui é pior que uma tabela faltando: a policy EXISTE e parece certa.
--
-- A prova de que a régua é esta, e não invenção minha, está no banco:
-- `pode_alarmar_no_top()` já aceita `is_approved() and status <> 'draft'`.
-- Hoje a pessoa pode DISPARAR ALARME num Top que ela não consegue ver.
--
-- ---------------------------------------------------------------------------
-- 2. O CHAT `geral` — ESTE FOI MEU ERRO, NÃO HERANÇA
--
-- `team_messages` nunca esteve no repositório (o `CLAUDE.md` diz isso), e
-- eu a reconstruí em `00_TABELAS_QUE_FALTAVAM.sql` a partir dos models.
-- Escrevi as policies com `is_team_member(top_id, team)` e **esqueci a
-- cláusula do `geral`**.
--
-- `geral` não é equipe: é o canal que todo participante aprovado do Top
-- enxerga. E `top_team_members` nasce VAZIA, então com a policy como eu a
-- escrevi o chat geral de um Top novo é invisível para todos menos o
-- admin — o mesmo defeito que o `CLAUDE.md` registra como já corrigido na
-- tela das 9 equipes, reintroduzido pelo banco.
--
-- A forma canônica não foi inventada: está em
-- `anotacoes_das_equipes.sql:91` e `:112`, copiada verbatim.
--
-- ---------------------------------------------------------------------------
-- POR QUE POLICIES SEPARADAS, E NÃO REESCRITA
--
-- Policies do mesmo comando são OR entre si. Somar uma amplia e não tira
-- nada de ninguém — e é o que permite aplicar isto num banco onde alguém
-- possa ter criado regra à mão que eu não conheço. O mesmo raciocínio de
-- `admin_ve_todas_as_equipes.sql`.
--
-- A exceção é `tops_select_linked`, que precisa ser substituída porque é
-- a MESMA policy que está restritiva demais; aí vale o `drop ... if
-- exists` do próprio nome, como manda a convenção do projeto.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. Todo aprovado vê todo Top que não é rascunho
-- ---------------------------------------------------------------------------
drop policy if exists "tops_select_linked" on public.tops;

create policy "tops_select_linked" on public.tops
  for select using (
    -- Caminho novo: a aprovação é global de propósito. Quem foi aprovado
    -- vê os Tops ativos; é por ali que se chega a qualquer outra coisa.
    (
      public.is_approved()
      and tops.status <> 'draft'::public.top_status
    )
    -- A escada antiga continua, somada. Ela cobre o que a nova não cobre:
    -- Hakuna ou senderista vinculado a um Top AINDA EM RASCUNHO, que é
    -- quem monta o evento antes de ativá-lo.
    or exists (
      select 1 from public.top_hakunas th
      where th.top_id = tops.id and th.profile_id = auth.uid()
    )
    or exists (
      select 1 from public.top_senderistas ts
      where ts.top_id = tops.id and ts.profile_id = auth.uid()
    )
    or public.is_admin()
  );

-- ---------------------------------------------------------------------------
-- 2. O canal `geral` é de todo aprovado do Top
-- ---------------------------------------------------------------------------
drop policy if exists team_messages_select_geral on public.team_messages;

create policy team_messages_select_geral
  on public.team_messages for select to authenticated
  using (
    team = 'geral'::public.team_key
    and public.is_approved()
    and exists (
      select 1 from public.tops t
      where t.id = team_messages.top_id
        and t.status <> 'draft'::public.top_status
    )
  );

drop policy if exists team_messages_insert_geral on public.team_messages;

create policy team_messages_insert_geral
  on public.team_messages for insert to authenticated
  with check (
    sender_id = auth.uid()
    and team = 'geral'::public.team_key
    and public.is_approved()
    and exists (
      select 1 from public.tops t
      where t.id = team_messages.top_id
        and t.status <> 'draft'::public.top_status
    )
    -- Alerta continua sendo da coordenação e do admin, que entram pelas
    -- policies deles. Membro comum marcando alerta esvazia o significado
    -- do alerta para todo mundo — a mesma razão da policy de membro.
    and is_alert = false
  );

-- Conferência (como a conta recém-cadastrada, não como admin):
--   select count(*) from public.tops;              -> >= 1
--   select count(*) from public.team_messages
--    where team = 'geral';                         -> lê sem erro
