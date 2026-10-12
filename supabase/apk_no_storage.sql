-- ============================================================================
-- 12/10/2026 — O APK SAI DO DRIVE E VAI PARA O SUPABASE STORAGE
-- ============================================================================
--
-- O ACHADO QUE MOTIVOU ISTO
--
-- Conferido pela API do Google Drive: NENHUM APK la jamais esteve
-- compartilhado. Os APKs 1.0.35, 1.0.37, 1.0.38, 1.0.39, a pasta
-- "Legendarios APK" e a pasta `apk1035` voltaram todos apenas o dono, sem
-- permissao de link.
--
-- Ou seja: o botao ATUALIZAR nunca funcionou para ninguem alem do dono.
-- Quem tocava nele caia em "Solicitar acesso" do Google.
--
-- A causa raiz nao e esquecimento — e que compartilhar era um passo MANUAL
-- repetido a cada release. Passo manual repetido e passo que vai ser
-- esquecido, e esse foi esquecido em pelo menos quatro versoes seguidas.
--
-- Bucket publico resolve de outro jeito: nao ha o que compartilhar. A URL
-- e publica por construcao, e `.github/workflows/android-build.yml` sobe o
-- arquivo e escreve a linha de `app_versions` sozinho.
--
-- GANHO DE QUEBRA: o Drive nao baixa direto arquivo grande — mostra "nao
-- foi possivel verificar se ha virus" e exige um segundo clique. O Storage
-- devolve o arquivo. Um toque menos no meio do mato.
--
-- O LIMITE QUE IMPORTA, E ELE E DURO
--
-- Plano FREE do Supabase: 50 MB por arquivo, 1 GB no total. O APK universal
-- tem 76 MB — NAO CABE. Medido no arquivo da v1.0.39:
--
--   x86_64        27,1 MB   <- so serve para EMULADOR
--   arm64-v8a     24,7 MB   <- praticamente todo celular desde 2016
--   armeabi-v7a   20,9 MB   <- 32 bits, aparelho antigo
--   resto          4,8 MB
--
-- Entao `--split-per-abi` nao e otimizacao, e requisito: o arm64 sozinho
-- da ~30 MB e cabe folgado. De quebra, para de baixar 27 MB de x86_64 que
-- nenhum celular usa. O `CLAUDE.md` ja apontava esse caminho.
--
-- Enquanto o build for universal, o passo do CI avisa e NAO publica — ele
-- confere o tamanho antes de enviar, para nao receber um 413 cru.
-- ============================================================================


-- ----------------------------------------------------------------------------
-- 1. O bucket, publico para leitura
-- ----------------------------------------------------------------------------
--
-- `public = true` significa leitura sem token: e exatamente o que se quer
-- de um instalador. APK nao e segredo — ele e distribuido para 200 pessoas
-- por WhatsApp. O que precisa de cerca e o dado clinico, nao o instalador.
--
-- `file_size_limit` em 50 MB bate com o teto do plano free de proposito:
-- recusa cedo, com erro claro, em vez de aceitar e falhar no meio.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'apks',
  'apks',
  true,
  52428800,
  array['application/vnd.android.package-archive', 'application/octet-stream']
)
on conflict (id) do update
  set public             = true,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;


-- ----------------------------------------------------------------------------
-- 2. Quem escreve: ninguem, pelo app
-- ----------------------------------------------------------------------------
--
-- Sem policy de INSERT/UPDATE/DELETE para `authenticated` nem `anon`. Quem
-- sobe e o CI, com `service_role`, que ignora RLS por natureza.
--
-- Isso e deliberado e vale explicar: uma policy de escrita para
-- `authenticated` deixaria QUALQUER usuario logado substituir o APK que as
-- outras 200 pessoas vao instalar. Trocar instalador e a definicao de
-- ataque de cadeia de suprimentos — nao se abre essa porta por
-- conveniencia de upload.
--
-- A leitura publica vem do `public = true` do bucket; nao precisa de
-- policy. Estes drops existem para o caso de alguem ter criado o bucket a
-- mao com escrita aberta antes deste arquivo.
drop policy if exists apks_insert_authenticated on storage.objects;
drop policy if exists apks_update_authenticated on storage.objects;
drop policy if exists apks_delete_authenticated on storage.objects;


-- ----------------------------------------------------------------------------
-- 3. CONFERENCIA
-- ----------------------------------------------------------------------------
--
--   select id, public, file_size_limit, allowed_mime_types
--   from storage.buckets where id = 'apks';
--
--   -- esperado: public = true · file_size_limit = 52428800
--
-- Nenhuma policy de escrita deve aparecer para o bucket:
--
--   select policyname, cmd from pg_policies
--   where schemaname = 'storage' and tablename = 'objects'
--     and policyname like 'apks%';
--
--   -- esperado: 0 linhas
--
-- Depois do primeiro upload pelo CI, a URL publica fica:
--
--   https://<projeto>.supabase.co/storage/v1/object/public/apks/legendarios<versao>.apk
--
-- Teste de verdade: abra essa URL numa janela ANONIMA do navegador, sem
-- estar logado em nada. Se baixar, funciona para a equipe. Foi justamente
-- esse teste que nunca foi feito com os links do Drive.
-- ----------------------------------------------------------------------------
