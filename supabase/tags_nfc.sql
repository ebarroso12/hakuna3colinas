-- ============================================================================
-- Aplicado em producao (projeto jitfbambhmfnqiatwoud) em 09/10/2026.
--
-- Identificacao de participante por tag NFC.
--
-- Principio que governa este arquivo inteiro: LER A TAG NAO AUTENTICA.
-- NTAG213/215 sao clonaveis, entao posse da pulseira nao prova identidade.
-- O token so e resolvido para quem JA esta logado e e Hakuna liberado no
-- Top. Quem acha a pulseira no chao e abre a URL nao descobre nada.
-- ============================================================================

create type tag_status as enum ('ativa','revogada','substituida');


-- ----------------------------------------------------------------------------
-- Vinculo tag <-> participante
--
-- A tag grava APENAS `token`: 32 hex = 128 bits aleatorios, sem
-- significado. Nunca nome, documento, telefone ou dado medico.
--
-- `tag_uid` (o UID de fabrica) fica guardado so para inventario fisico -
-- saber qual pulseira e qual na caixa. NAO e usado como identidade, porque
-- e justamente o que se copia ao clonar uma tag.
-- ----------------------------------------------------------------------------
create table if not exists public.participant_tags (
  id                uuid primary key default gen_random_uuid(),
  token             text not null unique,
  participant_id    uuid not null references public.top_participants(id) on delete cascade,
  top_id            uuid not null references public.tops(id) on delete cascade,
  status            tag_status not null default 'ativa',
  tag_uid           text,
  issued_by         uuid references public.profiles(id),
  issued_at         timestamptz not null default now(),
  revoked_by        uuid references public.profiles(id),
  revoked_at        timestamptz,
  revoked_reason    text,
  replaced_by_token text
);

-- Um participante so pode ter UMA tag ativa. Trocar a pulseira exige
-- revogar a anterior - e isso que faz a tag perdida parar de valer.
create unique index if not exists idx_participant_tags_ativa
  on public.participant_tags (participant_id) where status = 'ativa';
create index if not exists idx_participant_tags_token
  on public.participant_tags (token);


-- ----------------------------------------------------------------------------
-- Auditoria LGPD das leituras
--
-- Registra TODA leitura, inclusive as que falham: tentativa com tag
-- revogada ou desconhecida e exatamente o que a auditoria precisa mostrar.
-- ----------------------------------------------------------------------------
create table if not exists public.tag_leituras (
  id             bigserial primary key,
  token          text not null,
  participant_id uuid references public.top_participants(id) on delete set null,
  top_id         uuid references public.tops(id) on delete cascade,
  lida_por       uuid references public.profiles(id),
  resultado      text not null,
  latitude       double precision,
  longitude      double precision,
  lida_em        timestamptz not null default now()
);

create index if not exists idx_tag_leituras_token
  on public.tag_leituras (token, lida_em desc);


alter table public.participant_tags enable row level security;
alter table public.tag_leituras     enable row level security;


-- ----------------------------------------------------------------------------
-- Policies
-- ----------------------------------------------------------------------------

-- Resolver um token exige estar logado E ser Hakuna liberado no Top (ou
-- admin). Quem nao tem acesso recebe ZERO LINHAS, nao um erro - a resposta
-- nao pode confirmar a existencia do token para quem nao deveria saber.
create policy participant_tags_select on public.participant_tags
for select using (
  is_admin()
  or exists (
    select 1 from public.top_hakunas h
    where h.top_id = participant_tags.top_id
      and h.profile_id = auth.uid()
      and h.released = true
  )
);

-- Emitir, revogar e substituir tag e so de admin. Hakuna le, nao emite.
create policy participant_tags_insert on public.participant_tags
for insert with check (is_admin() and issued_by = auth.uid());

create policy participant_tags_update on public.participant_tags
for update using (is_admin()) with check (is_admin());

-- Sem DELETE de proposito: tag nao se apaga, se revoga. Apagar perderia o
-- rastro de que aquela pulseira existiu e de quem a portava.

create policy tag_leituras_select on public.tag_leituras
for select using (lida_por = auth.uid() or is_admin());

create policy tag_leituras_insert on public.tag_leituras
for insert with check (lida_por = auth.uid());

-- Sem UPDATE nem DELETE: log de auditoria que pode ser alterado nao e
-- auditoria.
