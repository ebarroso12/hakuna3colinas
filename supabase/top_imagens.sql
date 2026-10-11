-- ===========================================================================
-- ATÉ 3 IMAGENS POR TOP
--
-- "A cada Top será tudo novo": logo da trilha, brasão, patrocínio. O Top já
-- tinha UMA imagem (`tops.emblema_path`, o campo Emblema); estas são as
-- outras três posições.
--
-- Tabela e não três colunas (`emblema_path_2`, `_3`): com colunas a ordem não
-- se altera sem reescrever valores, apagar a do meio deixa um buraco, e um
-- quarto slot amanhã exige migração. Com `ordem`, os três casos resolvem
-- sozinhos.
--
-- ---------------------------------------------------------------------------
-- POR QUE ESTE ARQUIVO EXISTE
--
-- A tabela foi criada direto no banco de produção em 11/10/2026 e ficou SÓ
-- lá: nada em `supabase/` a criava. Quem reconstruísse o schema a partir do
-- repositório teria o app chamando `top_imagens` sem a tabela existir — e
-- `ImagensDoTop._carregar` engole o erro de leitura de propósito (o
-- formulário do Top tem mais o que fazer do que exibir falha de rede), então
-- a tela apareceria funcionando e simplesmente nunca mostraria imagem
-- nenhuma. Achado por revisão de código, antes de qualquer linha existir.
--
-- Escrito a partir do que está EM PRODUÇÃO (conferido em 11/10/2026:
-- colunas, constraints, RLS e as duas policies), não do que eu lembrava ter
-- criado. `if not exists` em tudo, para rodar nos dois mundos.
-- ===========================================================================

create table if not exists public.top_imagens (
  id          uuid primary key default gen_random_uuid(),
  top_id      uuid not null references public.tops (id) on delete cascade,
  storage_path text not null,
  -- O teto está AQUI, não só na tela. A tela é conveniência; a fronteira é
  -- o banco. `ImagensDoTop` desenha 3 quadros, mas é este check que impede
  -- uma quarta posição de entrar por qualquer outro caminho.
  ordem       smallint not null check (ordem >= 1 and ordem <= 3),
  legenda     text,
  enviado_por uuid references public.profiles (id),
  -- Default `now()` é correto aqui, ao contrário do resto do app: imagem de
  -- Top não é registro de campo, não entra pela fila offline e não acontece
  -- horas antes do upload. Além disso o valor é usado como SELO DE VERSÃO na
  -- URL pública (`TopImagem.selo`) — o caminho no Storage é fixo por
  -- posição, então sem o selo o `ImageCache` do Flutter e o CDN continuam
  -- servindo a imagem antiga depois da troca.
  enviado_em  timestamptz not null default now()
);

-- Uma imagem por posição, por Top. É o que `enviarImagemDoTop` usa como
-- `onConflict: 'top_id,ordem'` — índice ÚNICO SIMPLES de propósito. Índice
-- parcial aqui quebraria o upsert: o Postgres não infere índice parcial na
-- forma simples do `ON CONFLICT`, e foi exatamente o bug da v1.0.29 neste
-- projeto. Não trocar por parcial.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'top_imagens_top_id_ordem_key'
  ) then
    alter table public.top_imagens
      add constraint top_imagens_top_id_ordem_key unique (top_id, ordem);
  end if;
end $$;

alter table public.top_imagens enable row level security;

-- Leitura aberta a quem está logado, como o emblema do Top: é identidade
-- visual do evento, não dado de pessoa. Qualquer participante que abre a
-- lista de Tops precisa ver a logo.
drop policy if exists top_imagens_select on public.top_imagens;
create policy top_imagens_select
  on public.top_imagens for select
  using (true);

-- Escrita só de admin. Quem define a identidade visual do evento é o dono do
-- evento — coordenador de equipe não troca a logo do Top.
drop policy if exists top_imagens_admin on public.top_imagens;
create policy top_imagens_admin
  on public.top_imagens for all
  using (is_admin())
  with check (is_admin());
