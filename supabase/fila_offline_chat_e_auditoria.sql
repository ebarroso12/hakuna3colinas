-- ============================================================================
-- v1.0.18 — client_id para tudo que passa pela fila offline
--
-- POR QUE ISTO E NECESSARIO
--
-- O outbox reenvia uma entrada quando o envio anterior falhou. "Falhou" nao
-- quer dizer "nao chegou": o insert pode ter sido aplicado e a resposta ter
-- se perdido na volta — o caso normal quando o sinal cai no meio. Sem uma
-- chave gerada no aparelho, o reenvio cria uma SEGUNDA linha.
--
-- `atendimentos` ja resolve isso: tem `client_id` unico e o app usa
-- `upsert(onConflict: 'client_id', ignoreDuplicates: true)`. As tabelas
-- abaixo vao entrar na fila agora e precisam do mesmo.
--
-- Para o chat isso e visivel: a mesma mensagem apareceria duas vezes na
-- tela. Para mensagem marcada como alerta, duas vezes um alerta.
-- Para `tag_leituras` e `audit_log` e pior de outra forma: auditoria com
-- linha duplicada deixa de servir para contar quantas vezes uma pulseira
-- revogada foi apresentada.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. CHAT
--
-- Nullable de proposito: as mensagens que ja existem nao tem client_id e
-- NOT NULL exigiria inventar um para cada uma. O indice unico e PARCIAL
-- (`where client_id is not null`), entao as linhas antigas nao colidem
-- entre si — varios NULL num indice unico comum tambem nao colidiriam no
-- Postgres, mas o indice parcial deixa a intencao explicita e nao indexa
-- linha que nunca sera consultada por essa coluna.
-- ----------------------------------------------------------------------------

alter table public.team_messages
  add column if not exists client_id uuid;

create unique index if not exists idx_team_messages_client_id
  on public.team_messages (client_id)
  where client_id is not null;

alter table public.top_hakuna_messages
  add column if not exists client_id uuid;

create unique index if not exists idx_top_hakuna_messages_client_id
  on public.top_hakuna_messages (client_id)
  where client_id is not null;

-- ----------------------------------------------------------------------------
-- 2. AUDITORIA
--
-- `tag_leituras` registra TODA leitura de pulseira, inclusive as que
-- falham — e justamente a tentativa com tag revogada ou desconhecida que a
-- auditoria precisa mostrar. Ate a v1.0.17 so a leitura ONLINE era
-- registrada: o `catch` que embrulhava a chamada engolia a falha e a
-- leitura offline nao deixava rastro nenhum.
-- ----------------------------------------------------------------------------

alter table public.tag_leituras
  add column if not exists client_id uuid;

create unique index if not exists idx_tag_leituras_client_id
  on public.tag_leituras (client_id)
  where client_id is not null;

-- `lida_em` passa a vir do aparelho: offline a leitura acontece horas antes
-- de chegar aqui, e `now()` registraria o instante do SYNC, nao o da
-- leitura. Auditoria com hora errada e pior que sem hora — da a impressao
-- de precisao que ela nao tem. O default fica para quem nao mandar.
--
-- Nao ha backfill: as linhas existentes foram todas gravadas online, onde
-- `now()` era o instante correto.

alter table public.audit_log
  add column if not exists client_id uuid;

create unique index if not exists idx_audit_log_client_id
  on public.audit_log (client_id)
  where client_id is not null;

-- `created_at` pelo mesmo motivo de `lida_em`: o evento tem a hora em que
-- aconteceu no aparelho, nao a do upload.
alter table public.audit_log
  add column if not exists occurred_at timestamptz;

create index if not exists idx_audit_log_quando
  on public.audit_log (coalesce(occurred_at, created_at) desc);

create index if not exists idx_audit_log_top
  on public.audit_log (top_id, coalesce(occurred_at, created_at) desc);

-- ----------------------------------------------------------------------------
-- 3. RLS — nada muda, e isso e deliberado
--
-- As policies existentes ja prendem `sender_id = auth.uid()`,
-- `lida_por = auth.uid()` e `actor_id = auth.uid()`. Passar a escrever pela
-- fila NAO afrouxa nada: o upsert sobe com a sessao do proprio Hakuna, e a
-- RLS avalia igual. Uma entrada da fila de outra pessoa (aparelho
-- compartilhado, troca de login antes do sync) e REJEITADA pela RLS — e
-- tem de ser: o registro pertence a quem atendeu.
--
-- Consequencia pratica que precisa estar escrita em algum lugar: se o
-- Hakuna A registrar offline e o Hakuna B logar no mesmo aparelho antes do
-- sync, a fila de A travaria com erro de RLS. Hoje o app nao troca de
-- usuario sem limpar o aparelho, mas isso e convencao, nao garantia.
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- 4. Verificacao
-- ----------------------------------------------------------------------------
-- select table_name, column_name
--   from information_schema.columns
--  where table_schema='public' and column_name in ('client_id','occurred_at')
--  order by table_name;
