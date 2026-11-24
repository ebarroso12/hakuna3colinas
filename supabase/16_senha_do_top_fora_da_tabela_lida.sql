-- ===========================================================================
-- O HASH DA SENHA DO TOP SAI DA TABELA QUE TODO MUNDO LÊ
--
-- Segunda metade do conserto de 24/11/2026. A primeira foi o pepper
-- (`hashDoTop` na Edge Function `acesso`): vazar o hash deixou de entregar
-- a senha, porque quebrar fora do servidor passou a exigir um segredo que
-- não está no banco.
--
-- Mas o hash CONTINUAVA legível por toda conta aprovada, e isso é um elo a
-- mais do que o necessário:
--
--   `tops_select_linked`  -> `is_approved() and status <> 'draft'`
--   `GRANT SELECT`        -> `authenticated` tem `access_code_hash`
--   RLS                   -> é por LINHA, não por coluna
--
-- O caminho óbvio seria `revoke select (access_code_hash)`. **Não serve
-- hoje:** todo APK <= 1.0.52 manda `select *` em `fetchMyTops`, e com a
-- coluna revogada o PostgREST recusa a CONSULTA INTEIRA. A lista de Tops
-- sumiria para quem não atualizou — e é por ela que se chega a todo o
-- resto do app.
--
-- ---------------------------------------------------------------------------
-- A SAÍDA: MOVER O VALOR, NÃO A COLUNA
--
-- O hash passa a viver em `top_access_codes`, com RLS ligada e **nenhuma
-- policy** — o que nega para `anon` e `authenticated` (RLS sem policy nega
-- para todos; já morderam este projeto três vezes, aqui é de propósito).
-- `service_role` passa porque bypassa RLS, e é só por ali que a Edge
-- Function lê e escreve.
--
-- As colunas antigas de `tops` **ficam, vazias**. Isso é deliberado:
--
--   * APK antigo manda `select *` e continua funcionando — recebe as
--     colunas, agora nulas. Nada quebra, ninguém precisa atualizar;
--   * o trigger `tops_trava_senha` segue referenciando as três colunas.
--     Dropá-las faria `new.access_code_hash := old.access_code_hash`
--     estourar em TODO update de Top, e o admin não conseguiria mais nem
--     editar o nome do evento;
--   * nenhuma linha de `lib/` lê essas colunas (conferido por grep), então
--     esvaziá-las não muda uma tela.
--
-- Dropar as colunas é seguro só quando a base instalada toda estiver na
-- 1.0.53+, que já pede colunas explícitas. Fica nas pendências.
--
-- ---------------------------------------------------------------------------
-- A UNICIDADE VIAJA JUNTO, E ISSO NÃO É DETALHE
--
-- `validarConvite` acha o Top pelo hash com `maybeSingle()`. Dois Tops com
-- a mesma senha fazem a consulta FALHAR e ninguém se cadastra em nenhum dos
-- dois. O índice único mudou de tabela junto com o valor; sem isso a regra
-- voltaria a ser só um comentário.
-- ===========================================================================

create table if not exists public.top_access_codes (
  top_id    uuid primary key
            references public.tops (id) on delete cascade,
  code_hash text not null,
  set_at    timestamptz not null default now(),
  set_by    uuid references public.profiles (id) on delete set null
);

comment on table public.top_access_codes is
  'Hash (HMAC, com pepper na Edge Function) da senha de cadastro de cada '
  'Top. Vive fora de `tops` porque `tops` e legivel por toda conta '
  'aprovada e RLS e por linha, nao por coluna. RLS ligada SEM policy: '
  'so service_role alcanca.';

-- Uma senha por Top. Antes era `idx_tops_access_code_unico`, em `tops`.
create unique index if not exists idx_top_access_codes_hash
  on public.top_access_codes (code_hash);

alter table public.top_access_codes enable row level security;

-- Cinto e suspensório: a RLS sem policy já nega, e o `revoke` tira o
-- privilégio de tabela. Qualquer um dos dois sozinho bastaria; os dois
-- juntos sobrevivem a alguém criar uma policy por engano.
revoke all on public.top_access_codes from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Migra o que existe, sem inventar e sem perder
-- ---------------------------------------------------------------------------
insert into public.top_access_codes (top_id, code_hash, set_at, set_by)
select t.id, t.access_code_hash,
       coalesce(t.access_code_set_at, now()), t.access_code_set_by
  from public.tops t
 where t.access_code_hash is not null
on conflict (top_id) do nothing;

-- Esvazia a cópia legível. O UPDATE passa pelo trigger `tops_trava_senha`,
-- que deixa a conexão direta passar (ramo `v_papel is null and
-- session_user <> 'authenticator'`, em 13_trava_do_top_sem_uid_nulo.sql).
update public.tops
   set access_code_hash   = null,
       access_code_set_at = null,
       access_code_set_by = null
 where access_code_hash is not null
    or access_code_set_at is not null
    or access_code_set_by is not null;

-- O índice parcial em `tops` não indexa mais nada (a coluna é toda nula) e
-- a unicidade agora é de `top_access_codes`. Sai para não dar a impressão
-- de que ainda garante algo.
drop index if exists public.idx_tops_access_code_unico;

-- ---------------------------------------------------------------------------
-- Conferência:
--   -- nenhum hash na tabela legivel:
--   select count(*) from public.tops where access_code_hash is not null; -> 0
--   -- o hash existe, fora dela:
--   select count(*) from public.top_access_codes;                        -> 1
--   -- policy nenhuma, RLS ligada:
--   select relrowsecurity from pg_class where relname='top_access_codes'; -> t
--   select count(*) from pg_policy p join pg_class c on c.oid=p.polrelid
--    where c.relname='top_access_codes';                                 -> 0
--   -- e, pela Edge Function publicada, a senha em vigor continua valendo.
-- ---------------------------------------------------------------------------
