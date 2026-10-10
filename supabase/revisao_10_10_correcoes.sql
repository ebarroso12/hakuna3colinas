-- ============================================================================
-- Revisao linha a linha de 10/10/2026 — tres correcoes
-- ============================================================================

-- ----------------------------------------------------------------------------
-- BUG 1 (CRITICO): atendimento sem fix de GPS era PERDIDO
--
-- `atendimentos.latitude/longitude` eram NOT NULL sem default. O app captura
-- a posicao com try/catch e segue sem ela DE PROPOSITO — o comentario no
-- codigo diz "atender e mais importante que saber onde". O banco discordava,
-- e o banco ganha.
--
-- Cadeia completa da falha, em campo:
--   1. mata fechada, GPS sem fix
--   2. Hakuna registra o atendimento; o app aceita
--   3. entra na fila local
--   4. volta o sinal, sobe
--   5. Postgres recusa: 23502 not_null_violation
--   6. SyncService classifica 23xxx como PERMANENTE
--   7. vai para a QUARENTENA
--   8. o registro clinico NUNCA chega ao servidor
--
-- Null e o valor honesto: "nao sabiamos onde". 0,0 seria mentira — e um
-- ponto no Atlantico, a 600 km da costa da Africa.
-- ----------------------------------------------------------------------------

alter table public.atendimentos
  alter column latitude  drop not null,
  alter column longitude drop not null;

comment on column public.atendimentos.latitude is
  'Null quando nao houve fix de GPS. Atender vem antes de localizar.';

-- ----------------------------------------------------------------------------
-- BUG 2 (ALTO): posicoes de GPS duplicavam no reenvio
--
-- `publishPosition` fazia INSERT puro, sem client_id. O outbox reenvia
-- quando o envio anterior "falhou" — e falhou inclui o insert ter chegado e
-- so a resposta ter se perdido, que e o normal com sinal ruim.
--
-- `StatsService` soma a distancia entre pontos consecutivos, entao ponto
-- duplicado INFLA a distancia e, com ela, a estimativa de calorias.
--
-- E a entidade de MAIOR VOLUME do sistema: um ponto a cada 15 m. Atendimento,
-- foto, chat e auditoria ja tinham client_id desde a v1.0.18; a posicao, que
-- e a que mais reenvia, nao tinha.
-- ----------------------------------------------------------------------------

alter table public.hakuna_positions
  add column if not exists client_id uuid;

create unique index if not exists idx_positions_client_id
  on public.hakuna_positions (client_id)
  where client_id is not null;

comment on column public.hakuna_positions.client_id is
  'Gerado no aparelho. Torna o reenvio da fila idempotente: sem ele, ponto
   duplicado infla a distancia percorrida e as calorias.';

-- ----------------------------------------------------------------------------
-- BUG 3 (BAIXO): is_in_top_community era oraculo anonimo
--
-- SECURITY DEFINER, recebendo p_profile_id arbitrario e SEM NENHUMA checagem
-- de quem chama. Qualquer um com a chave anonima podia perguntar "o perfil X
-- esta no Top Y?" e receber a resposta.
--
-- Exige conhecer dois UUIDs, entao nao da para varrer — mas e um oraculo nao
-- autenticado, e nao precisa existir: a unica policy que a usa
-- (direct_messages_insert_self) roda como `authenticated`.
--
-- Medido antes e depois com has_function_privilege. Os TRES revokes sao
-- necessarios: o Supabase concede EXECUTE direto a anon e authenticated por
-- ALTER DEFAULT PRIVILEGES, e grant direto nao se remove revogando de PUBLIC.
--
-- VERIFICADAS E DESCARTADAS no mesmo exame (chamadas de verdade como anon):
--   searchable_profiles     -> []     (guarda is_team_admin/is_admin)
--   member_names_for_team   -> []     (guarda is_approved/is_team_member)
--   is_admin / is_approved  -> false  (respondem sobre QUEM CHAMA)
-- ----------------------------------------------------------------------------

revoke execute on function public.is_in_top_community(uuid, uuid) from public;
revoke execute on function public.is_in_top_community(uuid, uuid) from anon;
grant  execute on function public.is_in_top_community(uuid, uuid) to authenticated;

-- ----------------------------------------------------------------------------
-- NAO CORRIGIDO AQUI — depende de decisao do usuario
--
-- `top_hakunas` esta VAZIA, e estas policies exigem estar nela com
-- released = true, SEM escape de admin:
--
--   atendimentos_insert_self        INSERT   <- ninguem registra atendimento
--   atendimentos_select_same_top    SELECT   <- ninguem le atendimento
--   hakuna_positions_select_same_top SELECT  <- ninguem ve posicao de ninguem
--   top_hakuna_messages_*           ambos    <- chat dos Hakunas inutilizavel
--   top_alerts_insert_hakuna        INSERT   <- nao da para disparar alarme
--   notifications_insert_*          INSERT
--   attendance_members_insert_self  INSERT
--   nfc_tags_insert_hakuna          INSERT
--
-- Nao e bug de codigo: e dado operacional que falta. Alguem precisa ser
-- liberado como Hakuna no Top. Mexer nisso por conta propria seria decidir
-- quem atende — e isso e do usuario.
-- ----------------------------------------------------------------------------

