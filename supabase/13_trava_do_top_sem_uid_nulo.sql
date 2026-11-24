-- ===========================================================================
-- A TRAVA DO TOP NAO PODE SE APOIAR EM `auth.uid() is null`
--
-- Achado na revisao de 24/11/2026. `07_senha_do_top_so_o_master.sql` e
-- `11_autocadastro_sem_lista.sql` abriam a porta assim:
--
--     if auth.uid() is null then return new; end if;   -- "e o service_role"
--
-- O comentario estava errado, e o proprio CLAUDE.md registra a regra, escrita
-- no mesmo dia em que o furo foi introduzido: **uid nulo e `service_role` OU
-- A CHAVE ANON** -- e a chave anon esta dentro do APK, nas maos de qualquer
-- pessoa que baixe o arquivo. "Passar quando for nulo" nunca foi seguro.
-- `06_atendimentos_participant_id_e_exclusao.sql` ja usava o padrao certo; o
-- 07 e o 11 ficaram com a versao fraca.
--
-- ---------------------------------------------------------------------------
-- NAO ERA EXPLORAVEL HOJE -- E ISSO PRECISA SER DITO SEM MAQUIAGEM
--
-- Medido em 24/11/2026: `is_admin()` usa `exists (...)`, que devolve FALSE
-- (nunca NULL) para quem nao tem perfil, e a policy `tops_admin_update` e
-- `is_admin()`. Ou seja, a RLS barrava o anonimo ANTES de o trigger
-- disparar. O que estava quebrado era a defesa em profundidade: a segunda
-- tranca nao existia. Virava furo de verdade no dia em que alguem criasse
-- uma policy de UPDATE mais larga em `tops`, ou uma funcao `security
-- definer` que escrevesse nela -- e nada avisaria.
--
-- ---------------------------------------------------------------------------
-- QUEM PASSA, E POR QUE -- CADA RAMO FOI MEDIDO, NAO DEDUZIDO
--
--   | quem chama                     | claims role     | session_user    |
--   |--------------------------------|-----------------|-----------------|
--   | Edge Function (service_role)   | service_role    | authenticator   |
--   | chave ANON (dentro do APK)     | anon            | authenticator   |
--   | usuario logado                 | authenticated   | authenticator   |
--   | psql / Management API / migra. | <sem claims>    | postgres        |
--
-- Medido chamando uma sonda `session_user`/`current_setting` pelos dois
-- caminhos. Daí as duas condicoes de passagem:
--
--   1. `claims role = 'service_role'` -- a Edge Function `acesso`, que JA
--      conferiu `is_master_admin` antes de escrever. As duas andam juntas:
--      mexer numa sem a outra abre a porta.
--
--   2. `sem claims` E `session_user <> 'authenticator'` -- conexao direta ao
--      banco (migracao, correcao de dados, psql do dono). Sem este ramo, a
--      propria migracao que conserta dados teria a escrita revertida em
--      silencio. `session_user` e o discriminador certo porque NAO e afetado
--      por `security definer`: `current_user` vira o dono da funcao aqui
--      dentro e nao serve para distinguir nada (CLAUDE.md, 12/10/2026).
--
-- A chave anon cai fora dos dois: `role = 'anon'` nao e `service_role`, e nao
-- e "sem claims". Era exatamente o caso que passava antes.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. A trava, definitiva. Esta e a UNICA definicao valida da funcao.
-- ---------------------------------------------------------------------------
create or replace function public.tops_trava_senha_do_top()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_papel text := nullif(current_setting('request.jwt.claims', true), '')::json
                    ->> 'role';
begin
  -- Ramo 1: a Edge Function `acesso`, que ja conferiu o admin master.
  -- Ramo 2: conexao direta ao banco (migracao, psql). Ver a tabela no
  -- cabecalho: os dois foram medidos, e a chave anon nao entra em nenhum.
  if v_papel = 'service_role'
     or (v_papel is null and session_user <> 'authenticator') then
    return new;
  end if;

  -- "os admin master terao todo acesso".
  if public.is_master_admin() then
    return new;
  end if;

  -- Admin comum (e qualquer outro) nao mexe na senha. EM SILENCIO, de
  -- proposito: um `update` de rotina do Top pode mandar a linha inteira, e
  -- recusar quebraria a edicao de nome, local e datas por causa de um campo
  -- que nem mudou.
  new.access_code_hash   := old.access_code_hash;
  new.access_code_set_at := old.access_code_set_at;
  new.access_code_set_by := old.access_code_set_by;

  -- FECHAR o cadastro: qualquer admin. ABRIR: so o master, e com ERRO.
  -- A assimetria e deliberada -- fechar e sempre o lado seguro; abrir e dar
  -- acesso ao Top. E aqui o erro e levantado (ao contrario das colunas de
  -- senha) porque `definirAutocadastro` manda SO esta coluna: o erro nunca
  -- atropela outra edicao, e reverter calado faria o interruptor voltar
  -- sozinho na tela, que parece defeito do app.
  if coalesce(new.autocadastro_liberado, false)
     and not coalesce(old.autocadastro_liberado, false) then
    raise exception
      'so o admin master abre o cadastro de um Top'
      using errcode = '42501';
  end if;

  -- LIGAR "aceitar fora da lista" afrouxa quem entra no Top: so o master.
  -- DESLIGAR pode, pela mesma razao de fechar o cadastro -- e o lado seguro.
  if coalesce(new.aceitar_fora_da_lista, false)
     and not coalesce(old.aceitar_fora_da_lista, false) then
    raise exception
      'so o admin master aceita cadastro fora da lista do Top'
      using errcode = '42501';
  end if;

  return new;
end;
$fn$;

drop trigger if exists tops_trava_senha on public.tops;

create trigger tops_trava_senha
  before update on public.tops
  for each row execute function public.tops_trava_senha_do_top();

-- ---------------------------------------------------------------------------
-- 2. `is_approved()` devolvia NULL quando nao havia perfil
--
-- Era `select coalesce(approved, false) from profiles where id = auth.uid()`.
-- O `coalesce` cobre a COLUNA nula; nao cobre a LINHA ausente -- subconsulta
-- sem linha e NULL. Hoje e inofensivo porque toda policy usa a funcao dentro
-- de um `AND`, e NULL nega. Vira armadilha no primeiro `not is_approved()`:
-- `not null` e null, que nega tambem, e a policy faria o oposto do que o
-- nome diz, sem erro em lugar nenhum.
-- ---------------------------------------------------------------------------
create or replace function public.is_approved()
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $fn$
  select coalesce(
    (select p.approved from public.profiles p where p.id = auth.uid()),
    false
  );
$fn$;

-- ---------------------------------------------------------------------------
-- Conferencia (rodar duas vezes seguidas, as duas sem erro):
--   select count(*) from pg_trigger where tgname = 'tops_trava_senha';  -> 1
--   select public.is_approved();                                        -> f
--   -- com a chave ANON, por PATCH em /rest/v1/tops: hash NAO muda
--   -- como admin COMUM: abrir cadastro -> 42501; fechar -> 200
-- ---------------------------------------------------------------------------
