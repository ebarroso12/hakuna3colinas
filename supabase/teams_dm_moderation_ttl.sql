-- Hakuna Connect — mensagem privada entre qualquer equipe, moderação
-- (editar/apagar) pelo admin da equipe, bloqueio de membro, alerta em
-- negrito, e apagamento automático de mensagens após 7 dias.

-- ============ mensagem privada: agora vale pra qualquer equipe ============
--
-- direct_messages (chat_mentions_and_dm.sql) só permitia DM entre Hakunas
-- liberados. Generaliza pra "está vinculado a este Top de algum jeito"
-- (Hakuna liberado, membro liberado de qualquer equipe, ou Senderista
-- inscrito) — assim o sidebar de qualquer TeamChatScreen consegue abrir
-- DM com qualquer colega do mesmo Top, não só Hakunas.
create or replace function public.is_in_top_community(p_top_id uuid, p_profile_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
  select exists (
    select 1 from public.top_hakunas h
    where h.top_id = p_top_id and h.profile_id = p_profile_id and h.released = true
  )
  or exists (
    select 1 from public.top_team_members m
    where m.top_id = p_top_id and m.profile_id = p_profile_id and m.released = true
  )
  or exists (
    select 1 from public.top_senderistas s
    where s.top_id = p_top_id and s.profile_id = p_profile_id
  );
$$;

drop policy if exists "direct_messages_insert_self" on public.direct_messages;
create policy "direct_messages_insert_self" on public.direct_messages
  for insert with check (
    sender_id = auth.uid()
    and public.is_in_top_community(top_id, sender_id)
    and public.is_in_top_community(top_id, recipient_id)
  );

-- ============ bloqueio de membro ============
--
-- "released e blocked juntos" nunca devia acontecer — trava isso a nível
-- de banco (não só via app), pra ninguém reativar um bloqueado passando
-- por fora da tela de busca.
alter table public.top_team_members add column if not exists blocked boolean not null default false;

alter table public.top_team_members drop constraint if exists top_team_members_blocked_not_released;
alter table public.top_team_members add constraint top_team_members_blocked_not_released check (not (blocked and released));

-- searchable_profiles não pode mais devolver quem já está bloqueado
-- naquela equipe — senão o admin re-adiciona sem querer.
create or replace function public.searchable_profiles(p_top_id uuid, p_team public.team_key, p_query text default '')
returns table (id uuid, full_name text, legendarios_number text)
language sql stable security definer set search_path = public
as $$
  select p.id, p.full_name, p.legendarios_number
  from public.profiles p
  where (public.is_team_admin(p_top_id, p_team) or public.is_admin())
    and p.approved = true
    and not exists (
      select 1 from public.top_team_members m
      where m.top_id = p_top_id and m.team = p_team and m.profile_id = p.id and m.blocked = true
    )
    and (p_query = '' or p.full_name ilike '%' || p_query || '%' or p.legendarios_number ilike '%' || p_query || '%')
  order by p.full_name
  limit 50;
$$;

-- ============ moderação (editar/apagar) + alerta em negrito ============
--
-- is_alert: mensagem de alerta do admin, renderizada em negrito no app.
-- edited_at: marca quando o admin editou a mensagem de alguém (moderação).
alter table public.team_messages add column if not exists is_alert boolean not null default false;
alter table public.team_messages add column if not exists edited_at timestamptz;

-- Substitui a policy de insert: além de já poder mandar mensagem, só
-- admin da equipe (ou admin global) pode marcar is_alert = true.
drop policy if exists "team_messages_insert_member" on public.team_messages;
create policy "team_messages_insert_member" on public.team_messages
  for insert with check (
    sender_id = auth.uid()
    and (
      (
        team = 'geral'
        and public.is_approved()
        and exists (select 1 from public.tops t where t.id = top_id and t.status <> 'draft')
      )
      or public.is_team_member(top_id, team)
      or public.is_team_admin(top_id, team)
      or public.is_admin()
    )
    and (is_alert = false or public.is_team_admin(top_id, team) or public.is_admin())
  );

-- Admin da equipe (ou admin global) edita/apaga qualquer mensagem da
-- própria equipe — moderação de conteúdo.
create policy "team_messages_update_admin" on public.team_messages
  for update using (public.is_team_admin(top_id, team) or public.is_admin())
  with check (public.is_team_admin(top_id, team) or public.is_admin());

create policy "team_messages_delete_admin" on public.team_messages
  for delete using (public.is_team_admin(top_id, team) or public.is_admin());

-- ============ apagamento automático após 7 dias ============
--
-- Vale pra chat de equipe (inclusive o geral) e mensagem privada. O chat
-- próprio dos Hakunas (top_hakuna_messages) não entra aqui — não foi
-- pedido, e mexer nele arrisca o que já está testado.
create extension if not exists pg_cron;

create or replace function public.cleanup_expired_messages()
returns void
language sql
security definer set search_path = public
as $$
  delete from public.team_messages where created_at < now() - interval '7 days';
  delete from public.direct_messages where created_at < now() - interval '7 days';
$$;

select cron.schedule('cleanup-expired-messages', '0 3 * * *', $$select public.cleanup_expired_messages();$$);
