-- ===========================================================================
-- `tops.aceitar_fora_da_lista` — O TOP SEM LISTA PRÉVIA
--
-- Decisão de 23/11/2026. O Top "TRACK 3 Colinas 1 ano" começa com a lista
-- de participantes VAZIA: a lista dos 216 do Top anterior vivia só na
-- tabela do projeto Supabase que foi apagado, e não existe em lugar
-- nenhum que o app alcance — conferido no repositório, em todo commit do
-- histórico, nas transcrições das sessões e no DNS do projeto antigo
-- (NXDOMAIN, apagado e não pausado).
--
-- Sem isto, o autocadastro é inútil num Top novo: `participante_elegivel`
-- exige o número **na lista do Top**, então 216 pessoas digitariam a senha
-- certa e receberiam "número ou senha do Top incorretos" — que soa como
-- senha errada e manda todas ligarem para o admin.
--
-- Com o interruptor ligado, quem tem a senha do Top se cadastra mesmo sem
-- ficha, e **a ficha é criada a partir do que a pessoa digita**: nome,
-- família, nascimento, comorbidade, alergia, contato de emergência. Ou
-- seja, o autocadastro deixa de depender da lista e passa a ser **o jeito
-- de construir a lista** — feita pelas próprias pessoas, que são as que
-- sabem os dados.
--
-- ---------------------------------------------------------------------------
-- O QUE SE PERDE, DITO SEM ENFEITE
--
-- A lista era a segunda tranca. O comentário de `validarConvite` diz:
-- *"Só a senha não basta: ela é compartilhada, então quem a recebesse de
-- fora do grupo..."*. Com o interruptor ligado, **a senha passa a bastar**:
-- quem tiver a senha entra, com qualquer número.
--
-- O risco concreto: alguém de fora que receba a senha repassada cria uma
-- conta aprovada, vê o Top, lê o chat geral e **pode disparar alarme**. Não
-- alcança prontuário (cerca própria, `top_hakunas`) nem a posição dos
-- outros (`pode_ver_mapa`).
--
-- Por isso o padrão é `false` e o interruptor é **por Top**: um Top com
-- lista pronta continua exigindo a lista. E por isso ele é do admin
-- MASTER, igual à senha — quem decide quem entra no evento é quem responde
-- por ele.
--
-- Mitigação que já existe e continua valendo: depois que a equipe entrou,
-- fechar `autocadastro_liberado`. A senha continua circulando no WhatsApp
-- para sempre; o interruptor é o que tira o valor dela.
--
-- ---------------------------------------------------------------------------
-- A FICHA CRIADA ASSIM FICA MARCADA
--
-- `top_participants.notes` recebe "ficha criada no autocadastro". Não é
-- enfeite: a tela de participantes mostra `notes`, e o admin precisa
-- distinguir a ficha que veio da lista oficial da que a própria pessoa
-- digitou — se um dia a lista real aparecer, é por aí que ele confere. O
-- importador já desmarca duplicata por número e por nome, então reimportar
-- depois não cria ficha dobrada.
--
-- `registered_by` recebe o **id da própria pessoa**: foi ela quem
-- cadastrou. A coluna é `not null` e referencia `profiles`, e nesse ponto
-- do fluxo a conta já existe.
-- ===========================================================================

alter table public.tops
  add column if not exists aceitar_fora_da_lista boolean not null default false;

comment on column public.tops.aceitar_fora_da_lista is
  'Permite autocadastro de numero que NAO esta na lista do Top; a ficha e '
  'criada com o que a pessoa digita. Existe para Top sem lista previa. '
  'Com isto ligado a SENHA DO TOP PASSA A BASTAR — a lista era a segunda '
  'tranca. Padrao false, por Top, e so o admin master muda.';

-- ---------------------------------------------------------------------------
-- A MESMA TRAVA DA SENHA PROTEGE ESTE INTERRUPTOR
--
-- Ligar isto é afrouxar quem entra no Top, então vale a regra de
-- `07_senha_do_top_so_o_master.sql`: só o admin master. A função é
-- substituída inteira (é `create or replace`) para a trava ficar num lugar
-- só — duas travas separadas sobre a mesma tabela divergem.
-- ---------------------------------------------------------------------------
create or replace function public.tops_trava_senha_do_top()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $fn$
begin
  -- `service_role`: a Edge Function `acesso`, que ja conferiu o master.
  if auth.uid() is null then
    return new;
  end if;

  -- "os admin master terao todo acesso".
  if public.is_master_admin() then
    return new;
  end if;

  -- Admin comum (e qualquer outro) nao mexe na senha. Em silencio, porque
  -- um `update` de rotina do Top pode mandar a linha inteira e recusar
  -- quebraria a edicao de nome, local e datas.
  new.access_code_hash   := old.access_code_hash;
  new.access_code_set_at := old.access_code_set_at;
  new.access_code_set_by := old.access_code_set_by;

  -- Fechar o cadastro pode. Abrir, nao — e com erro, nao calado.
  if coalesce(new.autocadastro_liberado, false)
     and not coalesce(old.autocadastro_liberado, false) then
    raise exception
      'so o admin master abre o cadastro de um Top'
      using errcode = '42501';
  end if;

  -- LIGAR "aceitar fora da lista" e afrouxar quem entra: so o master.
  -- DESLIGAR pode, pela mesma razao de fechar o cadastro — e o lado seguro.
  if coalesce(new.aceitar_fora_da_lista, false)
     and not coalesce(old.aceitar_fora_da_lista, false) then
    raise exception
      'so o admin master aceita cadastro fora da lista do Top'
      using errcode = '42501';
  end if;

  return new;
end;
$fn$;

drop trigger if exists tops_trava_senha on public.tops;

create trigger tops_trava_senha
  before update on public.tops
  for each row execute function public.tops_trava_senha_do_top();

-- Conferência:
--   select name, autocadastro_liberado, aceitar_fora_da_lista from public.tops;
--   -- como admin COMUM, os dois devem dar 42501 ao LIGAR, e passar ao desligar.
