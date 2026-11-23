-- ===========================================================================
-- TRIAGEM: HAVIA DUAS CONFIGURAÇÕES ATIVAS, E A ANTIGA GANHAVA
--
-- Achado em 23/11/2026, auditando o banco reconstruído linha a linha.
-- `triage_rules` tinha **14 regras com `active = true`**, não 8: o conjunto
-- canônico (ids 35-42) **mais** o conjunto antigo (ids 43-48), que o
-- `CLAUDE.md` manda nunca reintroduzir.
--
-- O estrago é uma célula da matriz, e é a pior delas:
--
--     id 43: 41+ anos, 0..999 comorbidades -> VERMELHO, priority 1
--
-- `TriageService._corPara` ordena por `priority` crescente e devolve a
-- **primeira** regra que casa. Priority 1 é a primeira de todas. Então
-- **todo participante de 41 anos ou mais era pintado de VERMELHO**,
-- inclusive quem não tem nenhuma comorbidade — que a matriz manda ser
-- AMARELO. A regra 41 (`41+, 0 comorbidades -> amarelo`, priority 7) nunca
-- era alcançada.
--
-- É exatamente o defeito que `team_roles_and_triage_v2.sql:103-112` descreve
-- como motivo de ter criado a v2: *"acima de 40 o número de comorbidades
-- deixava de influenciar a cor... a triagem perdia a capacidade de
-- priorizar justamente na faixa com mais participantes"*. E é o que o
-- `CLAUDE.md` resume em uma linha: **"Não reintroduzir regras pega-tudo de
-- prioridade alta."**
--
-- Clinicamente é supertriagem, não subtriagem — ninguém fica menos
-- vermelho do que deveria. Mas encher a lista de vermelhos destrói a
-- discriminação onde ela mais importa, e "a cor pararia de significar
-- prioridade".
--
-- ---------------------------------------------------------------------------
-- POR QUE OS TESTES PASSAVAM
--
-- `test/services/triage_service_test.dart` valida a matriz contra o fixture
-- `_producao`, que é uma CÓPIA das 8 regras canônicas — e está correto.
-- Ele nunca olha o banco. O `CLAUDE.md` avisa do risco na direção oposta
-- ("mudou as regras no banco, atualize o fixture, senão os testes passam
-- validando uma configuração que não existe mais"); aqui foi o inverso: o
-- fixture certo, o banco errado. **575 testes verdes com a triagem errada
-- em produção.**
--
-- ---------------------------------------------------------------------------
-- A CAUSA RAIZ, E ELA ESTÁ NO REPOSITÓRIO
--
-- `schema.sql:443` e `admin_master_and_triage.sql:179` inserem o conjunto
-- ANTIGO **sem informar `active`** — e a coluna é
-- `active boolean not null default true` (`schema.sql:164`). Então:
--
--   . `team_roles_and_triage_v2.sql` faz
--     `update ... set active = false where active = true` e insere as 8
--     certas. Correto, e independente de id.
--   . Mas qualquer execução POSTERIOR de `schema.sql` ou de
--     `admin_master_and_triage.sql` insere as 6 antigas **já ativas**, e o
--     pega-tudo volta a atropelar tudo.
--
-- Foi o que aconteceu: a reconstrução de 23/11 teve uma segunda passada
-- dirigida nos arquivos que haviam falhado, e nela o `v2` não voltou a
-- rodar. Os dois arquivos foram corrigidos no mesmo commit deste arquivo —
-- passam a inserir com `active = false`, porque são **história**, não
-- configuração.
--
-- ---------------------------------------------------------------------------
-- A DESATIVAÇÃO AQUI NÃO USA ID, DE PROPÓSITO
--
-- Desativar "ids 43 a 48" seria repetir o erro que criou isto: amarrar a
-- correção a números que só existem neste banco. O `update` abaixo casa pela
-- FORMA da regra (cor, faixa de idade, faixa de comorbidades, prioridade) e
-- desativa tudo o que não é canônico — em qualquer banco, com qualquer id.
--
-- `is not distinct from` e não `=` para `max_age`: a regra de 41+ tem
-- `max_age` NULO, e `null = null` é NULO, não verdadeiro. Com `=` a regra
-- canônica de 41+ não se reconheceria e seria desativada junto.
-- ===========================================================================

with canonico (color, min_age, max_age, min_comorbidities, max_comorbidities, priority) as (
  values
    ('blue',   0,   25,   0,   0, 1),
    ('green',  0,   25,   1,   1, 2),
    ('red',    0,   25,   2, 999, 3),
    ('green', 26,   40,   0,   0, 4),
    ('yellow',26,   40,   1,   1, 5),
    ('red',   26,   40,   2, 999, 6),
    ('yellow',41, null,   0,   0, 7),
    ('red',   41, null,   1, 999, 8)
)
update public.triage_rules t
   set active = false
 where t.active
   and not exists (
     select 1 from canonico c
      where c.color = t.color::text
        and c.min_age = t.min_age
        and c.max_age is not distinct from t.max_age
        and c.min_comorbidities = t.min_comorbidities
        and c.max_comorbidities = t.max_comorbidities
        and c.priority = t.priority
   );

-- ---------------------------------------------------------------------------
-- CONFERÊNCIA — a matriz, calculada pelo MESMO critério do app
--
-- `TriageService._corPara`: ordena por `priority` crescente, devolve a
-- primeira que casa. Esta consulta faz igual, para a conferência não
-- depender de ler o Dart e acreditar.
--
-- Tem de sair exatamente:
--
--    idade |  0 comorb   1 comorb   2+ comorb
--    ------+---------------------------------
--     0-25 |     blue      green          red
--    26-40 |    green     yellow          red
--      41+ |   yellow        red          red
-- ---------------------------------------------------------------------------
--   with casos as (select * from (values (18),(30),(50)) i(idade),
--                                 (values (0),(1),(2)) c(comorb))
--   select idade, comorb,
--          (select r.color from public.triage_rules r
--            where r.active
--              and casos.idade >= r.min_age
--              and (r.max_age is null or casos.idade <= r.max_age)
--              and casos.comorb >= r.min_comorbidities
--              and casos.comorb <= r.max_comorbidities
--            order by r.priority limit 1) as cor
--     from casos order by idade, comorb;
--
--   select count(*) from public.triage_rules where active;   -> 8
