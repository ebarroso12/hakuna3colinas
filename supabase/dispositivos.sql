-- ===========================================================================
-- TOKENS DE APARELHO PARA PUSH (FCM)
--
-- Aplicada em produção em 11/10/2026. Este arquivo existe para o banco não
-- ficar à frente do repositório — foi exatamente o que aconteceu com
-- `top_imagens`, criada direto em produção e sem migração aqui, e que uma
-- reconstrução do schema teria perdido em silêncio.
--
-- A tabela está vazia e continua vazia até o app passar a registrar token,
-- o que depende do projeto Firebase existir. O plano completo está em
-- `docs/push_com_app_fechado.md`.
-- ===========================================================================

create table if not exists public.dispositivos (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid not null references public.profiles (id) on delete cascade,

  -- ÚNICO: o mesmo aparelho reinstalado pode devolver o mesmo token, e sem
  -- unicidade a pessoa receberia o alarme duas vezes. É o alvo do
  -- `onConflict` no upsert do app — índice único SIMPLES de propósito:
  -- índice parcial quebraria o upsert (o Postgres não infere parcial na
  -- forma simples do `ON CONFLICT`; foi o bug da v1.0.29 neste projeto).
  fcm_token   text not null unique,

  plataforma  text not null default 'android'
    check (plataforma in ('android', 'ios', 'web')),

  -- Para faxina: token que o FCM recusar com `UNREGISTERED` é apagado no
  -- disparo. Sem isso a lista cresce para sempre e cada alarme fica mais
  -- lento — e alarme lento é alarme pior.
  visto_em    timestamptz not null default now(),
  criado_em   timestamptz not null default now()
);

create index if not exists idx_dispositivos_profile
  on public.dispositivos (profile_id);

alter table public.dispositivos enable row level security;

-- Cada um gerencia os PRÓPRIOS aparelhos. Token de aparelho alheio não é
-- dado que membro de equipe precise ver, e o disparo roda com
-- `service_role`, que ignora RLS — nenhuma policy de leitura ampla é
-- necessária.
drop policy if exists dispositivos_proprios on public.dispositivos;
create policy dispositivos_proprios
  on public.dispositivos for all
  using (profile_id = auth.uid())
  with check (profile_id = auth.uid());
