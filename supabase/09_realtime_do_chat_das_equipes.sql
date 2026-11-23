-- ===========================================================================
-- `team_messages` NÃO ESTAVA NO REALTIME — O CHAT DAS EQUIPES NÃO RECEBIA
--
-- Achado em 23/11/2026, auditando o banco reconstruído. O app abre um
-- stream nessa tabela (`SupabaseService`, `from('team_messages')
-- .stream(primaryKey: ['id'])`), e a publicação `supabase_realtime` tinha
-- só cinco tabelas:
--
--     atendimentos, hakuna_positions, top_alerts,
--     top_hakuna_messages, vital_signs
--
-- O que o app assina, e o que estava publicado:
--
--   hakuna_positions ....... publicado    OK
--   top_hakuna_messages .... publicado    OK   (chat clínico)
--   top_alerts ............. publicado    OK   (alarme)
--   vital_signs ............ publicado    OK
--   team_messages .......... **FALTANDO**      (chat das 9 equipes + geral)
--
-- O efeito é cruel porque não parece defeito: o `.stream()` faz uma leitura
-- inicial, então as mensagens que já existem APARECEM. O que nunca chega é
-- mensagem **nova** de outra pessoa. Dois celulares lado a lado conversam e
-- nenhum vê o outro até fechar e reabrir a tela. Num evento de coordenação,
-- é o chat morto sem nenhum erro em tela.
--
-- Mesma família de todos os defeitos de hoje: `team_messages` nunca esteve
-- no repositório (o `CLAUDE.md` registra isso), então nenhum arquivo a
-- adicionava à publicação — enquanto as cinco de cima são adicionadas em
-- `schema.sql:428-431`, `atendimentos.sql:70` e
-- `admin_master_and_triage.sql:135`. A tabela foi reconstruída em
-- `00_TABELAS_QUE_FALTAVAM.sql` com colunas e policies, e o Realtime
-- passou batido: é configuração do servidor, não parte do `create table`.
--
-- ---------------------------------------------------------------------------
-- POR QUE UM BLOCO `do` E NÃO UM `alter publication` SECO
--
-- `alter publication ... add table` **não tem** `if not exists`: na segunda
-- execução ele falha com 42710 ("relation is already member of
-- publication"). A convenção do projeto exige que todo arquivo rode duas
-- vezes sem erro — e aqui isso não é zelo: num script que roda inteiro, o
-- erro aborta a transação e reverte o que vier depois. Foi assim que a
-- coluna `sender_name` do alarme se perdeu em 11/10/2026.
--
-- ---------------------------------------------------------------------------
-- O QUE ISTO NÃO RESOLVE
--
-- Realtime respeita RLS: quem não passa nas policies de SELECT de
-- `team_messages` continua não recebendo nada — e é o certo. O canal
-- `geral` depende da policy criada em
-- `04_todo_aprovado_ve_o_top_e_o_geral.sql`; as 9 equipes dependem de
-- `top_team_members` com `released = true`.
--
-- E Realtime é WebSocket do processo: **com o app fechado não chega nada**,
-- publicado ou não. Isso é o que `docs/push_com_app_fechado.md` trata, e
-- continua pendente.
-- ===========================================================================

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
     where pubname = 'supabase_realtime'
       and schemaname = 'public'
       and tablename = 'team_messages'
  ) then
    alter publication supabase_realtime add table public.team_messages;
  end if;
end
$$;

-- Conferência (tem de listar as SEIS, com `team_messages` entre elas):
--   select string_agg(tablename, ', ' order by tablename)
--     from pg_publication_tables
--    where pubname = 'supabase_realtime' and schemaname = 'public';