-- ============================================================================
-- BUG 4 (CRITICO) — encontrado testando o BUG 2, e pior que ele
--
-- INDICE UNICO PARCIAL NAO E INFERIDO POR `ON CONFLICT (coluna)`.
--
-- Criei os indices de client_id como PARCIAIS (`where client_id is not null`)
-- achando que era a forma cuidadosa. O Postgres so infere indice parcial se a
-- instrucao REPETIR o predicado:
--     ON CONFLICT (client_id) WHERE client_id IS NOT NULL
--
-- O `upsert(onConflict: 'client_id')` do supabase_flutter gera a forma SEM
-- predicado, entao o banco respondia:
--     42P10: there is no unique or exclusion constraint matching the
--            ON CONFLICT specification
--
-- E `42xxx` e classificado como PERMANENTE em
-- SupabaseService._motivoPermanente. Logo, CADA escrita da fila iria para a
-- QUARENTENA, em silencio:
--     atendimento, posicao, mensagem de equipe, mensagem do Top,
--     leitura de tag, auditoria
--
-- Seis dos sete indices estavam assim. So `atendimento_fotos_client_id_key`
-- escapou, porque e uma CONSTRAINT antiga e nao um indice parcial meu.
--
-- Era o pior bug do dia, introduzido por mim na v1.0.18, e so apareceria no
-- primeiro teste em aparelho - como "o app grava tudo e nada sobe".
--
-- CORRECAO: indice unico SIMPLES. Comportamento identico para as linhas
-- antigas (o Postgres trata NULLs como distintos entre si, entao varias
-- linhas sem client_id continuam permitidas) e passa a ser inferivel.
-- ============================================================================

drop index if exists public.idx_atendimentos_client_id;
create unique index idx_atendimentos_client_id on public.atendimentos (client_id);

drop index if exists public.idx_positions_client_id;
create unique index idx_positions_client_id on public.hakuna_positions (client_id);

drop index if exists public.idx_team_messages_client_id;
create unique index idx_team_messages_client_id on public.team_messages (client_id);

drop index if exists public.idx_top_hakuna_messages_client_id;
create unique index idx_top_hakuna_messages_client_id on public.top_hakuna_messages (client_id);

drop index if exists public.idx_tag_leituras_client_id;
create unique index idx_tag_leituras_client_id on public.tag_leituras (client_id);

drop index if exists public.idx_audit_log_client_id;
create unique index idx_audit_log_client_id on public.audit_log (client_id);

-- ----------------------------------------------------------------------------
-- PROVADO com a sessao do admin simulada (role authenticated + JWT), gravando
-- de verdade e desfazendo no fim:
--
--   atendimento SEM fix de GPS ....... GRAVOU
--   posicao enviada 2x ............... gravou 1 linha   <- idempotencia ok
--   chat dos Hakunas ................. GRAVOU
--   auditoria de leitura de tag ...... GRAVOU
--   leitura: atendimentos 1, posicoes 1, mensagens 1, participantes 216
--
-- Confirmado depois: todas as tabelas de volta a zero.
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- DIVIDA REGISTRADA, nao corrigida: `client_id` tem tipo diferente por tabela
--
--   atendimentos, atendimento_fotos  -> text
--   demais                           -> uuid
--
-- Funciona nos dois: o app manda UUID canonico em minusculo e o Postgres
-- converte para as colunas uuid. A diferenca so apareceria se o mesmo id
-- fosse enviado em formatos distintos (maiuscula, chaves) - `uuid` normaliza,
-- `text` nao. O app gera um formato so.
--
-- Nao unificado porque mudar tipo de coluna com dado dentro e risco maior que
-- o ganho. Se um dia `atendimentos` for migrada, fazer junto com fotos.
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- RESOLVIDO: top_hakunas deixou de estar vazia
--
-- O admin master foi liberado como Hakuna no Top 1782. Sem isso, oito
-- policies o bloqueavam - nao registrava nem lia atendimento, nao via posicao
-- de ninguem, nao usava o chat dos Hakunas e nao disparava alarme.
--
--   insert into public.top_hakunas (top_id, profile_id, released)
--   select t.id, p.id, true from public.tops t cross join public.profiles p
--    where t.top_number = '1782' and p.is_master_admin = true
--   on conflict (top_id, profile_id) do update set released = true;
-- ----------------------------------------------------------------------------
