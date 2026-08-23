-- Aprovação obrigatória: todo cadastro novo entra como "não aprovado" e só
-- consegue usar o app depois que o admin master (ou um admin) libera. Quem
-- já estava usando o app antes desta migração é aprovado automaticamente
-- (não trava quem já estava dentro).

alter table public.profiles add column approved boolean not null default false;
update public.profiles set approved = true;
