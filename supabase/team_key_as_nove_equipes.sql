-- ============================================================================
-- 11/10/2026 — AS 9 EQUIPES EXISTEM EM PRODUÇÃO E NÃO EXISTEM NO REPOSITÓRIO
-- ============================================================================
--
-- O dono do projeto abriu o app e não achou as 9 equipes. A correção da
-- TELA está em `lib/screens/team_chats_screen.dart` (ela listava só as
-- equipes em que a pessoa já era membro liberado, e `top_team_members`
-- nasce vazia, então todo mundo via zero). Este arquivo trata do outro
-- lado do mesmo problema.
--
-- O ACHADO: nada no repositório cria o enum `team_key`.
--
--   $ grep -rn "create type.*team_key" supabase/     ->  nada
--
-- O valor `hakunas` — a 9ª equipe, a de salvamento — entrou em produção
-- por dois comandos rodados à mão, e eles estão registrados apenas como
-- COMENTÁRIO em `supabase/equipes_alarme_mapa_e_blocos.sql:17-18`:
--
--     alter type public.team_key add value 'saude';           -- erro meu
--     alter type public.team_key rename value 'saude' to 'hakunas';
--
-- Comentário não roda. Num schema reconstruído a partir deste
-- repositório, `team_key` sai com 8 equipes + `geral` e a equipe de
-- salvamento desaparece de novo — sem chat, sem bloco de anotações, e
-- sem nada falhando alto o suficiente para alguém notar. É o mesmo
-- padrão de `top_imagens`, que ficou só em produção por um dia.
--
-- ESTE ARQUIVO É IDEMPOTENTE: rodar de novo num banco que já está certo
-- não faz nada. Pode ser rodado em produção para conferir.
--
-- O QUE ELE NÃO FAZ, E É PROPOSITAL
--
-- Não recria `top_team_members` nem `team_messages`. As duas também estão
-- fora do repositório (`grep -rn "create table.*top_team_members"` não
-- acha nada), mas eu não tenho acesso de leitura ao banco nesta sessão
-- para conferir colunas, defaults, constraints e policies. Escrever um
-- `create table` de memória produziria um arquivo que PARECE a fonte da
-- verdade e divergiria da produção em silêncio — pior que a ausência,
-- porque a ausência pelo menos não mente.
--
-- PENDÊNCIA, para quem tiver as credenciais: extrair o DDL real das duas
-- tabelas (`pg_dump --schema-only -t public.top_team_members
-- -t public.team_messages`) e versionar aqui.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. O enum, com as 9 equipes + o canal `geral`
-- ----------------------------------------------------------------------------
--
-- `geral` NÃO é equipe — é o canal que todo participante aprovado do Top
-- enxerga. Daí `TeamKeyUi.equipes` devolver 9 e não 10
-- (`lib/models/team.dart`, travado por `test/models/team_test.dart`).
--
-- A ordem é a da produção: as 8 originais, `hakunas` (acrescentada depois,
-- então no fim) e `geral`. Enum em Postgres ordena pela posição de
-- declaração, e `ADD VALUE` sem `BEFORE`/`AFTER` acrescenta no fim — é
-- como `hakunas` entrou lá. Mantendo igual aqui, `order by team` dá o
-- mesmo resultado nos dois lugares.
do $$
begin
  if not exists (
    select 1 from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'team_key' and n.nspname = 'public'
  ) then
    create type public.team_key as enum (
      'adm',
      'logistica',
      'voz',
      'intercessao',
      'producao',
      'midia',
      'eventos',
      'seguranca',
      'hakunas',
      'geral'
    );
  end if;
end
$$;


-- ----------------------------------------------------------------------------
-- 2. Os valores que faltarem, um a um
-- ----------------------------------------------------------------------------
--
-- Caso o tipo já exista com menos valores — que é exatamente o estado de
-- um banco criado a partir deste repositório antes de 11/10/2026.
--
-- `add value if not exists` é de PG 12+; o Supabase está muito à frente
-- disso. Cada `alter type` vai sozinho de propósito: em Postgres o valor
-- novo não pode ser USADO na mesma transação em que foi criado, e juntar
-- tudo num bloco com os `insert`/`update` de outro arquivo dá o erro
-- "unsafe use of new value of enum type", que não é óbvio de ler.
alter type public.team_key add value if not exists 'adm';
alter type public.team_key add value if not exists 'logistica';
alter type public.team_key add value if not exists 'voz';
alter type public.team_key add value if not exists 'intercessao';
alter type public.team_key add value if not exists 'producao';
alter type public.team_key add value if not exists 'midia';
alter type public.team_key add value if not exists 'eventos';
alter type public.team_key add value if not exists 'seguranca';
-- A que faltava. É esta a linha que este arquivo existe para garantir.
alter type public.team_key add value if not exists 'hakunas';
alter type public.team_key add value if not exists 'geral';


-- ----------------------------------------------------------------------------
-- 3. CONFERÊNCIA — tem de devolver 10, e tem de conter 'hakunas'
-- ----------------------------------------------------------------------------
--
-- Rode isto depois. Guarda que não é verificada é pior que guarda nenhuma:
-- ela dá a impressão de cobertura.
--
--   select count(*) as valores, bool_or(e.enumlabel = 'hakunas') as tem_hakunas
--   from pg_enum e
--   join pg_type t on t.oid = e.enumtypid
--   join pg_namespace n on n.oid = t.typnamespace
--   where t.typname = 'team_key' and n.nspname = 'public';
--
--   -- esperado:  valores = 10   tem_hakunas = true
--
-- E para ver se sobrou lixo do erro de nomenclatura (o valor `saude`, que
-- foi RENOMEADO e não deve existir — valor órfão num enum reaparece em
-- todo dropdown e em toda migração futura):
--
--   select e.enumlabel, e.enumsortorder
--   from pg_enum e
--   join pg_type t on t.oid = e.enumtypid
--   where t.typname = 'team_key'
--   order by e.enumsortorder;
--
--   -- 'saude' NÃO pode aparecer. Se aparecer, o rename não foi aplicado
--   -- e há duas equipes de salvamento no banco.
-- ----------------------------------------------------------------------------
