-- ===========================================================================
-- AS 5 PEÇAS QUE NUNCA ESTIVERAM NO REPOSITÓRIO
--
-- Escrito em 23/11/2026, depois que o projeto Supabase `jitfbambhmfnqiatwoud`
-- foi APAGADO e o app ficou sem backend a 3 dias do Top de Franca.
--
-- O `CLAUDE.md` avisava: *"Ainda fora do repositório: `top_team_members` e
-- `team_messages`. As duas só existem em produção. Não as escrevi de memória
-- de propósito."* O aviso estava certo e o preço veio. Cruzando o que o app
-- consulta (`from('...')` no Dart) contra o que as 34 migrações criam,
-- faltavam CINCO coisas:
--
--     top_participants   a ficha do senderista — prontuário
--     team_messages      o chat das 9 equipes
--     top_team_members   quem é de qual equipe
--     audit_log          o registro de segurança
--     bucket `emblemas`  a logo do Top
--
-- ---------------------------------------------------------------------------
-- DE ONDE VEIO CADA COLUNA, JÁ QUE NÃO VEIO DE MEMÓRIA
--
-- 1. Os nomes exatos saíram do `fromMap` de cada model — é o contrato que o
--    app usa para ler a linha, então divergir ali quebra na primeira tela.
-- 2. O que `participantes_e_atendimentos.sql` ACRESCENTA por `alter table`
--    prova o que a tabela-base tinha antes: tudo que está lá como
--    `add column` não pertence ao `create` original.
-- 3. Os índices vieram dos arquivos que já os criam — eles referenciam
--    colunas e, com isso, confirmam tipo e nulidade.
-- 4. `registered_by` é `not null`: está documentado no `CLAUDE.md` como a
--    causa do 23502 que mandava edição para a quarentena.
--
-- O que NÃO dá para recuperar por leitura são os DADOS. Isto recria a
-- estrutura, não as 216 pessoas.
--
-- ---------------------------------------------------------------------------
-- ORDEM: rode este arquivo DEPOIS de `schema.sql` e ANTES dos demais.
-- Os outros 33 fazem `alter table` e `create policy` em cima destas.
--
-- Idempotente de verdade — rodado duas vezes seguidas, não dá erro. Ver a
-- regra em `CLAUDE.md`: `create policy` não tem `if not exists`, então cada
-- uma leva o `drop policy if exists` do próprio nome logo acima.
-- ===========================================================================


-- ---------------------------------------------------------------------------
-- 1. top_participants — A FICHA DO SENDERISTA
--
-- É prontuário: comorbidade, alergia, medicação contínua. A cerca aqui não é
-- conveniência, é a diferença entre dado clínico guardado e dado clínico
-- vazado.
--
-- O `id` é gerado NO APARELHO e não por `default gen_random_uuid()`. Isso é
-- deliberado e está no `CLAUDE.md`: cadastro offline precisa de identidade
-- antes de ter rede — dá para abrir a ficha, atender e emitir pulseira sem
-- sinal — e o próprio id é a chave de idempotência do envio.
-- ---------------------------------------------------------------------------
create table if not exists public.top_participants (
  id                       uuid primary key,
  top_id                   uuid not null references public.tops (id) on delete cascade,

  -- Conta no app, quando a pessoa já se cadastrou. Nulo é o normal: a
  -- maioria dos senderistas está na lista do Top sem nunca ter logado.
  linked_profile_id        uuid references public.profiles (id) on delete set null,

  -- Número do Legendários. NÃO é único por Top de propósito — ver a nota de
  -- índice no fim desta seção.
  participant_code         text,

  full_name                text not null,
  nickname                 text,
  phone                    text,
  birth_date               date,
  emergency_contact        text,

  -- Quem cadastrou. NOT NULL e é o que permite saber depois quem respondeu
  -- por aquela ficha. Foi a causa de um bug caro: `upsert` na EDIÇÃO tenta o
  -- INSERT primeiro, bate aqui com 23502, `_motivoPermanente` classifica
  -- como PERMANENTE e a edição vai para a quarentena sem nunca subir. Por
  -- isso edição usa `update().eq('id', ...)` e não upsert.
  registered_by            uuid not null references public.profiles (id) on delete restrict,

  active                   boolean not null default true,
  tag_uid                  text,
  notes                    text,

  -- Cadastro de teste. Existe como DADO e não como convenção de nome: o
  -- único sinal antes era o texto "TESTE" em caixa alta, que ninguém pode
  -- usar como critério de exclusão em massa.
  is_teste                 boolean not null default false,

  -- --- acrescentadas em 09/10/2026 por participantes_e_atendimentos.sql ---
  familia                  text,
  cidade                   text,
  estado                   text,
  height_cm                numeric,
  weight_kg                numeric,
  blood_type               text,
  biotipo                  text,
  cirurgias                text,
  observacao_hakuna        text,
  atividade_fisica_semanal text,

  -- Só doença entra aqui. Plano de saúde, alergia, medicação e restrição têm
  -- coluna própria porque a TRIAGEM CONTA O TAMANHO DESTE ARRAY: misturar
  -- faria alguém sem nenhuma doença ser contado como tendo uma e subir de
  -- verde para amarelo.
  comorbidades             text[] not null default '{}',
  alergias                 text,
  plano_saude              text,
  medicamentos_continuos   text,
  restricoes_fisicas       text,

  created_at               timestamptz not null default now()
);

