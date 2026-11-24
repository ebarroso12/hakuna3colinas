-- ===========================================================================
-- A SENHA DO TOP É DO ADMIN MASTER. E UMA POR TOP, GARANTIDO PELO BANCO.
--
-- Decisão do dono em 23/11/2026, nestas palavras: *"esta senha deve ser
-- gerada dentro do app somente pelos master... o master irá colocar o
-- número do top, local, nome da pista, e diretor, aí terá o botão gerar
-- senha, neste momento o admin tem a senha para distribuir entre os
-- usuários do top... os admin master terão todo acesso"*.
--
-- Até aqui **qualquer admin** gerava a senha: a Edge Function `acesso`
-- liberava em `ehAdmin = is_master_admin || role === 'admin'`, e a tela do
-- Top mostrava o botão para os dois. Quem distribui continua sendo
-- qualquer admin — distribuir é falar, não é permissão. Quem **gera** passa
-- a ser só o master.
--
-- ---------------------------------------------------------------------------
-- POR QUE ISTO MORA NO BANCO, E NÃO SÓ NA TELA
--
-- A tela esconder o botão não é controle de acesso: a chave anônima está
-- dentro do APK e um `PATCH` na API REST alcança `tops` direto. A policy
-- `tops_admin_update` é `is_admin()` — ou seja, admin comum escreve na
-- tabela inteira, inclusive em `access_code_hash`.
--
-- E **`with check` não serve aqui**, pela mesma razão medida em 12/10/2026
-- com `profiles.approved`: função que lê a mesma tabela que está sendo
-- alterada, chamada de dentro do `with check` daquela alteração, não dá
-- garantia confiável sobre qual versão da linha enxerga. O que vale é
-- TRIGGER `before update ... for each row`, que recebe `OLD` e `NEW`
-- explicitamente.
--
-- ---------------------------------------------------------------------------
-- AS TRÊS DECISÕES DO CORPO DO TRIGGER
--
-- 1. **`auth.uid() is null` passa direto.** É `service_role`: é por ali que
--    a Edge Function `acesso` grava a senha, DEPOIS de já ter conferido que
--    quem pediu é admin master. Sem essa saída, a trava quebraria o único
--    caminho legítimo de gerar senha. Mesma estrutura da trava de
--    `profiles`.
--
-- 2. **As colunas de senha voltam ao valor antigo EM SILÊNCIO**, para admin
--    comum. Não levantam erro porque um `update` de rotina do Top pode
--    mandar a linha inteira um dia, e recusar quebraria a edição de nome,
--    local e datas por causa de um campo que nem mudou. Hoje
--    `AdminService` não manda essas colunas — conferido —, então na prática
--    isto é defesa, não caminho.
--
-- 3. **Fechar o cadastro: qualquer admin. ABRIR: só o master, e com ERRO.**
--    Fechar é sempre o lado seguro — se der engano, alguém reclama e
--    resolve em um toque. Abrir é dar acesso, e é o que a decisão do dono
--    põe na mão do master.
--
--    Aqui o erro é LEVANTADO, ao contrário do item 2, e a diferença é
--    importante: `definirAutocadastro` manda SÓ essa coluna, então um erro
--    aqui nunca atropela outra edição; e reverter em silêncio faria o
--    interruptor voltar sozinho, que parece defeito do app. Um `update`
--    normal do Top não dispara nada, porque não manda a coluna e `NEW`
--    recebe o valor de `OLD`.
--
-- ---------------------------------------------------------------------------
-- UMA SENHA POR TOP, E AGORA O BANCO EXIGE
--
-- O `CLAUDE.md` registra a armadilha: `validarConvite` acha o Top pelo hash
-- da senha com `maybeSingle()`, então **dois Tops com a mesma senha fazem a
-- consulta falhar e ninguém se cadastra em nenhum dos dois.** Era regra
-- escrita e só isso. O índice único abaixo torna a regra impossível de
-- violar — se um dia um sorteio repetir, quem falha é o `insert` do admin,
-- na hora, e não 216 pessoas no dia do evento.
--
-- O índice de `top_number` fecha o outro lado: o pedido de acesso pede o
-- **número do Top** digitado, e dois Tops com o mesmo número deixariam o
-- admin sem saber de qual evento a pessoa está falando.
--
-- Os dois são **parciais** (`where ... is not null`): em Postgres NULL não
-- conflita com NULL, mas o índice parcial deixa a intenção explícita e não
-- indexa linha que não tem o valor — vários Tops em rascunho, sem número e
-- sem senha, convivem.
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- 1. Só o admin master gera a senha e abre o cadastro
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- ATENCAO: ESTE ARQUIVO TEM A VERSAO ANTIGA DA TRAVA. NAO RODE SOZINHO.
--
-- A definicao valida de `tops_trava_senha_do_top()` esta em
-- `13_trava_do_top_sem_uid_nulo.sql`. Esta aqui abre a porta com
-- `auth.uid() is null`, que tambem e verdade para A CHAVE ANON -- a que
-- esta dentro do APK (revisao de 24/11/2026).
--
-- A guarda abaixo existe porque este e exatamente o modo de falha que
-- custou caro em 23/11/2026: `schema.sql` reexecutado RESSUSCITOU a regra
-- pega-tudo da triagem e repintou de vermelho todo mundo acima de 40 anos,
-- sem erro em lugar nenhum. Reexecutar este arquivo rebaixaria a trava do
-- mesmo jeito, calado. Entao ele FALHA ALTO em vez de rebaixar.
-- ---------------------------------------------------------------------------
do $guarda$
begin
  if exists (
    select 1
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'public'
       and p.proname = 'tops_trava_senha_do_top'
       and pg_get_functiondef(p.oid) like '%request.jwt.claims%'
  ) then
    raise exception
      'Trava do Top JA esta na versao nova (13_trava_do_top_sem_uid_nulo.sql). '
      'Rodar este arquivo a rebaixaria para a versao com `auth.uid() is null`, '
      'que a chave anon satisfaz. Rode o 13.'
      using errcode = '42501';
  end if;
end
$guarda$;

create or replace function public.tops_trava_senha_do_top()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $fn$
begin
  -- `service_role`: a Edge Function `acesso`, que ja conferiu o master.
  if auth.uid() is null then
    return new;
  end if;

  -- "os admin master terao todo acesso".
  if public.is_master_admin() then
    return new;
  end if;

  -- Admin comum (e qualquer outro) nao mexe na senha. Em silencio: ver a
  -- decisao 2 no cabecalho.
  new.access_code_hash   := old.access_code_hash;
  new.access_code_set_at := old.access_code_set_at;
  new.access_code_set_by := old.access_code_set_by;

  -- Fechar pode. Abrir, nao — e com erro, nao calado.
  if coalesce(new.autocadastro_liberado, false)
     and not coalesce(old.autocadastro_liberado, false) then
    raise exception
      'so o admin master abre o cadastro de um Top'
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
-- 2. Uma senha por Top, e um número por Top
-- ---------------------------------------------------------------------------
create unique index if not exists idx_tops_access_code_unico
  on public.tops (access_code_hash)
  where access_code_hash is not null;

create unique index if not exists idx_tops_numero_unico
  on public.tops (top_number)
  where top_number is not null;

-- Conferência:
--   -- como admin COMUM, deve dar 42501:
--   update public.tops set autocadastro_liberado = true where id = '...';
--   -- como admin MASTER, deve funcionar.
--   select count(*) from pg_trigger where tgname = 'tops_trava_senha';  -> 1
