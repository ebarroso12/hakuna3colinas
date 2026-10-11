-- ===========================================================================
-- POR QUE NENHUM EMBLEMA NUNCA SUBIU
--
-- Achado em 11/10/2026, depois de três tentativas falhadas de subir a
-- logomarca do Top.
--
-- O bucket `emblemas` tinha policy de INSERT, de UPDATE e de DELETE — e
-- NENHUMA de SELECT. Com RLS ligado, ausência de policy não é "leitura
-- aberta": é leitura NEGADA para todo mundo, inclusive para o admin que é
-- dono do arquivo.
--
-- O efeito prático: `AdminService.uploadEmblema` e `enviarImagemDoTop`
-- usam `FileOptions(upsert: true)`, e o Storage procura o objeto antes de
-- gravar. A busca batia na ausência de policy de SELECT, e a API
-- respondia:
--
--     403  "new row violates row-level security policy"
--
-- A mensagem é enganosa. Parece permissão de ESCRITA e era de LEITURA — e
-- foi por isso que o diagnóstico demorou. O INSERT em si sempre passou:
-- conferido com transação simulada (`set local role authenticated` +
-- `request.jwt.claims` do admin), revertida com rollback. O que falhou foi
-- o SELECT que vem antes dele.
--
-- A prova que fechou o caso: criar a linha com papel privilegiado e depois
-- tentar lê-la como o admin logado devolve ZERO.
--
-- ---------------------------------------------------------------------------
-- POR QUE LIBERAR A LEITURA AQUI É SEGURO
--
-- `emblemas` é `public = true`. Os arquivos já são baixáveis por URL
-- pública, sem token nenhum — é assim que `AdminService.urlEmblema`
-- funciona e é assim que a logo aparece para quem abre a lista de Tops.
-- Negar a leitura da LINHA não protegia arquivo nenhum; só impedia o
-- próprio app de trabalhar.
--
-- O bucket `atendimentos` é outra história: `public = false`, guarda foto
-- de ferida, e tem policy de SELECT própria restrita a Hakuna liberado.
-- Esta mudança NÃO o toca. Confira depois de aplicar:
--
--     select id, public from storage.buckets;
--     select policyname, cmd from pg_policies
--      where schemaname='storage' and tablename='objects';
--
-- `atendimentos` tem de continuar com `public = false` e com
-- `atendimentos_hakuna_le`.
-- ===========================================================================

drop policy if exists emblemas_leitura on storage.objects;

create policy emblemas_leitura
  on storage.objects for select
  using (bucket_id = 'emblemas');

-- Depois de aplicar, a conferência é subir a logo pelo app. Para checar
-- pelo banco:
--
--     select bucket_id, name, metadata->>'size' as bytes
--       from storage.objects where bucket_id = 'emblemas';
--     select name, emblema_path from tops;
--
-- `emblema_path` é preenchido pelo próprio `uploadEmblema` logo depois do
-- upload. Se o arquivo aparecer e o `emblema_path` ficar nulo, o upload
-- funcionou e o update da tabela falhou — são dois passos.