-- Uma conta por pessoa por Top. PARCIAL porque `linked_profile_id` é nulo na
-- maioria das linhas, e em Postgres NULL não conflita com NULL — sem o
-- `where`, o índice não impediria nada e ainda assim pareceria que impedia.
create unique index if not exists idx_participants_perfil_unico
  on public.top_participants (top_id, linked_profile_id)
  where linked_profile_id is not null;

-- NÃO é único, e isso é uma escolha com custo conhecido: reimportar planilha
-- cria ficha duplicada com o mesmo número, e `participante_elegivel` resolve
-- com `limit 1`. A tela de importação confere e desmarca duplicata antes de
-- gravar. Tornar único aqui quebraria o cadastro de quem ainda não tem
-- número — e 144 dos 216 do Top 1782 estavam nessa situação.
create index if not exists idx_participants_codigo
  on public.top_participants (top_id, participant_code);

create index if not exists idx_participants_familia
  on public.top_participants (top_id, familia);
create index if not exists idx_participants_nome
  on public.top_participants (top_id, lower(full_name));
create index if not exists idx_participants_registered_by
  on public.top_participants (registered_by);
create index if not exists idx_participants_linked_profile
  on public.top_participants (linked_profile_id)
  where linked_profile_id is not null;

alter table public.top_participants enable row level security;

-- LEITURA: Hakuna liberado no Top, ou admin. É a mesma cerca de atendimento
-- e prontuário, e tem de continuar assim — membro de mídia não tem motivo
-- para ler comorbidade de ninguém.
drop policy if exists top_participants_select_hakuna on public.top_participants;
create policy top_participants_select_hakuna
  on public.top_participants for select
  using (
    is_admin()
    or exists (
      select 1 from public.top_hakunas th
      where th.top_id = top_participants.top_id
        and th.profile_id = auth.uid()
        and th.released = true
    )
  );

-- ESCRITA: mesma cerca, e `registered_by` tem de ser quem está gravando.
-- Sem o `with check` do autor, um Hakuna poderia carimbar a ficha no nome de
-- outro — e é exatamente a autoria que esta coluna existe para guardar.
drop policy if exists top_participants_insert_hakuna on public.top_participants;
create policy top_participants_insert_hakuna
  on public.top_participants for insert
  with check (
    registered_by = auth.uid()
    and (
      is_admin()
      or exists (
        select 1 from public.top_hakunas th
        where th.top_id = top_participants.top_id
          and th.profile_id = auth.uid()
          and th.released = true
      )
    )
  );

