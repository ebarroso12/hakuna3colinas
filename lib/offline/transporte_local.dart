library;

// Troca de mensagens entre aparelhos próximos, **sem rede nenhuma**.
//
// ## Por que existe
//
// Na trilha não há operadora. O app já grava tudo na fila e sobe depois,
// mas isso não ajuda quem precisa da informação AGORA e está a vinte
// metros de quem a escreveu.
//
// ## A ideia que faz isto funcionar sem mexer na RLS
//
// Eu havia concluído, em `docs/comunicacao_sem_rede.md`, que o obstáculo
// era a RLS (`sender_id = auth.uid()`). **Só é obstáculo se um aparelho
// tentar SUBIR a mensagem do outro.**
//
// Aqui a mensagem viaja de celular a celular **apenas para ser vista**.
// Cada pessoa sobe as próprias mensagens quando tiver rede, e o
// `client_id` impede duplicata quando as duas sincronizarem. Nenhuma
// mudança de policy, nenhuma Edge Function, nenhum payload assinado.
//
// ## O rádio é PLUGÁVEL de propósito
//
// [TransporteLocal] é interface, e esta biblioteca não importa plugin
// nenhum. Três razões concretas:
//
// 1. `nearby_connections` é **Android-only** e estava 19 meses sem
//    publicar quando isto foi escrito (12/10/2026). Amarrar o app a ele
//    seria herdar o risco dele.
// 2. O mesmo protocolo serve a **LoRa**: muda o alcance e o tamanho do
//    pacote, não a regra de quem aceita o quê.
// 3. O que decide se isto é seguro e correto — dedupe, validação,
//    confiança — fica **testável sem hardware**. O rádio não.
//
// ## O RISCO QUE NÃO SE PODE ESCONDER
//
// Mensagem que chega por rádio local **não tem autenticação**. Qualquer
// aparelho ao alcance pode afirmar "fulano disse X". No servidor isso é
// impossível (a RLS prende a autoria); aqui, não.
//
// Numa emergência isso é grave: "o coordenador mandou todos descerem"
// forjado move 200 pessoas. Por isso toda mensagem recebida por aqui é
// marcada [PacoteLocal.confirmada] = false e a tela **tem de** mostrar
// isso. Ela vale como aviso, não como ordem, até chegar pelo servidor.
//
// Esconder essa diferença seria pior que não ter a funcionalidade.


import 'dart:convert';

import '../models/team.dart';

/// Um rádio qualquer que leve bytes a quem está perto.
///
/// Implementações possíveis: Nearby Connections (BLE + WiFi Direct),
/// WiFi Direct puro, um nó LoRa por USB-C. Nenhuma delas pertence a esta
/// biblioteca — é isso que a mantém testável.
abstract interface class TransporteLocal {
  /// Começa a anunciar e a procurar aparelhos próximos.
  Future<void> ligar({required String meuNome});

  /// Para tudo e libera o rádio. Rádio ligado consome bateria, e na
  /// trilha bateria é recurso clínico.
  Future<void> desligar();

  /// Manda para **todos** ao alcance. É broadcast por desenho: numa
  /// emergência não se escolhe destinatário.
  Future<void> enviar(List<int> bytes);

  /// O que chega dos outros, cru.
  Stream<List<int>> get recebidos;

  /// Quantos aparelhos estão ao alcance agora. A tela mostra isso: saber
  /// que não há ninguém por perto é informação, não falha.
  Stream<int> get vizinhos;
}

/// Uma mensagem no formato que viaja entre aparelhos.
///
/// JSON e não binário: o canal aqui é BLE/WiFi Direct, onde sobra banda,
/// e texto legível é depurável em campo com um `print`. **Se um dia isto
/// for para LoRa** — 1 a 5 kbps — este formato não serve e tem de virar
/// binário compacto; está anotado em
/// `docs/voz_e_texto_simultaneos_sem_rede.md`.
class PacoteLocal {
  const PacoteLocal({
    required this.clientId,
    required this.topId,
    required this.team,
    required this.autorId,
    required this.autorNome,
    required this.corpo,
    required this.criadaEm,
    this.confirmada = false,
    this.saltos = 0,
  });

