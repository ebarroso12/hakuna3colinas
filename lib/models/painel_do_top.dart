import 'team.dart';

/// Linha de uma equipe no painel.
class EquipeNoPainel {
  final TeamKey? equipe;
  final String chave;
  final int membros;
  final int liberados;
  final int coordenacao;
  final int mensagens24h;

  const EquipeNoPainel({
    required this.equipe,
    required this.chave,
    required this.membros,
    required this.liberados,
    required this.coordenacao,
    required this.mensagens24h,
  });

  factory EquipeNoPainel.fromMap(Map<String, dynamic> map) => EquipeNoPainel(
    equipe: teamKeyFromString(map['equipe'] as String?),
    chave: (map['equipe'] ?? '?').toString(),
    membros: _int(map['membros']),
    liberados: _int(map['liberados']),
    coordenacao: _int(map['coordenacao']),
    mensagens24h: _int(map['mensagens_24h']),
  );

  /// Incluídos que ainda não podem usar o chat da equipe.
  int get faltaLiberar => membros - liberados;
}

/// Métricas de um Top, como devolvidas por `painel_do_top` no banco.
///
/// Só contagens. A função recusa quem não é admin no próprio banco — a
/// tela não é a fronteira.
class PainelDoTop {
  final DateTime geradoEm;

  final int fichas;
  final int fichasComConta;
  final int fichasSemNumero;
  final int fichasSemNascimento;
  final int fichasTeste;

  final int contasAguardando;
  final int pedidosPendentes;
  final int hakunasLiberados;

  final List<EquipeNoPainel> equipes;
  final int mensagens24h;
  final int mensagensTotal;
  final int chatClinico24h;

  final int atendimentos;
  final int atendimentosAbertos;
  final int atendimentos24h;
  final int pessoasComVitalCritico;
  final int afericoes;

  final int alarmes;
  final int alarmes24h;
  final String? ultimoAlarmeNome;
  final DateTime? ultimoAlarmeEm;

  final int compartilhandoPosicaoAgora;
  final int comPosicaoNaUltimaHora;

  const PainelDoTop({
    required this.geradoEm,
    required this.fichas,
    required this.fichasComConta,
    required this.fichasSemNumero,
    required this.fichasSemNascimento,
    required this.fichasTeste,
    required this.contasAguardando,
    required this.pedidosPendentes,
    required this.hakunasLiberados,
    required this.equipes,
    required this.mensagens24h,
    required this.mensagensTotal,
    required this.chatClinico24h,
    required this.atendimentos,
    required this.atendimentosAbertos,
    required this.atendimentos24h,
    required this.pessoasComVitalCritico,
    required this.afericoes,
    required this.alarmes,
    required this.alarmes24h,
    required this.ultimoAlarmeNome,
    required this.ultimoAlarmeEm,
    required this.compartilhandoPosicaoAgora,
    required this.comPosicaoNaUltimaHora,
  });

  factory PainelDoTop.fromMap(Map<String, dynamic> map) {
    final ultimo = map['ultimo_alarme'] as Map<String, dynamic>?;
    final equipes = (map['equipes'] as List<dynamic>? ?? const [])
        .map((e) => EquipeNoPainel.fromMap(e as Map<String, dynamic>))
        .toList();
    return PainelDoTop(
      geradoEm: _data(map['gerado_em']) ?? DateTime.now(),
      fichas: _int(map['fichas']),
      fichasComConta: _int(map['fichas_com_conta']),
      fichasSemNumero: _int(map['fichas_sem_numero']),
      fichasSemNascimento: _int(map['fichas_sem_nascimento']),
      fichasTeste: _int(map['fichas_teste']),
      contasAguardando: _int(map['contas_aguardando']),
      pedidosPendentes: _int(map['pedidos_pendentes']),
      hakunasLiberados: _int(map['hakunas_liberados']),
      equipes: equipes,
      mensagens24h: _int(map['mensagens_24h']),
      mensagensTotal: _int(map['mensagens_total']),
      chatClinico24h: _int(map['chat_clinico_24h']),
      atendimentos: _int(map['atendimentos']),
      atendimentosAbertos: _int(map['atendimentos_abertos']),
      atendimentos24h: _int(map['atendimentos_24h']),
      pessoasComVitalCritico: _int(map['pessoas_com_vital_critico']),
      afericoes: _int(map['afericoes']),
      alarmes: _int(map['alarmes']),
      alarmes24h: _int(map['alarmes_24h']),
      ultimoAlarmeNome: ultimo?['nome'] as String?,
      ultimoAlarmeEm: _data(ultimo?['em']),
      compartilhandoPosicaoAgora: _int(map['compartilhando_posicao_agora']),
      comPosicaoNaUltimaHora: _int(map['com_posicao_na_ultima_hora']),
    );
  }

  /// Fichas que ainda não viraram conta no app.
  int get fichasSemConta => fichas - fichasComConta;

  /// Fração das fichas com conta, de 0 a 1. Zero fichas dá zero, não erro.
  double get adesao => fichas == 0 ? 0 : fichasComConta / fichas;
}

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

DateTime? _data(Object? v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