drop policy if exists top_participants_update_hakuna on public.top_participants;
create policy top_participants_update_hakuna
  on public.top_participants for update
  using (
    is_admin()
    or exists (
      select 1 from public.top_hakunas th
      where th.top_id = top_participants.top_id
        and th.profile_id = auth.uid()
        and th.released = true
    )
  );
-- Sem `with check` no update de propósito: a edição NÃO manda
-- `registered_by` (a autoria é de quem cadastrou primeiro), e exigi-lo aqui
-- recusaria toda edição legítima.

-- DELETE fica para `exclusao_protegida.sql`, que já tem
-- `top_participants_delete_master`. Não repetir aqui.


-- ---------------------------------------------------------------------------
-- 2. top_team_members — QUEM É DE QUAL EQUIPE
--
-- As três dimensões não se confundem: `user_role` é o que a pessoa pode
-- fazer no app, `team` é onde ela trabalha, `team_role` é a hierarquia
-- dentro da equipe. Esta tabela carrega as duas últimas.
--
-- `released` e `blocked` são separados e os dois importam: `is_team_member`
-- exige `released = true AND blocked = false`. Quem entra sem liberação fica
-- sem chat e sem bloco de anotações — e sem saber o que pedir, que foi o
-- defeito que a tela de equipes passou a explicar.
-- ---------------------------------------------------------------------------
create table if not exists public.top_team_members (
  id         bigint generated always as identity primary key,
  top_id     uuid      not null references public.tops (id)     on delete cascade,
  profile_id uuid      not null references public.profiles (id) on delete cascade,
  team       team_key  not null,
  team_role  team_role not null default 'membro',
  released   boolean   not null default false,
  blocked    boolean   not null default false,
  is_team_admin boolean,
  created_at timestamptz not null default now(),

  -- Uma pessoa, uma linha por equipe. Sem isto, incluir duas vezes criaria
  -- vínculo duplicado e `is_team_member` passaria a depender de qual linha o
  -- Postgres lesse primeiro.
  unique (top_id, team, profile_id)
);

create index if not exists idx_team_members_profile
  on public.top_team_members (profile_id);
create index if not exists idx_team_members_top_team
  on public.top_team_members (top_id, team);

alter table public.top_team_members enable row level security;

-- Cada um vê os próprios vínculos; admin vê todos. Sem a parte do admin, a
-- tela "Equipes do Top" ficaria vazia justamente para quem monta as equipes.
drop policy if exists top_team_members_select on public.top_team_members;
create policy top_team_members_select
  on public.top_team_members for select
  using (profile_id = auth.uid() or is_admin());

-- Só admin monta equipe. Coordenador incluir membro é decisão de produto que
-- ainda não foi tomada — e policy mais aberta do que a decisão é como se
-- entrega acesso sem ninguém perceber.
drop policy if exists top_team_members_admin_write on public.top_team_members;
create policy top_team_members_admin_write
  on public.top_team_members for all
  using (is_admin())
  with check (is_admin());


