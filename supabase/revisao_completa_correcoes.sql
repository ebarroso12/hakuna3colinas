-- ============================================================================
-- REVISÃO COMPLETA DO APP — 10/10/2026
--
-- Varredura das 35 telas, 25 serviços e 22 models, cruzada com o banco.
-- Este arquivo documenta as mudanças de ESQUEMA; as de código estão no
-- commit correspondente. Migrações já aplicadas em produção:
--
--   app_versions_versao_publicada
--   alarme_e_vitais_pela_fila_offline
--   fechar_atendimento_so_em_nome_proprio
--
-- Nenhuma página em branco foi encontrada: as 35 telas renderizam conteúdo
-- real e todas têm texto de estado vazio. O que havia eram defeitos de
-- integração — nada que `flutter analyze` ou teste de unidade pegasse.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. O ALARME NÃO TINHA FILA  (o pior dos achados)
--
-- `sendTopAlert` era `insert` direto no Supabase. Sem sinal — o estado
-- normal na trilha — falhava, a tela dizia "não foi possível disparar o
-- alarme" e o registro era DESCARTADO. Atendimento, foto, posição, chat e
-- auditoria todos passavam pela fila offline; o alarme, não. Justamente
-- ele, que é usado em acidente.
--
-- Segundo defeito, de recebimento: o alarme só existia como faixa vermelha
-- DENTRO da tela de detalhe do Top, alimentada por realtime. Quem
-- estivesse na lista de participantes, no chat, ou com o celular no bolso
-- não recebia nada — sem som, sem vibração, sem notificação.
--
-- No banco, o que faltava era o `client_id`:
-- ----------------------------------------------------------------------------
alter table public.top_alerts add column if not exists client_id uuid;
create unique index if not exists top_alerts_client_id_key
  on public.top_alerts (client_id);

-- ÍNDICE ÚNICO NÃO PARCIAL, e isto não é detalhe. `upsert(onConflict:
-- 'client_id')` emite a forma SIMPLES do `ON CONFLICT`, e o Postgres só
-- infere um índice parcial quando o comando repete o predicado do índice.
-- Com índice parcial o envio falha com 42P10, que `_motivoPermanente`
-- classifica como PERMANENTE — e a entrada vai para quarentena. Foi
-- exatamente o bug da v1.0.29, que mandava a fila inteira para quarentena.


-- ----------------------------------------------------------------------------
-- 2. SINAIS VITAIS TAMBÉM IAM DIRETO, E NÃO RECLASSIFICAVAM A TRIAGEM
--
-- `recordVitalSigns` era `insert` puro. Offline a medição era perdida e
-- não aparecia nem na fila: o Hakuna media a pressão, via "registrado" e o
-- dado não existia em lugar nenhum.
--
-- E havia uma incoerência clínica pior que a perda: `TriageDinamica` escala
-- a cor para vermelho a partir de `cache_ultima_afericao`, e essa tabela
-- local só era alimentada por `AtendimentoService`. Então SpO₂ 85 medido no
-- formulário de ATENDIMENTO pintava a pessoa de vermelho, e o MESMO 85
-- medido na tela de SINAIS VITAIS não pintava nada. Duas portas para a
-- mesma medida, uma funcionando.
-- ----------------------------------------------------------------------------
alter table public.vital_signs add column if not exists client_id uuid;
create unique index if not exists vital_signs_client_id_key
  on public.vital_signs (client_id);


-- ----------------------------------------------------------------------------
-- 3. DA SEGUNDA FOTO EM DIANTE, A LINHA ERA DESCARTADA
--
-- Todas as fotos de um atendimento subiam com `'client_id': <client_id do
-- ATENDIMENTO>` — o mesmo valor para todas. Como
-- `atendimento_fotos.client_id` é único e o envio usa `ignoreDuplicates:
-- true`, o arquivo ia para o Storage e a LINHA era ignorada em silêncio.
-- Foto clínica órfã: bytes no servidor que nenhuma consulta alcança.
--
-- O identificador por foto já existia no código (`'$_clientId-${n+1}'`, no
-- nome do arquivo) e simplesmente não era levado ao payload. Esse nome
-- tinha um bug próprio: remover uma foto e tirar outra repetia o número, e
-- o `File.copy` SOBRESCREVIA a foto anterior.
--
-- Correção no app: um uuid por foto, usado no nome do arquivo e no payload.
-- No banco, só a divida de tipo:
-- ----------------------------------------------------------------------------
alter table public.atendimento_fotos
  drop constraint if exists atendimento_fotos_client_id_key;
