import '../models/afericao.dart';
import '../models/triage_rule.dart';

/// Limiares de reclassificação. Em constantes nomeadas para aparecerem no
/// teste e na tela com o mesmo valor que a regra usa.
///
/// Vindos da especificação do usuário (09/10/2026). Registro uma ressalva
/// técnica: a diretriz brasileira de crise hipertensiva costuma usar
/// **180/120**, não 180/110 — o valor aqui é mais sensível, o que gera mais
/// vermelho do que o protocolo padrão. Num app de trilha isso é o erro do
/// lado certo, mas é escolha, não consenso clínico.
abstract final class LimiaresVitais {
  /// SpO₂ **abaixo** disto é vermelho. 90% é o ponto onde a curva de
  /// dissociação da hemoglobina despenca.
  static const spo2Critico = 90;

  /// Sistólica **acima** disto é vermelho.
  static const sistolicaCritica = 180;

  /// Diastólica **acima** disto é vermelho.
  static const diastolicaCritica = 110;

  /// SpO₂ só é fisiologicamente plausível a partir daqui. Abaixo disso o
  /// oxímetro não está lendo — não é um paciente a 3%.
  static const spo2Implausivel = 50;
}

/// Gravidade final de um participante: a cor que a tela deve mostrar, com
/// o rastro de por que ela é essa.
///
/// Carrega [corDeCadastro] junto de propósito. A cor estática não é
/// descartada quando a aferição escala — ela é o que volta a valer quando
/// uma medida nova e normal chegar, e é o que explica ao Hakuna a diferença
/// entre "é idoso com comorbidade" e "está com SpO₂ 88% agora".
class Gravidade {
  final TriageColor? cor;
  final TriageColor? corDeCadastro;

  /// Vazia quando a cor é a do cadastro. Cada motivo é texto pronto para a
  /// tela: "SpO₂ 88%", "PA 190 x 120".
  final List<String> motivos;

  const Gravidade({
    required this.cor,
    required this.corDeCadastro,
    this.motivos = const [],
  });

  /// A aferição puxou a cor para cima do que o cadastro dizia.
  bool get escalada => motivos.isNotEmpty;
}

/// Reclassifica gravidade a partir dos sinais vitais aferidos em campo.
///
/// **O problema que resolve:** a cor vinha de `f(idade, comorbidades)`,
/// fixada no cadastro. Um participante com PA 190x120 e SpO₂ 88% continuava
/// **verde** na lista. O dado estava gravado em coluna e nunca era lido de
/// volta — pior que não ter cor, porque transmitia confiança indevida a
/// quem decide quem atender primeiro.
///
/// **Só escala, nunca rebaixa.** Uma aferição normal não transforma em
/// verde quem o cadastro diz que é vermelho: idade e comorbidade não
/// desaparecem porque a pressão deu 120x80 numa medição. O inverso seria
/// uma porta para rebaixar alguém grave com uma aferição de sorte.
///
/// **Não grava sobre o cadastro.** O usuário pediu "substituir o dado
/// estático"; o que faço é sobrepor na leitura, não sobrescrever a coluna.
/// Sobrescrever perderia a classificação de base de forma irreversível e
/// faria a cor depender da ordem em que os atendimentos sincronizaram.
/// O efeito visível é o mesmo; o dado continua reconstruível.
abstract final class TriageDinamica {
  /// Combina a cor de cadastro com a última aferição.
  ///
  /// [corDeCadastro] vem de `TriageService.colorForParticipant`. Null
  /// (sem data de nascimento, nenhuma regra batendo) **não impede** a
  /// escalada: SpO₂ 85% é vermelho mesmo em alguém sem ficha completa.
  static Gravidade avaliar({
    required TriageColor? corDeCadastro,
    Afericao? afericao,
  }) {
    if (afericao == null || afericao.vazia) {
      return Gravidade(cor: corDeCadastro, corDeCadastro: corDeCadastro);
    }

    final motivos = <String>[];

    final spo2 = afericao.spo2;
    if (spo2 != null) {
      if (spo2 < LimiaresVitais.spo2Implausivel) {
        // Escala em vez de ignorar: um oxímetro devolvendo 3% é um
        // equipamento que falhou num paciente que alguém achou que
        // precisava de oxímetro. Silenciar isso pintaria de verde quem
        // ninguém mediu de verdade.
        motivos.add('SpO₂ $spo2% — implausível, reaferir');
      } else if (spo2 < LimiaresVitais.spo2Critico) {
        motivos.add('SpO₂ $spo2%');
      }
    }

    final pas = afericao.systolicBp;
    final pad = afericao.diastolicBp;
    final pasCritica = pas != null && pas > LimiaresVitais.sistolicaCritica;
    final padCritica = pad != null && pad > LimiaresVitais.diastolicaCritica;
    if (pasCritica || padCritica) {
      // Uma linha só mesmo quando as duas estouram: o Hakuna lê "PA 190 x
      // 120", não dois alertas sobre a mesma medida.
      motivos.add('PA ${pas ?? '?'} x ${pad ?? '?'}');
    }

    if (motivos.isEmpty) {
      return Gravidade(cor: corDeCadastro, corDeCadastro: corDeCadastro);
    }

    return Gravidade(
      cor: TriageColor.red,
      corDeCadastro: corDeCadastro,
      motivos: motivos,
    );
  }

  /// Um valor isolado justifica vermelho? Serve ao formulário de
  /// atendimento para avisar **na hora da digitação**, antes de salvar.
  static bool valorCritico({int? spo2, int? sistolica, int? diastolica}) {
    return avaliar(
      corDeCadastro: null,
      afericao: Afericao(
        medidoEm: DateTime.now(),
        spo2: spo2,
        systolicBp: sistolica,
        diastolicBp: diastolica,
      ),
    ).escalada;
  }
}