-- ---------------------------------------------------------------------------
-- 3. team_messages — O CHAT DAS 9 EQUIPES
--
-- `sender_name` é desnormalizado de propósito, pelo mesmo motivo de
-- `top_alerts.sender_name`: `profiles` é fechada para quem recebe, o Realtime
-- não passa por RPC, e offline não há rede para buscar. Guardar o nome DO
-- MOMENTO do envio é a vantagem, não o defeito.
--
-- `client_id` com índice ÚNICO é o que faz a fila offline não duplicar:
-- "falhou" inclui o caso em que o insert chegou e a resposta se perdeu.
-- ---------------------------------------------------------------------------
create table if not exists public.team_messages (
  id          bigint generated always as identity primary key,
  top_id      uuid      not null references public.tops (id)     on delete cascade,
  team        team_key  not null,
  sender_id   uuid      not null references public.profiles (id) on delete cascade,
  sender_name text,
  team_role   team_role,
  body        text      not null,

  -- Mensagem de alerta da equipe. Quem pode marcar é coordenação e admin —
  -- a regra fica na policy de INSERT, em `admin_ve_todas_as_equipes.sql`.
  is_alert    boolean   not null default false,

  -- Hora DO APARELHO, não `now()`: offline a mensagem é escrita horas antes
  -- de subir, e carimbar com a hora do servidor contaria a história errada.
  created_at  timestamptz not null default now(),
  edited_at   timestamptz,

  -- UUID, nao text. `Outbox.novoClientId()` gera UUID v4 de verdade (versao
  -- e variante carimbadas nos bytes 6 e 8), e as outras OITO tabelas da fila
  -- ja usam `uuid`. Escrevi `text` na primeira versao e a conferencia pegou:
  -- tipo divergente numa chave de idempotencia e convite a comparacao que
  -- funciona em oito lugares e falha no nono.
  client_id   uuid
);

create unique index if not exists idx_team_messages_client_id
  on public.team_messages (client_id)
  where client_id is not null;
create index if not exists idx_team_messages_sender
  on public.team_messages (sender_id);
create index if not exists idx_team_messages_conversa
  on public.team_messages (top_id, team, created_at desc);

alter table public.team_messages enable row level security;

-- Membro liberado da equipe lê o chat dela. As policies que SOMAM o acesso
-- do admin às 9 equipes estão em `admin_ve_todas_as_equipes.sql` — policies
-- do mesmo comando são OR entre si, então lá amplia sem tirar nada daqui.
drop policy if exists team_messages_select_membro on public.team_messages;
create policy team_messages_select_membro
  on public.team_messages for select
  using (is_team_member(top_id, team));

drop policy if exists team_messages_insert_membro on public.team_messages;
create policy team_messages_insert_membro
  on public.team_messages for insert
  with check (
    sender_id = auth.uid()
    and is_team_member(top_id, team)
    -- Alerta é da coordenação. Membro comum marcando alerta esvazia o
    -- significado do alerta para todo mundo.
    and (is_alert = false or is_team_coordenador(top_id, team))
  );

-- Editar/apagar: só a própria mensagem. Mensagem de chat alterada por
-- terceiro é registro que não vale como registro.
drop policy if exists team_messages_update_propria on public.team_messages;
create policy team_messages_update_propria
  on public.team_messages for update
  using (sender_id = auth.uid())
  with check (sender_id = auth.uid());


-- ---------------------------------------------------------------------------
-- 4. audit_log — O REGISTRO DE SEGURANÇA
--
-- Recebe só o SUBCONJUNTO de segurança: tag revogada apresentada, tag
-- desconhecida, emissão, revogação, ficha alterada. Toda leitura de pulseira
-- vai para `tag_leituras`; mandar tudo para as duas dobraria a escrita sem
-- responder nada novo.
--
-- `occurred_at` é a hora DO APARELHO e pode ser muito anterior ao
-- `created_at`. Ler sempre `coalesce(occurred_at, created_at)`.
-- ---------------------------------------------------------------------------
create table if not exists public.audit_log (
  id             bigint generated always as identity primary key,
  action         text not null,
  actor_id       uuid references public.profiles (id) on delete set null,
  entity_type    text,
  entity_id      text,
  top_id         uuid references public.tops (id) on delete cascade,
  participant_id uuid,
  resultado      text,
  tinha_rede     boolean,
  latitude       double precision,
  longitude      double precision,
  metadata       jsonb,
  occurred_at    timestamptz,
  created_at     timestamptz not null default now(),
  -- uuid pelo mesmo motivo de `team_messages` — ver a nota la.
  client_id      uuid
);

create unique index if not exists idx_audit_log_client_id
  on public.audit_log (client_id)
  where client_id is not null;
create index if not exists idx_audit_log_top_quando
  on public.audit_log (top_id, coalesce(occurred_at, created_at) desc);

