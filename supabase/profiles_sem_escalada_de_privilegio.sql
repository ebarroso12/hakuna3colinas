-- ---------------------------------------------------------------------------
-- ESCALADA DE PRIVILEGIO EM `profiles`: qualquer pessoa logada vira admin
--
-- Achado por auditoria em 12/10/2026. NAO APLICADO AINDA — exige
-- autorizacao do dono, porque mexe em controle de acesso de producao.
--
-- ## O buraco
--
-- A policy `profiles_update_own` e hoje:
--
--     using      (id = auth.uid())
--     with check ((id = auth.uid()) AND (role = my_profile_role()))
--
-- Ela prende o `role` — e **so** o `role`. As outras duas colunas que
-- decidem permissao ficam livres:
--
--   * `is_master_admin`  (boolean)
--   * `approved`         (boolean)
--
-- E `is_admin()` e:
--
--     select exists (select 1 from profiles
--                    where id = auth.uid()
--                      and (role = 'admin' or is_master_admin));
--
-- Entao basta a qualquer conta logada mandar, pela API REST do Supabase,
-- com a propria chave anon que esta DENTRO do APK:
--
--     PATCH /rest/v1/profiles?id=eq.<meu uuid>
--     { "is_master_admin": true }
--
-- `using` passa (e a propria linha). `with check` passa (`id` bate,
-- `role` nao mudou). A coluna e gravada. A partir do commit a pessoa e
-- **admin master**: le todos os perfis, le e escreve nas 9 equipes, manda
-- mensagem como alerta, ve o mapa de todo mundo, apaga usuario e
-- senderista.
--
-- O mesmo vale para `approved = true`, que pula a aprovacao do admin e
-- libera chat geral e alarme de todo Top nao-draft (`is_approved()`).
--
-- ## Por que isso passou
--
-- A assimetria denuncia o descuido: a policy de ADMIN ja se protege,
--
--     with check (((role <> 'admin') OR is_master_admin())
--                 AND ((is_master_admin = false) OR is_master_admin()))
--
-- ou seja, nem um admin comum se promove a master. Quem escreveu pensou
-- na escalada pelo caminho do admin e nao pelo caminho de quem edita o
-- proprio perfil — que e o caminho que TODO usuario tem.
--
-- ## A correcao
--
-- Prender as tres colunas ao valor atual, pelo mesmo padrao que o `role`
-- ja usa: funcao `stable security definer`, que le `profiles` sem
-- reentrar na RLS. Subconsulta direta a `profiles` dentro de uma policy
-- de `profiles` recursa — e por isso que `my_profile_role()` existe.
--
-- O usuario continua editando o que e dele de direito: nome, telefone,
-- peso, data de nascimento, comorbidades, registro medico.
--
-- ## Conferencia depois de aplicar
--
-- Logado como conta comum, isto tem de ser RECUSADO:
--
--     update public.profiles set is_master_admin = true where id = auth.uid();
--     update public.profiles set approved = true where id = auth.uid();
--
-- e isto tem de continuar FUNCIONANDO:
--
--     update public.profiles set phone = '31999990000' where id = auth.uid();
--
-- Rodar este arquivo DUAS VEZES seguidas: a segunda tem de passar limpa.
-- ---------------------------------------------------------------------------

-- Espelham `my_profile_role()`: leem a propria linha sem reentrar na RLS.
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
  -- As tres colunas que decidem permissao ficam presas ao valor atual.
  -- `role` ja estava; as outras duas sao a correcao.
  and role             =  my_profile_role()
  and coalesce(is_master_admin, false) = my_is_master_admin()
  and coalesce(approved, false)        = my_approved()
);

-- Conferencia: quem ja se promoveu? Em 12/10/2026 o resultado esperado e
-- UMA linha, o admin master legitimo (Edson Barroso, nº 203460). Qualquer
-- outra linha aqui e conta que explorou o buraco e precisa ser revista a
-- mao antes de o evento comecar.
select id, full_name, legendarios_number, role, is_master_admin, approved, created_at
  from public.profiles
 where is_master_admin = true or role = 'admin'
 order by created_at;
