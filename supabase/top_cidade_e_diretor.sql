-- ============================================================================
-- v1.0.27 — Cidade e diretor responsavel no Top
--
-- O cadastro do Top ja tinha numero, nome, local, descricao, status, datas
-- de inicio e fim, e o emblema da pista. Faltavam dois campos pedidos pelo
-- usuario.
-- ============================================================================

alter table public.tops
  add column if not exists cidade               text,
  add column if not exists diretor_responsavel  text;

comment on column public.tops.cidade is
  'Cidade do evento. Separada de `location`, que e a pista/local.';

comment on column public.tops.diretor_responsavel is
  'Nome do diretor responsavel pelo Top. Campo INFORMATIVO: quem manda no
   app e definido por `profiles.role` e por `top_hakunas`, nao por este
   texto. Escrever um nome aqui nao da permissao nenhuma a ninguem.';

-- ----------------------------------------------------------------------------
-- Correcao de dado no Top 1782
--
-- `location` estava com "Franca", que e a CIDADE e nao o nome da pista.
-- O valor foi copiado para `cidade`; `location` fica como esta ate alguem
-- que saiba o nome da pista corrigir pela tela.
-- ----------------------------------------------------------------------------
-- update public.tops set cidade = 'Franca' where top_number = '1782';
