-- Pedido de acesso carrega o NUMERO DO TOP e, quando ha, a CONTA de quem
-- pediu. 28/10/2026.
--
-- O fluxo pedido pelo dono: a pessoa manda o numero do Legendarios e o
-- numero do Top logo no comeco; o pedido chega ao admin; o admin libera e
-- a pessoa ja entra aprovada e dentro daquele Top. A aprovacao em si vale
-- para todos os Tops (a policy `tops_select_linked` ja abre todo Top nao
-- rascunho para conta aprovada).
--
-- top_number  o que a pessoa DIGITOU. Guardado mesmo quando nao existe Top
--             com esse numero: o admin precisa ver "Top 1922" para saber
--             que a pessoa errou ou que o evento ainda nao foi criado.
-- top_id      o Top resolvido pelo servidor, ou null se o numero nao bate.
-- profile_id  a conta de quem pediu, quando pediu ja logado (entrou pelo
--             Google ou por e-mail e ficou na tela de aprovacao). Com ela
--             o liberar APROVA a conta que existe, em vez de criar outra
--             ou trocar a senha de quem entra pelo Google.
--
-- Idempotente: rodar duas vezes seguidas sem erro.

alter table public.access_requests
  add column if not exists top_number text;

alter table public.access_requests
  add column if not exists top_id uuid references public.tops(id) on delete set null;

alter table public.access_requests
  add column if not exists profile_id uuid references public.profiles(id) on delete cascade;

create index if not exists access_requests_pendentes_idx
  on public.access_requests (legendarios_number)
  where status = 'pendente';

-- Conferencia:
-- select column_name from information_schema.columns
--  where table_schema = 'public' and table_name = 'access_requests'
--    and column_name in ('top_number', 'top_id', 'profile_id');