alter table public.audit_log enable row level security;

-- Leitura só de admin. É registro de segurança: quem o lê vê padrão de
-- movimento de outras pessoas.
drop policy if exists audit_log_select_admin on public.audit_log;
create policy audit_log_select_admin
  on public.audit_log for select
  using (is_admin());

-- Escrita por quem está logado, carimbando a própria autoria. `actor_id`
-- preso a `auth.uid()` é o que impede registrar ação no nome de outro — e é
-- também o motivo de a fila de um usuário ser recusada se outro logar antes
-- do sync (pendência conhecida, "Troca de usuário no mesmo aparelho").
drop policy if exists audit_log_insert_proprio on public.audit_log;
create policy audit_log_insert_proprio
  on public.audit_log for insert
  with check (actor_id = auth.uid());

-- Sem UPDATE e sem DELETE, para ninguém: log que se edita não é log.


-- ---------------------------------------------------------------------------
-- 5. bucket `emblemas`
--
-- Público de propósito: é identidade visual do evento, não dado de pessoa.
-- Qualquer participante que abre a lista de Tops precisa ver a logo, e o app
-- a serve por URL pública (`AdminService.urlEmblema`).
--
-- O bucket `atendimentos` (foto de ferida) é outra história e NÃO está aqui:
-- ele nasce privado em `emblema_e_storage.sql`, com cerca própria.
--
-- A policy de SELECT é obrigatória e já custou caro: sem ela, RLS ligado
-- significa leitura NEGADA para todos — inclusive para o admin dono do
-- arquivo. Como `uploadEmblema` usa `upsert: true` e o Storage procura o
-- objeto antes de gravar, a ausência de SELECT aparecia como
-- `403 "new row violates row-level security policy"`. Mensagem enganosa:
-- parece permissão de ESCRITA e era de LEITURA. Ver `emblemas_leitura.sql`.
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit)
values ('emblemas', 'emblemas', true, 5242880)
on conflict (id) do update
  set public = true,
      file_size_limit = 5242880;

drop policy if exists emblemas_leitura on storage.objects;
create policy emblemas_leitura
  on storage.objects for select
  using (bucket_id = 'emblemas');

drop policy if exists emblemas_admin_escreve on storage.objects;
create policy emblemas_admin_escreve
  on storage.objects for insert
  with check (bucket_id = 'emblemas' and is_admin());

drop policy if exists emblemas_admin_atualiza on storage.objects;
create policy emblemas_admin_atualiza
  on storage.objects for update
  using (bucket_id = 'emblemas' and is_admin());

drop policy if exists emblemas_admin_apaga on storage.objects;
create policy emblemas_admin_apaga
  on storage.objects for delete
  using (bucket_id = 'emblemas' and is_admin());


-- ===========================================================================
-- CONFERÊNCIA — rode depois e compare com o esperado
-- ===========================================================================
--
-- select table_name from information_schema.tables
--  where table_schema='public'
--    and table_name in ('top_participants','top_team_members',
--                       'team_messages','audit_log')
--  order by table_name;
--   -> tem de devolver as QUATRO
--
-- select id, public from storage.buckets where id='emblemas';
--   -> emblemas | true
--
-- select tablename, count(*) from pg_policies
--  where schemaname='public'
--    and tablename in ('top_participants','top_team_members',
--                      'team_messages','audit_log')
--  group by tablename order by tablename;
--   -> top_participants 3 (+1 de exclusao_protegida = 4 no fim)
--      top_team_members 2
--      team_messages    3 (+2 de admin_ve_todas_as_equipes = 5 no fim)
--      audit_log        2
--
-- E rode o arquivo DUAS VEZES. "Idempotente" não é intenção, é propriedade
-- que se verifica — a lição de 11/10/2026, quando um arquivo que se dizia
-- idempotente morreu na segunda execução e reverteu, junto, a coluna que
-- ainda faltava.
