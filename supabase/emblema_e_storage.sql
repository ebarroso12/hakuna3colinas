-- ============================================================================
-- Aplicado em producao (projeto jitfbambhmfnqiatwoud) em 09/10/2026.
--
-- Emblema da pista do Top + os dois buckets de Storage.
-- ============================================================================

-- Guarda o CAMINHO no Storage, nao a imagem: blob em coluna faria a
-- listagem de Tops baixar megabytes a toa.
alter table public.tops
  add column if not exists emblema_path text;


-- ----------------------------------------------------------------------------
-- Buckets com niveis OPOSTOS de acesso, de proposito.
-- ----------------------------------------------------------------------------

-- Emblema aparece na lista de Tops: publico pra leitura evita ter que
-- assinar URL a cada item da lista.
insert into storage.buckets (id, name, public, file_size_limit)
values ('emblemas', 'emblemas', true, 5242880)
on conflict (id) do nothing;

-- Foto de paciente e de ferida e DADO CLINICO. Bucket privado - se fosse
-- publico, qualquer um com a URL veria foto de paciente.
insert into storage.buckets (id, name, public, file_size_limit)
values ('atendimentos', 'atendimentos', false, 10485760)
on conflict (id) do nothing;


-- EMBLEMAS: qualquer um le (bucket publico), so admin escreve.
create policy "emblemas_admin_escreve" on storage.objects
for insert to authenticated
with check (bucket_id = 'emblemas' and public.is_admin());

create policy "emblemas_admin_atualiza" on storage.objects
for update to authenticated
using (bucket_id = 'emblemas' and public.is_admin());

create policy "emblemas_admin_apaga" on storage.objects
for delete to authenticated
using (bucket_id = 'emblemas' and public.is_admin());


-- ATENDIMENTOS: so quem esta logado E e Hakuna liberado em algum Top, ou
-- admin. SEM policy de DELETE: foto de atendimento e registro clinico,
-- nao se apaga - mesma regra da tabela atendimento_fotos.
create policy "atendimentos_hakuna_le" on storage.objects
for select to authenticated
using (
  bucket_id = 'atendimentos'
  and (
    public.is_admin()
    or exists (
      select 1 from public.top_hakunas h
      where h.profile_id = auth.uid() and h.released = true
    )
  )
);

create policy "atendimentos_hakuna_escreve" on storage.objects
for insert to authenticated
with check (
  bucket_id = 'atendimentos'
  and (
    public.is_admin()
    or exists (
      select 1 from public.top_hakunas h
      where h.profile_id = auth.uid() and h.released = true
    )
  )
);
