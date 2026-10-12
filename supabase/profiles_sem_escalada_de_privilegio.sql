-- ---------------------------------------------------------------------------
-- ESCALADA DE PRIVILEGIO EM `profiles`: qualquer conta logada virava admin
--
-- Achado por auditoria em 12/10/2026. APLICADO EM PRODUCAO no mesmo dia,
-- com autorizacao do dono.
--
-- ## O buraco
--
-- A policy `profiles_update_own` era:
--
--     using      (id = auth.uid())
--     with check ((id = auth.uid()) AND (role = my_profile_role()))
--
-- Prendia o `role` — e so o `role`. As outras duas colunas que decidem
-- permissao ficavam livres: `is_master_admin` e `approved`.
--
-- E `is_admin()` e `role = 'admin' OR is_master_admin`. Entao bastava a
-- qualquer conta logada mandar, pela API REST, com a chave anon que esta
-- DENTRO do APK:
--
--     PATCH /rest/v1/profiles?id=eq.<meu uuid>   {"is_master_admin": true}
--
-- `using` passava (e a propria linha), `with check` passava (`role` nao
-- mudou), e a partir dali a pessoa era ADMIN MASTER: lia todos os perfis,
-- escrevia nas 9 equipes, mandava alerta, via o mapa de todos, apagava
-- usuario e senderista. Por `approved = true` pulava a aprovacao e abria
-- chat geral e alarme de todo Top nao-draft.
--
-- Conferido no banco em 12/10/2026: so existia UMA conta com privilegio,
-- o admin master legitimo. Ninguem explorou.
--
-- ## Por que `with check` NAO bastou — e isto e o que importa aqui
--
-- A primeira correcao foi prender as tres colunas no `with check`, pelo
-- mesmo padrao do `role`: funcoes `stable security definer` que leem a
-- propria linha (`my_approved()`, `my_is_master_admin()`).
--
-- Contra `is_master_admin` funcionou. Contra `approved` NAO:
--
--     begin;
--       update profiles set approved = false where id = <uid>;   -- estado inicial
--       set local role authenticated;  set local request.jwt.claims = ...;
--       update profiles set approved = true  where id = <uid>;   -- deveria falhar
--     -- resultado: 1 linha gravada, approved = true
--
-- Medido, nao deduzido. Uma funcao que LE a mesma tabela que esta sendo
-- alterada, chamada de dentro do `with check` daquela alteracao, nao da
-- garantia confiavel sobre qual versao da linha ela enxerga. Nao se deve
-- apoiar controle de acesso num comportamento que varia com o plano de
-- execucao.
--
-- ## A correcao que vale: TRIGGER
--
-- `before update ... for each row` recebe OLD e NEW explicitamente. Nao
-- ha ambiguidade de snapshot, nao ha releitura da tabela, nao depende de
-- plano. As colunas de permissao voltam ao valor antigo.
--
-- Reverter em SILENCIO, e nao levantar erro, e deliberado: o app manda a
-- linha inteira ao salvar o perfil, entao recusar quebraria a edicao
-- legitima de nome e telefone por causa de campos que nem mudaram.
--
-- `auth.uid() is null` passa direto porque e `service_role` — a Edge
-- Function `acesso` precisa aprovar no autocadastro, e sem essa saida
-- ninguem entraria no Top por numero + senha. A RLS ja barra usuario
-- final sem uid.
--
-- O `with check` fica junto como segunda camada. Ele sozinho nao basta,
-- mas tambem nao atrapalha, e cobre o caso que ele de fato pega.
--
-- ## Conferido apos aplicar, em transacao revertida
--
--   conta comum tentando approved+is_master_admin+role de uma vez
--     -> approved false, is_master_admin false, role senderista  (bloqueado)
--     -> phone gravado                                            (legitimo OK)
--   service_role aprovando (autocadastro)
--     -> approved true                                            (sem regressao)
--
-- Rodar este arquivo DUAS VEZES seguidas: a segunda passa limpa.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Camada 1 — `with check`. Espelham `my_profile_role()`.
-- ---------------------------------------------------------------------------

create or replace function public.my_is_master_admin()
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$ select coalesce(is_master_admin, false) from public.profiles where id = auth.uid(); $$;

create or replace function public.my_approved()
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $$ select coalesce(approved, false) from public.profiles where id = auth.uid(); $$;

-- `create policy` nao tem `if not exists`: o drop do PROPRIO nome e o que
-- torna este arquivo rodavel duas vezes.
drop policy if exists profiles_update_own on public.profiles;

create policy profiles_update_own
on public.profiles
for update
using (id = auth.uid())
with check (
  id = auth.uid()
  and role = my_profile_role()
  and coalesce(is_master_admin, false) = my_is_master_admin()
  and coalesce(approved, false) = my_approved()
);

-- ---------------------------------------------------------------------------
-- Camada 2 — TRIGGER. E esta que de fato segura.
-- ---------------------------------------------------------------------------

create or replace function public.profiles_trava_colunas_de_permissao()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $$
begin
  -- Sem uid nao e usuario final: e `service_role` (Edge Function `acesso`,
  -- que aprova no autocadastro) ou o painel.
  if auth.uid() is null then
    return new;
  end if;

  -- Admin master decide tudo, inclusive quem e master.
  if public.is_master_admin() then
    return new;
  end if;

  -- Admin comum aprova e muda papel de outros, mas NUNCA cria outro
  -- master nem promove alguem a admin.
  if public.is_admin() then
    new.is_master_admin := old.is_master_admin;
    if new.role = 'admin'::public.user_role
       and old.role <> 'admin'::public.user_role then
      raise exception 'so o admin master promove alguem a admin'
        using errcode = '42501';
    end if;
    return new;
  end if;

  -- Todo o resto: as tres colunas voltam ao valor antigo, em silencio.
  new.role            := old.role;
  new.is_master_admin := old.is_master_admin;
  new.approved        := old.approved;
  return new;
end;
$$;

drop trigger if exists profiles_trava_permissao on public.profiles;

create trigger profiles_trava_permissao
before update on public.profiles
for each row execute function public.profiles_trava_colunas_de_permissao();

-- ---------------------------------------------------------------------------
-- Conferencia. Em 12/10/2026 o esperado e UMA linha: o admin master
-- legitimo (Edson Barroso, no 203460). Qualquer outra linha aqui e conta
-- que ganhou privilegio e precisa ser revista a mao antes do evento.
-- ---------------------------------------------------------------------------

select id, full_name, legendarios_number, role, is_master_admin, approved, created_at
  from public.profiles
 where is_master_admin = true or role = 'admin'
 order by created_at;
