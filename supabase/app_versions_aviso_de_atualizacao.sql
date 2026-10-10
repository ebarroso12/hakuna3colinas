-- ============================================================================
-- app_versions — versão publicada do app e aviso de atualização
--
-- Aplicado em produção em 10/10/2026 como a migração
-- `app_versions_versao_publicada`. Este arquivo é a cópia versionada, com o
-- raciocínio; o banco já tem a tabela.
--
-- POR QUE EXISTE
--
-- O pedido foi "mostre na lateral a versão que está no momento; caso esteja
-- desatualizado, crie o botão Atualizar". Para o app saber que está
-- desatualizado ele precisa de uma fonte que diga qual é a versão atual, e
-- essa fonte tem de estar acessível ao celular de quem está em campo.
--
-- O GitHub Release não serve: o repositório é PRIVADO, então o link do APK
-- exige login no GitHub, e ninguém da equipe médica tem conta no projeto. A
-- distribuição real é o Google Drive, e é para lá que `apk_url` aponta.
--
-- POR QUE A COMPARAÇÃO É POR build_number
--
-- Comparar o texto da versão dá resultado errado na hora errada: em ordem
-- lexicográfica "1.0.9" é MAIOR que "1.0.10". O app diria que está em dia
-- estando uma versão atrás, e o aviso nunca apareceria. `build_number` é o
-- versionCode do Android: inteiro, monotônico, sem ambiguidade.
-- `test/services/atualizacao_service_test.dart` trava isso com o par exato
-- que quebra a comparação por texto.
-- ============================================================================

create table if not exists public.app_versions (
  version       text primary key,
  build_number  integer not null,
  apk_url       text    not null,
  notes         text,
  -- Permite gravar a linha e só depois disparar o aviso na tela de todos:
  -- publicar é um `update ... set published = true`, não um insert correndo
  -- contra o upload do arquivo.
  published     boolean not null default true,
  published_at  timestamptz not null default now()
);

alter table public.app_versions enable row level security;

-- Leitura para quem está logado. Saber que existe versão nova não é segredo,
-- e todo usuário do app precisa dessa informação — inclusive o senderista.
drop policy if exists app_versions_select on public.app_versions;
create policy app_versions_select on public.app_versions
  for select to authenticated using (true);

-- Escrita só de admin: esta linha dispara um aviso no aparelho de todo
-- mundo e aponta para um arquivo que as pessoas vão instalar. Quem escreve
-- aqui escolhe o que a equipe instala.
drop policy if exists app_versions_write_admin on public.app_versions;
create policy app_versions_write_admin on public.app_versions
  for all to authenticated using (is_admin()) with check (is_admin());

create index if not exists idx_app_versions_build
  on public.app_versions (build_number desc) where published;

-- ============================================================================
-- COMO PUBLICAR UMA VERSÃO (o passo que fecha o fluxo de release)
--
--   insert into public.app_versions (version, build_number, apk_url, notes)
--   values ('1.0.30', 31,
--           'https://drive.google.com/file/d/<ID>/view',
--           'Versão na gaveta e botão Atualizar.');
--
-- O `build_number` tem de ser o `+N` do `pubspec.yaml` daquela build — é o
-- mesmo número que o `aapt2 dump badging` mostra como `versionCode`. Confira
-- no APK antes de inserir, em vez de confiar na memória: inserir um número
-- menor que o real faz o aviso nunca aparecer, e maior faz ele aparecer para
-- sempre, inclusive para quem já atualizou.
--
-- O arquivo no Drive precisa estar compartilhado com quem vai baixar, senão
-- o botão abre uma tela de "pedir acesso".
-- ============================================================================
