-- ===========================================================================
-- `atendimento_status` — SEIS DOS NOVE ESTADOS SÓ EXISTIAM EM PRODUÇÃO
--
-- Achado em 23/11/2026, chamando o **Painel do Top** como admin no banco
-- reconstruído. Ele não devolve número nenhum; devolve erro:
--
--     22P02: invalid input value for enum atendimento_status: "cancelado"
--
-- `atendimentos.sql:10` cria o enum com TRÊS valores:
--
--     create type public.atendimento_status as enum
--       ('aberto', 'em_andamento', 'encerrado');
--
-- e `painel_do_top.sql:81` filtra por `status not in ('encerrado',
-- 'cancelado')`. Os outros seis foram adicionados à mão em produção e
-- ficaram registrados apenas como COMENTÁRIO, em
-- `revisao_completa_correcoes.sql:161-166`. Comentário não roda — é a
-- mesma armadilha que o `CLAUDE.md` já registra para o `team_key`, onde a
-- equipe `hakunas` desapareceria de um schema reconstruído.
--
-- O estrago é o Painel do Top inteiro: a função é `security definer` e
-- morre na primeira contagem, então o admin não vê nem participantes, nem
-- atendimentos, nem aferições. Não é uma contagem errada — é a tela toda.
--
-- ---------------------------------------------------------------------------
-- POR QUE OS SEIS ENTRAM AGORA, SE O APP NÃO OS USA
--
-- O app escreve só `aberto` e `encerrado`, e o `CLAUDE.md` registra que os
-- outros sete seguem sem uso **por decisão** — fluxo de despacho exige
-- painel de coordenação. Isso continua valendo: este arquivo não
-- implementa despacho nenhum.
--
-- Mas o enum precisa dos valores porque CONSULTA os menciona. Um enum é
-- fechado: comparar com um rótulo que não existe não devolve `false`,
-- levanta 22P02 e derruba a consulta inteira. Ou o enum tem os nove, ou o
-- `painel_do_top` tem de ser reescrito — e reescrevê-lo seria mudar a
-- consulta para caber no esquema errado, que é o inverso do conserto.
--
-- A ordem segue o fluxo real do despacho, não a alfabética: é a ordem em
-- que `enumsortorder` vai aparecer em qualquer `order by status`.
--
-- ---------------------------------------------------------------------------
-- `add value if not exists` É OBRIGATÓRIO E NÃO RODA EM TRANSAÇÃO COM USO
--
-- `alter type ... add value` aceita `if not exists`, e é o que faz este
-- arquivo rodar duas vezes sem erro. O que NÃO se pode fazer é usar o
-- valor novo na mesma transação em que ele foi criado — daí este arquivo
-- não ter nenhum `insert`, `where` ou `check` que mencione os valores.
-- ===========================================================================

alter type public.atendimento_status add value if not exists 'reconhecido'  after 'aberto';
alter type public.atendimento_status add value if not exists 'atribuido'    after 'reconhecido';
alter type public.atendimento_status add value if not exists 'a_caminho'    after 'atribuido';
alter type public.atendimento_status add value if not exists 'no_local'     after 'a_caminho';
alter type public.atendimento_status add value if not exists 'escalado'     after 'em_andamento';
alter type public.atendimento_status add value if not exists 'cancelado';

-- Conferência (tem de listar os NOVE):
--   select string_agg(e.enumlabel, ', ' order by e.enumsortorder)
--     from pg_type t join pg_enum e on e.enumtypid = t.oid
--    where t.typname = 'atendimento_status';
