-- ===========================================================================
-- `profiles.is_teste` — A OITAVA PEÇA QUE SÓ EXISTIA EM PRODUÇÃO
--
-- Achada em 23/11/2026, testando a corrente do autocadastro de ponta a
-- ponta no banco reconstruído. A coluna não aparece em NENHUM arquivo SQL
-- do repositório — conferido por busca — e a Edge Function `acesso` a
-- GRAVA ao criar a conta, em `cadastrar`:
--
--     .from('profiles').update({ ..., is_teste: r.isTeste })
--
-- O estrago é total e não é sutil: o `update` falha com
--
--     Could not find the 'is_teste' column of 'profiles' in the schema cache
--
-- e o bloco seguinte DESFAZ a conta (`deleteUser`) de propósito, para não
-- deixar perfil pela metade. Resultado: **ninguém se autocadastra.** A
-- pessoa digita número e senha certos, recebe "falha ao salvar o perfil" e
-- não há segunda tentativa que funcione. Com 216 pessoas para cadastrar e
-- o evento a 3 dias, era a diferença entre o app servir e não servir.
--
-- Não foi pego pela conferência por área do app porque a tabela existe, a
-- RLS existe e as policies existem — falta uma COLUNA. Conferir objeto por
-- objeto não vê isso; só a chamada de verdade vê.
--
-- A nona desta série. As anteriores: `top_participants`, `team_messages`,
-- `top_team_members`, `audit_log`, bucket `emblemas`, `is_approved()`,
-- `tops.autocadastro_liberado` e o índice de `atendimentos`.
--
-- ---------------------------------------------------------------------------
-- POR QUE A COLUNA EXISTE
--
-- Marca conta nascida de cadastro de TESTE. `top_participants.is_teste` já
-- existe (`00_TABELAS_QUE_FALTAVAM.sql:89`) e a ficha de teste carimba a
-- conta criada a partir dela — é o que permite apagar o teste em bloco
-- depois, sem olhar nome por nome. Antes do evento a equipe testa o
-- cadastro com números falsos, e sem a marca essas contas ficariam
-- indistinguíveis das reais na lista de 216.
--
-- `not null default false` para que toda conta existente e toda conta
-- criada por outro caminho (Google, convite do admin) nasça como REAL.
-- O lado seguro aqui é o contrário do da `autocadastro_liberado`: marcar
-- de menos deixa um teste parecendo gente, marcar de mais apagaria gente
-- junto com o teste.
-- ===========================================================================

alter table public.profiles
  add column if not exists is_teste boolean not null default false;

comment on column public.profiles.is_teste is
  'Conta nascida de cadastro de teste. Gravada por `cadastrar` na Edge '
  'Function `acesso`, a partir de `top_participants.is_teste` da ficha. '
  'Permite apagar o teste em bloco antes do evento.';

-- Conferência:
--   select count(*) filter (where is_teste) as testes,
--          count(*) filter (where not is_teste) as reais
--     from public.profiles;
