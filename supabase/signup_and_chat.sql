-- Hakuna Connect - Cadastro自动 de participantes + Chat interno dos Hakunas
--
-- 1) Cadastro automático: hoje só um admin consegue criar usuário manualmente no
--    dashboard do Supabase. Isso não escala para "toda a equipe de
--    Hakunas". A partir de agora, o app tem uma tela de cadastro que chama
--    auth.signUp(email, senha, data: {full_name, legendarios_number}), e
--    este trigger cria a linha em profiles automaticamente. Todo cadastro
--    novo entra como 'senderista' — um admin promove pra 'hakuna' depois.
--
-- 2) Chat interno: mensagens de texto entre os Hakunas liberados de um
--    mesmo Top, em tempo real via Supabase Realtime (mesmo mecanismo já
--    usado pra posição). Substitui a ideia de usar o Chatwoot da clínica
--    (que é uma ferramenta de atendimento a paciente, não de chat de
--    equipe — misturar os dois contextos seria errado).

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, legendarios_number, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', 'Sem nome'),
    coalesce(new.raw_user_meta_data ->> 'legendarios_number', new.id::text),
    'senderista'
  );
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create table public.top_hakuna_messages (
  id bigint generated always as identity primary key,
  top_id uuid not null references public.tops (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now()
);

create index top_hakuna_messages_top_idx
  on public.top_hakuna_messages (top_id, created_at);

alter table public.top_hakuna_messages enable row level security;

-- só hakunas liberados (ou admin) do MESMO top leem/escrevem no chat
create policy "top_hakuna_messages_select_same_top" on public.top_hakuna_messages
  for select using (
    exists (
      select 1 from public.top_hakunas hk
      where hk.top_id = top_hakuna_messages.top_id
        and hk.profile_id = auth.uid()
        and hk.released = true
    )
    or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin')
  );

create policy "top_hakuna_messages_insert_self" on public.top_hakuna_messages
  for insert with check (
    sender_id = auth.uid()
    and exists (
      select 1 from public.top_hakunas hk
      where hk.top_id = top_hakuna_messages.top_id
        and hk.profile_id = auth.uid()
        and hk.released = true
    )
  );

alter publication supabase_realtime add table public.top_hakuna_messages;
