// Hakuna Medical AI — Edge Function (IA-FASE 3, esqueleto).
//
// NÃO IMPLANTADO EM PRODUÇÃO. Existe aqui como o contrato/arquitetura
// alvo, pronto pra revisão — só quando aprovado é que roda
// `supabase functions deploy clinical-ai` (deploy fica fora do que faço
// sozinho, ver auditoria/regras de produção).
//
// Por enquanto NÃO chama a OpenAI de verdade: valida autorização médica,
// desidentifica/valida o caso recebido, "recupera" evidência (stub) e
// devolve uma resposta MOCK que já respeita o schema final — assim o
// cliente Flutter e o contrato da API podem ser testados de ponta a ponta
// antes de existir custo real de API ou uma chave pra proteger.
//
// Conectar a OpenAI de verdade (IA-FASE 3 final) = trocar só a função
// callClinicalModel() abaixo por uma chamada real, usando
// Deno.env.get("OPENAI_API_KEY") (nunca no cliente) e
// Deno.env.get("CLINICAL_AI_MODEL") (default "gpt-5.4-mini", mas
// configurável sem precisar atualizar o app).

import { createClient } from 'jsr:@supabase/supabase-js@2';

const CLINICAL_AI_MODEL = Deno.env.get('CLINICAL_AI_MODEL') ?? 'gpt-5.4-mini';
const PROMPT_VERSION = '2026-08-24-v1';

interface ClinicalCase {
  topId: string;
  attendanceId?: string;
  ageYears?: number;
  sex?: string;
  chiefComplaint: string;
  mechanismOfInjury?: string;
  onsetMinutesAgo?: number;
  vitals?: {
    systolicBp?: number;
    diastolicBp?: number;
    heartRate?: number;
    respiratoryRate?: number;
    spo2?: number;
    temperatureC?: number;
    glasgow?: number;
    glycemia?: number;
  };
  notes?: string;
  mode: 'rapida' | 'discussao';
}

interface ClinicalAiResponse {
  priority: 'CRITICA' | 'ALTA' | 'MODERADA' | 'BAIXA';
  immediateRisks: string[];
  cannotMiss: string[];
  differentialDiagnosis: { hypothesis: string; forIt: string; against: string }[];
  actionsNow: string[];
  additionalAssessment: string[];
  therapeuticOptions: string[];
  medicationConsiderations: string[];
  evacuationRecommendation: 'IMEDIATA' | 'PRIORITARIA' | 'OBSERVACAO_LOCAL' | null;
  missingInformation: string[];
  evidence: { source: string; institution: string; year: number | null; reference: string }[];
  uncertainty: string;
  isMock: boolean; // true enquanto não houver chamada real à OpenAI
}

function validateCase(body: unknown): ClinicalCase | null {
  if (typeof body !== 'object' || body === null) return null;
  const c = body as Record<string, unknown>;
  if (typeof c.topId !== 'string' || typeof c.chiefComplaint !== 'string') return null;
  if (c.mode !== 'rapida' && c.mode !== 'discussao') return null;
  return c as unknown as ClinicalCase;
}

/**
 * Stub de recuperação de evidência — na IA-FASE 2 real isso vira uma busca
 * por similaridade de embedding em clinical_evidence_documents. Por
 * enquanto devolve vazio: sem evidência real, a resposta mock deixa isso
 * explícito em vez de fingir que recuperou algo.
 */
async function retrieveEvidence(_clinicalCase: ClinicalCase): Promise<ClinicalAiResponse['evidence']> {
  return [];
}

/**
 * TROCAR AQUI quando for conectar a OpenAI de verdade. Por enquanto
 * devolve uma resposta estruturada e válida, mas claramente marcada como
 * simulação (isMock: true) — nunca uma alucinação disfarçada de resposta
 * real.
 */
async function callClinicalModel(
  clinicalCase: ClinicalCase,
  evidence: ClinicalAiResponse['evidence'],
): Promise<ClinicalAiResponse> {
  return {
    priority: 'MODERADA',
    immediateRisks: [],
    cannotMiss: [],
    differentialDiagnosis: [],
    actionsNow: [],
    additionalAssessment: [],
    therapeuticOptions: [],
    medicationConsiderations: [],
    evacuationRecommendation: null,
    missingInformation: [
      'Esta é uma resposta simulada (modo mock) — a integração real com ' +
        CLINICAL_AI_MODEL +
        ' ainda não foi conectada nesta função.',
    ],
    evidence,
    uncertainty: 'N/A — resposta mock, sem análise clínica real realizada.',
    isMock: true,
  };
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return new Response(JSON.stringify({ error: 'method_not_allowed' }), { status: 405 });
  }

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return new Response(JSON.stringify({ error: 'missing_authorization' }), { status: 401 });
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')!;
  const userClient = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) {
    return new Response(JSON.stringify({ error: 'invalid_session' }), { status: 401 });
  }

  // Só Hakuna médico (com CRM) ou admin master pode consultar a IA clínica
  // — reforçado aqui, não só na UI do Flutter.
  const { data: profile, error: profileError } = await userClient
    .from('profiles')
    .select('role, medical_registry, is_master_admin')
    .eq('id', userData.user.id)
    .single();

  if (profileError || !profile) {
    return new Response(JSON.stringify({ error: 'profile_not_found' }), { status: 403 });
  }
  const isAuthorizedMedical =
    profile.is_master_admin || profile.role === 'admin' || (profile.role === 'hakuna' && profile.medical_registry);
  if (!isAuthorizedMedical) {
    return new Response(JSON.stringify({ error: 'not_authorized_medical' }), { status: 403 });
  }

  const clinicalCase = validateCase(await req.json().catch(() => null));
  if (!clinicalCase) {
    return new Response(JSON.stringify({ error: 'invalid_case' }), { status: 400 });
  }

  const evidence = await retrieveEvidence(clinicalCase);
  const response = await callClinicalModel(clinicalCase, evidence);

  // Auditoria via service role (bypassa RLS de propósito — é a única
  // escrita autorizada nesta tabela, ver clinical_ai_schema.sql).
  const serviceClient = createClient(supabaseUrl, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  await serviceClient.from('clinical_ai_queries').insert({
    top_id: clinicalCase.topId,
    attendance_id: clinicalCase.attendanceId ?? null,
    requested_by: userData.user.id,
    model: CLINICAL_AI_MODEL,
    prompt_version: PROMPT_VERSION,
    structured_case: clinicalCase,
    response,
    evidence_used: evidence,
  });

  return new Response(JSON.stringify(response), {
    headers: { 'Content-Type': 'application/json' },
  });
});