drop index if exists idx_atendimentos_client_id;

-- `client_id` era `text` nestas duas tabelas e `uuid` em todas as outras.
-- O app sempre gerou uuid v4, então o conteúdo já era compatível — só o
-- tipo divergia. Converter com as tabelas vazias é seguro; depois do
-- evento não seria.
alter table public.atendimentos
  alter column client_id type uuid using nullif(client_id, '')::uuid;
alter table public.atendimento_fotos
  alter column client_id type uuid using nullif(client_id, '')::uuid;

create unique index atendimentos_client_id_key
  on public.atendimentos (client_id);
create unique index atendimento_fotos_client_id_key
  on public.atendimento_fotos (client_id);


-- ----------------------------------------------------------------------------
-- 4. NENHUMA TELA EXIBIA AS FOTOS
--
-- Nada em `lib/screens/` lia `atendimento_fotos` nem `storage_path`. A
-- câmera gravava, a fila subia, o Storage guardava — e não havia como
-- rever. Em registro de ferida isso é metade do atendimento jogada fora.
--
-- Sem mudança de esquema. No app: `FotosDoAtendimento`, com URL assinada
-- de 1 hora (o bucket `atendimentos` é privado, e tem de continuar: foto
-- de ferida é dado clínico) e, para o que ainda está na fila, o arquivo
-- local — que funciona SEM rede, quando mais importa.
-- ----------------------------------------------------------------------------


-- ----------------------------------------------------------------------------
-- 5. ATENDIMENTO NUNCA FECHAVA
--
-- `status` vinha só do default da coluna e `closed_at` nunca era escrito.
-- Todo atendimento ficava `aberto` para sempre; numa lista de 30 não se
-- distinguia quem ainda precisava de atenção.
--
-- Faltava a coluna que diz QUEM encerrou — sem ela `closed_at` informa que
-- fechou mas não quem, e em prontuário isso não serve.
-- ----------------------------------------------------------------------------
alter table public.atendimentos
  add column if not exists closed_by uuid references public.profiles(id);

-- E a policy de UPDATE não tinha WITH CHECK. Sem ele o Postgres reaproveita
-- o USING, e um Hakuna liberado podia gravar `closed_by` com o id de OUTRA
-- pessoa — assinar o fechamento do atendimento no nome de um colega.
--
-- Provado com sessão simulada (Hakuna comum, não admin, liberado no Top):
--   assinar no nome do colega  -> bloqueado pela RLS
--   assinar no próprio nome    -> permitido
--
-- O admin segue podendo corrigir, porque é ele que acerta registro errado
-- depois do evento.
drop policy if exists atendimentos_update_owner_or_admin on public.atendimentos;
create policy atendimentos_update_owner_or_admin on public.atendimentos
  for update
  using (
    exists (
      select 1 from public.top_hakunas th
      where th.top_id = atendimentos.top_id
        and th.profile_id = auth.uid()
        and th.released = true
    ) or is_admin()
  )
  with check (
    (
      exists (
        select 1 from public.top_hakunas th
        where th.top_id = atendimentos.top_id
          and th.profile_id = auth.uid()
          and th.released = true
      ) or is_admin()
    )
    and (closed_by is null or closed_by = auth.uid() or is_admin())
  );

-- OS OUTROS SETE ESTADOS CONTINUAM SEM USO, e é decisão, não esquecimento.
-- `reconhecido`, `atribuido`, `a_caminho`, `no_local`, `em_andamento`,
-- `escalado` e `cancelado` formam um fluxo de DESPACHO: exigem painel de
-- coordenação e regra de quem atribui o quê. Isso é decisão de produto.
-- Meio-implementado seria pior que ausente — estado que ninguém atualiza
-- mente sobre a situação do paciente.


