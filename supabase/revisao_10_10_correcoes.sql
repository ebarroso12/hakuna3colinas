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
