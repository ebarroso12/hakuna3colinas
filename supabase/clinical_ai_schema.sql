-- Hakuna Medical AI — IA-FASE 2 (base de evidência) + IA-FASE 3 (schema de
-- consulta clínica). NÃO aplicado em produção ainda — ver auditoria.
--
-- Pré-requisito: extensão "vector" (pgvector) habilitada no projeto — vem
-- disponível no Supabase, mas precisa ser ativada uma vez:
--   create extension if not exists vector;
-- Isso NÃO é feito automaticamente por este arquivo (é uma alteração de
-- infraestrutura do projeto, mais apropriado revisar antes de rodar).

-- ============ base de evidência (RAG) ============
--
-- Cada linha é um TRECHO (chunk) de um documento clínico já validado pelo
-- processo INGESTÃO -> VALIDAÇÃO -> INDEXAÇÃO -> PUBLICAÇÃO do prompt —
-- nunca inserido direto por scraping automático. embedding é preenchido
-- pela Edge Function de ingestão (fora do escopo desta migração: aqui só
-- a estrutura, sem pipeline de ingestão real ainda).
create table public.clinical_evidence_documents (
  id uuid primary key default gen_random_uuid(),
  source text not null, -- 'pubmed' | 'ms_pcdt' | 'cfm' | 'sociedade_medica' | outro
  institution text,
  title text not null,
  authors text,
  publication_year int,
  document_version text,
  reference_url text,
  doi text,
  pmid text,
  evidence_level text, -- 'protocolo_oficial' | 'guideline' | 'revisao_sistematica' | 'ensaio_clinico' | 'observacional' | 'opiniao'
  specialty text,
  chunk_index int not null default 0,
  chunk_text text not null,
  embedding vector(1536), -- dimensão do modelo de embedding a definir na IA-FASE 2 real
  indexed_at timestamptz not null default now(),
  last_verified_at timestamptz,
  superseded_by uuid references public.clinical_evidence_documents (id) on delete set null,
  active boolean not null default true
);

create index clinical_evidence_documents_source_idx on public.clinical_evidence_documents (source, active);
-- Índice vetorial fica pra quando o pipeline de ingestão real existir e
-- houver volume de dados — criar cedo demais sem dados reais não ajuda.

alter table public.clinical_evidence_documents enable row level security;

-- Só Hakunas médicos (role hakuna/admin com CRM preenchido) e admin master
-- podem consultar a base de evidência — não é dado público do app.
create policy "clinical_evidence_select_medical_hakuna" on public.clinical_evidence_documents
  for select using (
    exists (
      select 1 from public.profiles p
      where p.id = auth.uid()
        and (p.role = 'admin' or (p.role = 'hakuna' and p.medical_registry is not null))
    )
  );

-- Ingestão/edição só pelo admin master — curadoria manual, nunca automática.
create policy "clinical_evidence_write_master_admin" on public.clinical_evidence_documents
  for all using (public.is_master_admin()) with check (public.is_master_admin());

-- ============ consultas clínicas (auditoria da IA) ============
--
-- Registra CADA consulta à IA médica, sem guardar dado identificável do
-- participante (ver desidentificação na arquitetura) — só o caso clínico
-- estruturado (idade, não data de nascimento; sem nome/CPF/telefone).
create table public.clinical_ai_queries (
  id uuid primary key default gen_random_uuid(),
  top_id uuid not null references public.tops (id) on delete cascade,
  attendance_id uuid references public.atendimentos (id) on delete set null,
  requested_by uuid not null references public.profiles (id),
  model text not null, -- valor de CLINICAL_AI_MODEL usado nesta consulta específica
  prompt_version text not null,
  structured_case jsonb not null, -- caso clínico desidentificado enviado
  response jsonb, -- resposta estruturada recebida (schema da IA-FASE 3)
  evidence_used jsonb, -- ids/fontes de clinical_evidence_documents recuperados
  reviewed_by_physician boolean not null default false,
  physician_decision text, -- o que o médico decidiu, se registrado
  feedback text check (feedback in ('util', 'incorreto', 'perigoso')),
  created_at timestamptz not null default now()
);

create index clinical_ai_queries_top_idx on public.clinical_ai_queries (top_id, created_at desc);

alter table public.clinical_ai_queries enable row level security;

-- Cada médico só vê as próprias consultas; admin vê todas (auditoria).
create policy "clinical_ai_queries_select_own_or_admin" on public.clinical_ai_queries
  for select using (requested_by = auth.uid() or public.is_admin());

-- Inserção só pela Edge Function (service role) — não pelo cliente
-- diretamente, pra garantir que toda consulta passou pela validação de
-- autorização médica antes de ser registrada. Sem policy de insert pro
-- role authenticated: a service role do Supabase ignora RLS por padrão.

create policy "clinical_ai_queries_update_own_feedback" on public.clinical_ai_queries
  for update using (requested_by = auth.uid())
  with check (requested_by = auth.uid());
