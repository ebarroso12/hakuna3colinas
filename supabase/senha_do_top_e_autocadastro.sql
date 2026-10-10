-- ============================================================================
-- v1.0.24 — Senha do Top e autocadastro do Legendário
--
-- FLUXO
--   1. O admin gera UMA senha para o Top e anuncia no grupo.
--   2. O Legendário digita numero + senha do Top.
--   3. O sistema confere que o número está na lista daquele Top.
--   4. Ele preenche a ficha médica e CRIA A SENHA DELE.
--   5. Daí em diante entra com numero + senha pessoal.
--
-- A senha do Top é CONVITE, não senha de entrada. A diferença não é
-- cosmética: se ela servisse para entrar, o Legendário 203460 digitaria o
-- número 441892 com a mesma senha e abriria o prontuário do outro. Todo
-- mundo teria a senha de todo mundo.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. A senha do Top
--
-- Guardada como SHA-256, nunca em claro — mesma regra de `access_requests
-- .code_hash`. Quem tiver acesso de leitura ao banco não consegue entrar
-- com ela, e nem o admin a recupera depois: se perder, gera outra.
-- ----------------------------------------------------------------------------

alter table public.tops
  add column if not exists access_code_hash   text,
  add column if not exists access_code_set_at timestamptz,
  add column if not exists access_code_set_by uuid references public.profiles(id);

comment on column public.tops.access_code_hash is
  'SHA-256 da senha de convite do Top. Libera o CADASTRO, nunca o login.';

-- ----------------------------------------------------------------------------
-- 2. Quem pode se cadastrar
--
-- A senha sozinha não basta. O número digitado precisa estar na lista de
-- participantes DAQUELE Top — senão quem recebesse a senha no grupo poderia
-- se cadastrar com o número de outra pessoa e tomar o lugar dela.
--
-- Hoje o Top 1782 tem 215 participantes, 71 com número (os Legendários) e
-- 144 sem (os Senderistas). Só os 71 conseguem conta.
--
-- SECURITY DEFINER porque roda ANTES de existir sessão: quem chama ainda
-- não é ninguém no sistema. Por isso ela devolve o mínimo possível e nunca
-- dado clínico — ver o SELECT abaixo.
-- ----------------------------------------------------------------------------

create or replace function public.participante_elegivel(
  p_top_id uuid,
  p_numero text
)
returns table (
  participante_id uuid,
  nome            text,
  familia         text,
  ja_tem_conta    boolean
)
language sql
security definer
set search_path = public
stable
as $$
  select
    tp.id,
    tp.full_name,
    tp.familia,
    tp.linked_profile_id is not null
  from public.top_participants tp
  where tp.top_id = p_top_id
    and tp.participant_code = p_numero
    and tp.active = true
  limit 1;
$$;

-- Só a Edge Function (service_role) chama isto. Deixar aberta ao `anon`
-- permitiria descobrir quem está inscrito num Top testando números.
--
-- ARMADILHA, confirmada medindo com has_function_privilege: revogar de
-- PUBLIC **não basta**. O Supabase configura
--   alter default privileges in schema public
--     grant execute on functions to anon, authenticated, service_role;
-- ou seja, toda função nova nasce com EXECUTE concedido DIRETAMENTE a
-- `anon` e `authenticated` — e grant direto não se remove revogando de
-- PUBLIC. Depois do primeiro revoke, `anon` continuava podendo chamar.
--
-- Os três revokes são necessários. E sempre conferir depois:
--   select has_function_privilege('anon', 'public.participante_elegivel(uuid,text)', 'EXECUTE');
revoke execute on function public.participante_elegivel(uuid, text) from public;
revoke execute on function public.participante_elegivel(uuid, text) from anon;
revoke execute on function public.participante_elegivel(uuid, text) from authenticated;
grant  execute on function public.participante_elegivel(uuid, text) to service_role;

-- ----------------------------------------------------------------------------
-- 3. Vincular conta à ficha
--
-- Os 71 Legendários JÁ existem como participantes (hoje com
-- linked_profile_id vazio nos 215). O cadastro não cria ficha nova: ele
-- liga a conta à ficha que já está lá. Assim nome e família já vêm
-- preenchidos e não nasce participante duplicado.
-- ----------------------------------------------------------------------------

create unique index if not exists idx_participants_profile_unico
  on public.top_participants (top_id, linked_profile_id)
  where linked_profile_id is not null;

-- ----------------------------------------------------------------------------
-- 4. Índice para a conferência do número
--
-- `participante_elegivel` consulta por (top_id, participant_code) a cada
-- tentativa de cadastro. Sem índice, varre os 215 — e varreria 2.000 num
-- evento maior.
-- ----------------------------------------------------------------------------

create index if not exists idx_participants_codigo
  on public.top_participants (top_id, participant_code)
  where participant_code is not null;

-- ----------------------------------------------------------------------------
-- 5. Verificação
-- ----------------------------------------------------------------------------
-- select top_number, access_code_hash is not null as tem_senha, access_code_set_at
--   from public.tops;
--
-- select count(*) filter (where participant_code is not null) as legendarios,
--        count(*) filter (where participant_code is null)     as senderistas
--   from public.top_participants where top_id = '...';
