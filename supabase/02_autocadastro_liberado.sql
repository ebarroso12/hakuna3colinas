-- ===========================================================================
-- `tops.autocadastro_liberado` — A SÉTIMA PEÇA QUE SÓ EXISTIA EM PRODUÇÃO
--
-- Achada em 23/11/2026, reconstruindo o banco do zero. A coluna não aparece
-- em NENHUM dos 35 arquivos SQL do repositório — conferido por busca — e a
-- Edge Function `acesso` a consulta em `validarConvite`:
--
--     .select('id, name, status, autocadastro_liberado')
--     ...
--     if (top.autocadastro_liberado !== true) { ... recusa ... }
--
-- Sem a coluna, o `select` falha com 42703 e **o autocadastro inteiro para**:
-- ninguém consegue entrar no Top por número + senha. Com 216 pessoas para
-- cadastrar e o evento a 3 dias, é a diferença entre o app servir e não
-- servir.
--
-- Essa foi a sétima: `top_participants`, `team_messages`, `top_team_members`,
-- `audit_log`, bucket `emblemas`, `is_approved()` e agora esta. O padrão é
-- sempre o mesmo — objeto criado à mão em produção, nunca versionado, e que
-- ninguém sente falta até reconstruir.
--
-- ---------------------------------------------------------------------------
-- POR QUE O PADRÃO É `false`
--
-- A senha do Top é COMPARTILHADA e anunciada ao grupo: circula em WhatsApp,
-- cartaz e voz. Depois que a equipe se cadastrou ela continua valendo, e não
-- deveria — este interruptor fecha a porta sem precisar gerar senha nova.
--
-- Nascer `false` significa que um Top novo não aceita cadastro até o admin
-- abrir. É o lado seguro: porta fechada por engano alguém reclama e resolve
-- em um clique; porta aberta por engano ninguém percebe, e quem tiver a
-- senha entra com o número de outro Legendário.
-- ===========================================================================

alter table public.tops
  add column if not exists autocadastro_liberado boolean not null default false;

comment on column public.tops.autocadastro_liberado is
  'Interruptor do autocadastro. A senha do Top e compartilhada e continua '
  'valendo depois que todos se cadastraram; isto fecha a porta sem gerar '
  'senha nova. Conferido por `validarConvite` na Edge Function `acesso`.';

-- Conferência:
--   select name, status, autocadastro_liberado from public.tops;