  /// Identidade da mensagem, gerada no aparelho de origem.
  ///
  /// É a mesma chave que a fila e o Postgres usam, e é ela que impede a
  /// mesma mensagem de aparecer duas vezes quando chega por dois
  /// caminhos — pelo rádio e, depois, pelo servidor.
  final String clientId;

  final String topId;

  /// Null = chat geral do Top.
  final TeamKey? team;

  final String autorId;

  /// Nome de quem escreveu, **no momento em que escreveu**.
  ///
  /// Viaja junto pelo mesmo motivo de `top_alerts.sender_name`: `profiles`
  /// é fechada para quem recebe, e sem rede não há como resolver uuid em
  /// nome. Um uuid na tela não ajuda ninguém a achar a pessoa.
  final String autorNome;

  final String corpo;
  final DateTime criadaEm;

  /// **Falso para tudo que chegou por rádio local.**
  ///
  /// Só o servidor confirma autoria. Ver o aviso no topo desta biblioteca:
  /// a tela tem de distinguir, porque sem autenticação qualquer aparelho
  /// pode afirmar o que quiser em nome de qualquer um.
  final bool confirmada;

  /// Quantos aparelhos já repassaram esta mensagem.
  ///
  /// Serve de freio: sem limite, três aparelhos ao alcance um do outro
  /// repassam o mesmo pacote para sempre, e a malha derrete a bateria de
  /// todo mundo com uma mensagem só.
  final int saltos;

  Map<String, Object?> paraMapa() => {
    'v': 1,
    'client_id': clientId,
    'top_id': topId,
    'team': team?.name,
    'autor_id': autorId,
    'autor_nome': autorNome,
    'corpo': corpo,
    'criada_em': criadaEm.toUtc().toIso8601String(),
    'saltos': saltos,
  };

  List<int> paraBytes() => utf8.encode(jsonEncode(paraMapa()));

  /// Lê o que chegou do rádio. **Devolve null em vez de lançar.**
  ///
  /// O que entra aqui é byte de origem desconhecida: pacote cortado,
  /// outro app no mesmo canal, ou alguém testando o que acontece. Lançar
  /// exceção derrubaria o stream de recepção e calaria o rádio inteiro
  /// por causa de um pacote ruim — exatamente o que não pode acontecer
  /// numa emergência.
  static PacoteLocal? deBytes(List<int> bytes) {
    try {
      final mapa = jsonDecode(utf8.decode(bytes));
      if (mapa is! Map) return null;

      // Versão do formato. Aparelho com app mais novo falando com um mais
      // velho é o caso normal numa equipe, e descartar o que não se
      // entende é melhor que interpretar errado.
      if (mapa['v'] != 1) return null;

      final clientId = mapa['client_id'];
      final topId = mapa['top_id'];
      final autorId = mapa['autor_id'];
      final corpo = mapa['corpo'];
      final criadaEm = mapa['criada_em'];
      if (clientId is! String || clientId.isEmpty) return null;
      if (topId is! String || topId.isEmpty) return null;
      if (autorId is! String || autorId.isEmpty) return null;
      if (corpo is! String || corpo.isEmpty) return null;
      if (criadaEm is! String) return null;

      final quando = DateTime.tryParse(criadaEm);
      if (quando == null) return null;

      final nome = mapa['autor_nome'];
      final saltos = mapa['saltos'];

      return PacoteLocal(
        clientId: clientId,
        topId: topId,
        team: teamKeyFromString(mapa['team'] as String?),
        autorId: autorId,
        autorNome: (nome is String && nome.trim().isNotEmpty)
            ? nome.trim()
            // Mesma regra do alarme: nunca mostrar uuid. "Alguém" é
            // verdade; um uuid ocupa a linha do nome e não ajuda.
            : 'Alguém do Top',
        corpo: corpo,
        criadaEm: quando.toUtc(),
        confirmada: false,
        saltos: saltos is int ? saltos : 0,
      );
    } catch (_) {
      return null;
    }
  }

  PacoteLocal maisUmSalto() => PacoteLocal(
    clientId: clientId,
    topId: topId,
    team: team,
    autorId: autorId,
    autorNome: autorNome,
    corpo: corpo,
    criadaEm: criadaEm,
    confirmada: confirmada,
    saltos: saltos + 1,
  );
}