-- ----------------------------------------------------------------------------
-- 6. PRONTUÁRIO CEGO SEM REDE
--
-- Lia os atendimentos direto do Supabase, contra a regra do projeto
-- ("leitura vem do SQLite"). E o contador de pendentes era lido DEPOIS da
-- chamada de rede, no mesmo `try`: quando a rede falhava, o `catch`
-- engolia tudo e o Hakuna não via nem o histórico nem o atendimento que
-- ele mesmo tinha registrado cinco minutos antes.
--
-- Sem mudança de esquema. No app, o que está no aparelho é lido PRIMEIRO e
-- fora do try da rede.
-- ----------------------------------------------------------------------------


-- ----------------------------------------------------------------------------
-- 7. `audit_log` NÃO REGISTRAVA EDIÇÃO DE FICHA
--
-- `AcaoAuditada.fichaAlterada` existia no enum e NADA no app a usava. Só
-- `TagService` escrevia em `audit_log` (4 chamadas, todas de pulseira).
-- Alterar comorbidade, tipo sanguíneo ou alergia de um paciente não deixava
-- rastro nenhum.
--
-- Sem mudança de esquema. No app, o formulário de participante passa a
-- registrar a alteração com os NOMES dos campos que mudaram — nunca os
-- valores. `audit_log` é legível por qualquer admin, e copiar comorbidade e
-- alergia para lá criaria um segundo prontuário com regra de acesso mais
-- frouxa que o primeiro.
-- ----------------------------------------------------------------------------


-- ----------------------------------------------------------------------------
-- 8. "QUEM ESTÁ MAIS PERTO?" NÃO TINHA RESPOSTA
--
-- Havia GPS dos Hakunas, havia alarme com coordenada, e nada cruzava os
-- dois. Na prática a coordenação era por rádio, com a informação já no
-- banco e ninguém para ler.
--
-- Sem mudança de esquema. `ProximidadeService` ordena por distância de
-- Haversine (a mesma conta que `StatsService` já usava), usando só a ÚLTIMA
-- posição de cada Hakuna e descartando ponto com mais de 2 horas.
--
-- Duas limitações ficam DITAS na tela, não escondidas: a distância é em
-- linha reta — a trilha é sempre mais longa — e a idade da posição aparece
-- ao lado do número, porque "250 m" de um ponto de 40 minutos atrás é
-- ficção.
-- ----------------------------------------------------------------------------


-- ============================================================================
-- O QUE CONTINUA EM ABERTO, de propósito e por ordem de risco
--
-- 1. NOTIFICAÇÃO COM O APP FECHADO não existe. O alarme agora chega em
--    qualquer tela, com som e vibração, mas só com o app aberto. Push de
--    app fechado exige FCM: projeto Firebase, `google-services.json` e um
--    serviço no servidor para disparar. Não foi feito. Em campo isso
--    significa que o alarme serve para quem está com o app aberto; para
--    quem não está, continua valendo o rádio.
--
-- 2. 144 DOS 216 SENDERISTAS ESTÃO SEM `participant_code`. O autocadastro
--    exige o número NA LISTA do Top (`participante_elegivel`), então essas
--    144 pessoas recebem a recusa genérica e vão achar que a senha está
--    errada. Resta o caminho de pedir código ao admin, um a um — o gargalo
--    que a senha compartilhada existia para eliminar. A correção é dado,
--    não código: preencher os números. NÃO INVENTAR NÚMERO.
--
-- 3. SÓ 1 HAKUNA LIBERADO NO TOP 1782 (o admin). As 8 policies que
--    dependem de `top_hakunas` passam a valer para cada médico só depois
--    que ele for liberado naquele Top.
--
-- 4. QUATRO TABELAS SEM USO NO APP: `attendance_members`,
--    `direct_messages`, `notifications`, `nfc_tags`. Ficam — `notifications`
--    é o lugar natural do push quando ele existir. Não foram apagadas
--    porque apagar tabela é irreversível e elas não custam nada vazias.
--
-- 5. NENHUM TESTE DE HARDWARE. Os 322 testes cobrem lógica. NFC, câmera,
--    GPS com tela bloqueada, o som do alarme e o `launchUrl` do botão
--    Atualizar só se provam em aparelho Android físico.
-- ============================================================================
