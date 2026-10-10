-- ============================================================================
-- Aplicado em producao (projeto jitfbambhmfnqiatwoud) em 09/10/2026.
--
-- Entrada no app pelo numero do Legendarios.
--
-- Fluxo: o Legendario pede acesso com o numero -> o admin ve o pedido,
-- gera um codigo e ENTREGA A PESSOA (WhatsApp, pessoalmente) -> ela entra
-- com numero + codigo e a sessao persiste ate deslogar.
--
-- Nao ha envio automatico de SMS/e-mail: decisao de 09/10/2026, por custo
-- zero e pra manter o admin no controle de quem entra - mesmo modelo do
-- `approved` dos perfis.
-- ============================================================================

create type access_request_status as enum ('pendente','liberado','negado');

create table if not exists public.access_requests (
  id                 uuid primary key default gen_random_uuid(),
  legendarios_number text not null,
  full_name          text,
  phone              text,
  status             access_request_status not null default 'pendente',
  requested_at       timestamptz not null default now(),
  handled_by         uuid references public.profiles(id),
  handled_at         timestamptz,
  -- So o HASH do codigo. Codigo legivel guardado pra sempre e senha em
  -- texto claro; se o admin perder, gera outro.
  code_hash          text,
  code_expires_at    timestamptz,
  code_used_at       timestamptz,
  notes              text
);

-- Um pedido pendente por numero: tocar "entrar" varias vezes nao pode
-- encher a fila do admin com o mesmo Legendario.
create unique index if not exists idx_access_requests_pendente
  on public.access_requests (legendarios_number) where status = 'pendente';
create index if not exists idx_access_requests_numero
  on public.access_requests (legendarios_number, requested_at desc);

alter table public.access_requests enable row level security;

-- So admin le e gerencia. Quem pede NAO consegue consultar o proprio
-- pedido pela API: isso permitiria descobrir quais numeros existem
-- testando um por um.
create policy access_requests_admin_all on public.access_requests
for all using (is_admin()) with check (is_admin());


-- ----------------------------------------------------------------------------
-- A Edge Function `acesso` (supabase/functions/acesso/index.ts) complementa
-- esta tabela.
--
-- Ela existe por um motivo de seguranca: criar usuario e definir senha
-- exigem a chave service_role, que NAO pode ir dentro do APK - quem
-- extraisse o arquivo viraria admin do projeto inteiro, lendo todos os
-- prontuarios. A chave fica no servidor; o app so chama as acoes
-- `solicitar` (publica), `liberar` e `negar` (so admin).
--
-- O numero vira `<numero>@legendarios.app` porque o Supabase Auth exige um
-- identificador em formato de e-mail. NENHUM e-mail e enviado pra esse
-- endereco; o usuario digita apenas o numero.
-- ----------------------------------------------------------------------------
