-- Hakuna Connect — chat: sinalizar @menção + mensagem privada entre Hakunas.
-- NÃO aplicado em produção ainda.
--
-- Apelido de @menção (ex: "Dr. Edson Barroso" -> "@Dredsonbarroso") é
-- calculado no app (Profile.mentionHandle), não precisa de coluna nova —
-- a menção sempre resolve pelo id do perfil escolhido na sugestão, então
-- uma colisão de apelido entre duas pessoas não troca o destinatário real.

-- ============ mensagens privadas (Hakuna <-> Hakuna) ============
--
-- Escopadas por Top, igual tudo mais no app — isolamento entre Tops é
-- princípio central do produto, não faz sentido abrir exceção pro DM.
create table public.direct_messages (
  id bigint generated always as identity primary key,
  top_id uuid not null references public.tops (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now(),
  read_at timestamptz,
  check (sender_id <> recipient_id)
);

create index direct_messages_thread_idx on public.direct_messages (top_id, sender_id, recipient_id, created_at);

alter table public.direct_messages enable row level security;

-- Só quem manda ou quem recebe vê a mensagem — nunca um terceiro Hakuna,
-- nem admin (privado é privado; auditoria de conteúdo de DM não é o
-- propósito de nenhuma tela do app hoje).
create policy "direct_messages_select_participant" on public.direct_messages
  for select using (sender_id = auth.uid() or recipient_id = auth.uid());

create policy "direct_messages_insert_self" on public.direct_messages
  for insert with check (
    sender_id = auth.uid()
    and exists (
      select 1 from public.top_hakunas th
      where th.top_id = direct_messages.top_id
        and th.profile_id = auth.uid()
        and th.released = true
    )
    and exists (
      select 1 from public.top_hakunas th
      where th.top_id = direct_messages.top_id
        and th.profile_id = direct_messages.recipient_id
        and th.released = true
    )
  );

create policy "direct_messages_update_mark_read" on public.direct_messages
  for update using (recipient_id = auth.uid())
  with check (recipient_id = auth.uid());

alter publication supabase_realtime add table public.direct_messages;

-- ============ fix: notifications não tinha policy de INSERT ============
--
-- A tabela public.notifications (participants_and_attendance.sql) já está
-- em produção com RLS habilitado, mas só tinha policy de SELECT e UPDATE —
-- sem policy de INSERT, todo insert client-side era bloqueado em silêncio
-- (RLS nega por padrão). Isso já afetava as notificações de atendimento
-- (attendance_detail_screen, attendance_list_screen) e bloquearia também
-- o novo "sinal" de @menção no chat. Corrigido aqui: qualquer Hakuna
-- liberado do Top pode notificar (broadcast ou outro Hakuna liberado do
-- mesmo Top).
create policy "notifications_insert_released_hakuna" on public.notifications
  for insert with check (
    exists (
      select 1 from public.top_hakunas th
      where th.top_id = notifications.top_id
        and th.profile_id = auth.uid()
        and th.released = true
    )
    and (
      recipient_id is null
      or exists (
        select 1 from public.top_hakunas th2
        where th2.top_id = notifications.top_id
          and th2.profile_id = notifications.recipient_id
          and th2.released = true
      )
    )
  );