/// O que fazer com cada pacote que chega.
///
/// Toda a regra mora aqui, longe do rádio, porque é ela que decide se a
/// malha funciona ou derrete a bateria da equipe. Função pura: entra
/// pacote e estado, sai decisão — e por isso dá para provar sem dois
/// aparelhos na mão.
enum Decisao {
  /// Guardar e mostrar. Primeira vez que se vê este `client_id`.
  aceitar,

  /// Já foi visto. Não guarda, não repassa.
  jaVisto,

  /// Mensagem de outro Top. Não é minha.
  deOutroTop,

  /// Velha demais para ser repassada.
  velhaDemais,

  /// Deu voltas demais na malha.
  saltosDemais,

  /// Pacote ilegível ou de versão desconhecida.
  invalido,
}

/// Decide o que aceitar e o que repassar.
///
/// Guarda os `client_id` já vistos em memória: a malha pode entregar o
/// mesmo pacote por três caminhos, e sem isto a tela piscaria a mesma
/// mensagem três vezes e o aparelho a repassaria três vezes.
class RegrasDaMalha {
  RegrasDaMalha({
    required this.meuTopId,
    this.idadeMaxima = const Duration(hours: 6),
    this.saltosMaximos = 5,
    this.lembrarNoMaximo = 2000,
  });

  final String meuTopId;

  /// Mensagem mais velha que isto não se repassa.
  ///
  /// Seis horas: cobre um turno inteiro, que é o que alguém chegando ao
  /// acampamento precisa recuperar. Mais que isso seria a malha
  /// reencenando o dia anterior toda vez que dois aparelhos se encontram.
  final Duration idadeMaxima;

  /// Teto de repasses. Sem ele, três aparelhos ao alcance mútuo repassam
  /// o mesmo pacote indefinidamente — e a bateria de todos acaba por
  /// causa de uma mensagem.
  final int saltosMaximos;

  /// Quantos ids lembrar. Evita a memória crescer sem fim num evento
  /// longo; o mais antigo sai quando estoura.
  final int lembrarNoMaximo;

  final _vistos = <String>{};
  final _ordem = <String>[];

  int get quantosVistos => _vistos.length;

  /// Marca um id como visto **sem** passar pela decisão.
  ///
  /// Usado para as mensagens que o próprio aparelho escreveu: elas já
  /// estão na tela e na fila, e aceitar de volta a própria mensagem
  /// vinda do rádio a duplicaria.
  void jaConheco(String clientId) => _registrar(clientId);

  Decisao decidir(PacoteLocal? pacote, {DateTime? agora}) {
    if (pacote == null) return Decisao.invalido;
    if (pacote.topId != meuTopId) return Decisao.deOutroTop;
    if (_vistos.contains(pacote.clientId)) return Decisao.jaVisto;

    final momento = (agora ?? DateTime.now()).toUtc();
    // `abs()`: relógio de celular erra, e um aparelho adiantado faria a
    // mensagem parecer vinda do futuro. Descartar por isso perderia dado
    // bom; o que importa é a distância no tempo, não o sinal dela.
    if (momento.difference(pacote.criadaEm).abs() > idadeMaxima) {
      return Decisao.velhaDemais;
    }
    if (pacote.saltos >= saltosMaximos) return Decisao.saltosDemais;

    _registrar(pacote.clientId);
    return Decisao.aceitar;
  }

  /// Repassa só o que foi aceito agora. Quem já conhecia o pacote não o
  /// repassa de novo — é isso que faz a propagação terminar.
  bool deveRepassar(Decisao decisao, PacoteLocal pacote) =>
      decisao == Decisao.aceitar && pacote.saltos + 1 < saltosMaximos;

  void _registrar(String clientId) {
    if (_vistos.add(clientId)) {
      _ordem.add(clientId);
      while (_ordem.length > lembrarNoMaximo) {
        _vistos.remove(_ordem.removeAt(0));
      }
    }
  }

  void esquecerTudo() {
    _vistos.clear();
    _ordem.clear();
  }
}
