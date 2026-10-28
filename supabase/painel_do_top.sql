-- Painel do Top: as métricas que o admin pediu em 28/10/2026 ("o admin tem
-- de ter o controle de tudo, até métricas"), numa chamada só.
--
-- Por que uma função e não oito consultas do app: no campo o sinal é ruim,
-- e oito idas e voltas são oito chances de a tela abrir pela metade. Aqui
-- é uma requisição; ou vem tudo, ou vem o erro.
--
-- SECURITY DEFINER porque soma linhas de tabelas com RLS por pessoa
-- (atendimentos, mensagens de equipe). A guarda é a primeira linha:
-- quem não é admin recebe erro, não um painel vazio que pareceria "Top
-- sem movimento". Devolve CONTAGENS, nunca dado de pessoa — exceto o nome
-- de quem disparou o último alarme, que todo aprovado do Top já vê na
-- faixa de alarme.
--
-- Idempotente: create or replace + grant. Rodar duas vezes sem erro.

create or replace function public.painel_do_top(p_top_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  r jsonb;
begin
  if not public.is_admin() then
    raise exception 'apenas administradores' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'gerado_em', now(),

    'fichas', (select count(*) from top_participants
                where top_id = p_top_id and coalesce(is_teste, false) = false),
    'fichas_com_conta', (select count(*) from top_participants
                where top_id = p_top_id and linked_profile_id is not null
                  and coalesce(is_teste, false) = false),
    'fichas_sem_numero', (select count(*) from top_participants
                where top_id = p_top_id and participant_code is null
                  and coalesce(is_teste, false) = false),
    'fichas_sem_nascimento', (select count(*) from top_participants
                where top_id = p_top_id and birth_date is null
                  and coalesce(is_teste, false) = false),
    'fichas_teste', (select count(*) from top_participants
                where top_id = p_top_id and is_teste = true),

    'contas_aguardando', (select count(*) from profiles where approved = false),
    'pedidos_pendentes', (select count(*) from access_requests where status = 'pendente'),

    'hakunas_liberados', (select count(*) from top_hakunas
                where top_id = p_top_id and released = true),

    'equipes', coalesce((
      select jsonb_agg(jsonb_build_object(
               'equipe', team,
               'membros', membros,
               'liberados', liberados,
               'coordenacao', coordenacao,
               'mensagens_24h', mensagens_24h) order by team)
        from (
          select m.team,
                 count(*) as membros,
                 count(*) filter (where m.released and not m.blocked) as liberados,
                 count(*) filter (where m.team_role in ('coordenador', 'subcoordenador')) as coordenacao,
                 (select count(*) from team_messages t
                   where t.top_id = p_top_id and t.team = m.team
                     and t.created_at > now() - interval '24 hours') as mensagens_24h
            from top_team_members m
           where m.top_id = p_top_id
           group by m.team
        ) e), '[]'::jsonb),
    'mensagens_24h', (select count(*) from team_messages
                where top_id = p_top_id and created_at > now() - interval '24 hours'),
    'mensagens_total', (select count(*) from team_messages where top_id = p_top_id),
    'chat_clinico_24h', (select count(*) from top_hakuna_messages
                where top_id = p_top_id and created_at > now() - interval '24 hours'),

    'atendimentos', (select count(*) from atendimentos where top_id = p_top_id),
    'atendimentos_abertos', (select count(*) from atendimentos
                where top_id = p_top_id and status not in ('encerrado', 'cancelado')),
    'atendimentos_24h', (select count(*) from atendimentos
                where top_id = p_top_id and opened_at > now() - interval '24 hours'),
    -- Mesmos limiares de TriageDinamica: SpO2 < 90, PA > 180 x 110.
    'pessoas_com_vital_critico', (select count(distinct participant_id) from atendimentos
                where top_id = p_top_id
                  and (spo2 < 90 or systolic_bp > 180 or diastolic_bp > 110)),
    'afericoes', (select count(*) from vital_signs where top_id = p_top_id),

    'alarmes', (select count(*) from top_alerts where top_id = p_top_id),
    'alarmes_24h', (select count(*) from top_alerts
                where top_id = p_top_id and created_at > now() - interval '24 hours'),
    'ultimo_alarme', (select jsonb_build_object('nome', sender_name, 'em', created_at,
                                                'mensagem', message)
                        from top_alerts where top_id = p_top_id
                       order by created_at desc limit 1),

    'compartilhando_posicao_agora', (select count(distinct profile_id) from hakuna_positions
                where top_id = p_top_id and recorded_at > now() - interval '15 minutes'),
    'com_posicao_na_ultima_hora', (select count(distinct profile_id) from hakuna_positions
                where top_id = p_top_id and recorded_at > now() - interval '1 hour')
  ) into r;

  return r;
end;
$$;

revoke all on function public.painel_do_top(uuid) from public, anon;
grant execute on function public.painel_do_top(uuid) to authenticated;

-- Conferencia (como admin no SQL Editor, com service_role is_admin() e
-- falso — rode pelo app, ou troque o papel com set local role):
-- select public.painel_do_top('<top_id>');
