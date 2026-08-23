-- Adiciona peso (opcional) ao perfil, usado só para estimar gasto
-- calórico na trilha (distância/velocidade/calorias são calculados
-- localmente no app a partir do GPS já salvo em hakuna_positions —
-- nenhuma API do Google é usada aqui).

alter table public.profiles add column weight_kg numeric;

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, legendarios_number, role, weight_kg)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', 'Sem nome'),
    coalesce(new.raw_user_meta_data ->> 'legendarios_number', new.id::text),
    'senderista',
    nullif(new.raw_user_meta_data ->> 'weight_kg', '')::numeric
  );
  return new;
end;
$$;
