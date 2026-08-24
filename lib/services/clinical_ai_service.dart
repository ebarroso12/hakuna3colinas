import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/clinical_ai_response.dart';
import '../models/clinical_case.dart';

/// Chama a Edge Function clinical-ai (supabase/functions/clinical-ai) —
/// que por sua vez ainda devolve uma resposta MOCK, sem chamada real à
/// OpenAI (ver comentário no início daquele arquivo). Esta função só
/// funciona depois que a Edge Function for implantada pelo administrador
/// (`supabase functions deploy clinical-ai` + segredos configurados) —
/// até lá, lança uma exceção que a tela trata com o fallback exigido pelo
/// prompt: "IA indisponível — utilize protocolo clínico local."
class ClinicalAiService {
  ClinicalAiService._();

  static final ClinicalAiService instance = ClinicalAiService._();

  Future<ClinicalAiResponse> analyzeCase(ClinicalCase clinicalCase) async {
    final response = await Supabase.instance.client.functions.invoke(
      'clinical-ai',
      body: clinicalCase.toJson(),
    );
    if (response.status != 200 || response.data == null) {
      throw StateError(
        'Hakuna Medical AI indisponível (status ${response.status}).',
      );
    }
    return ClinicalAiResponse.fromJson(response.data as Map<String, dynamic>);
  }
}
