/// Definição pura do esquema local.
///
/// Separado do código de acesso de propósito — padrão emprestado do
/// OpenTracks, onde `tables/` descreve o esquema e `ContentProviderUtils`
/// faz o acesso. Quem precisa saber "que colunas existem" lê só este
/// arquivo, e migração nenhuma se perde no meio de regra de negócio.
abstract final class Tabelas {
  // ---------------------------------------------------------------------
  // OUTBOX — fila de escritas feitas offline (v1)
  // ---------------------------------------------------------------------
  static const outbox = 'outbox';
  static const syncState = 'sync_state';

  // ---------------------------------------------------------------------
  // CACHE DE LEITURA (v2) — o que o app precisa enxergar sem rede
  //
  // Sem isto, em cold start no mato a lista de participantes vem vazia e a
  // tag NFC não resolve. A fila cobria escrita; faltava leitura.
  // ---------------------------------------------------------------------
  static const participantes = 'cache_participantes';
  static const tags = 'cache_tags';
  static const regrasTriagem = 'cache_regras_triagem';

  /// Última aferição conhecida de cada participante.
  ///
  /// Separada de [participantes] porque muda em ritmo diferente: a ficha é
  /// baixada uma vez, a aferição é reescrita a cada atendimento — e é ela
  /// que faz a cor de triagem reagir a PA e SpO₂ em vez de ficar travada
  /// no cadastro.
  static const ultimaAfericao = 'cache_ultima_afericao';

  // ---------------------------------------------------------------------
  // CACHE DE MENSAGENS (v5) — a conversa da equipe sem rede
  //
  // Até aqui o chat combinava o stream do Supabase com a fila local. Sem
  // rede, o stream não traz nada, então o usuário via apenas **o que ele
  // mesmo escreveu** — a conversa da equipe sumia da tela.
  //
  // No mato isso é o oposto do que se precisa: quem chega ao acampamento
  // sem sinal é exatamente quem mais precisa ler o que foi combinado
  // enquanto estava fora.
  //
  // Mesmo padrão de `cache_participantes`: a rede alimenta o disco, o
  // disco alimenta a tela. E é a base para entrega entre aparelhos — sem
  // um lugar onde guardar, não há o que trocar por Bluetooth nem onde
  // escrever o que chegou.
  // ---------------------------------------------------------------------
  static const mensagens = 'cache_mensagens';

  /// Chave-valor para intenção que tem de sobreviver ao processo.
  ///
  /// Existe porque não somos donos do Foreground Service — ele é do
  /// plugin `geolocator_android`, e não há como marcá-lo `START_STICKY`.
  /// O que dá para fazer é o **app** lembrar que deveria estar rastreando
  /// e retomar na subida. Ver `LocationService.retomarSeDevia`.
  static const estado = 'estado_local';
}

/// Colunas de [Tabelas.estado].
abstract final class ColunasEstado {
  static const chave = 'chave';
  static const valor = 'valor';
  static const gravadoEm = 'gravado_em';

  static const criar =
      '''
    CREATE TABLE ${Tabelas.estado} (
      $chave      TEXT PRIMARY KEY,
      $valor      TEXT,
      $gravadoEm  INTEGER NOT NULL
    )
  ''';

  /// Top que deveria estar sendo rastreado. Ausente = rastreamento parado
  /// de propósito pelo usuário.
  static const topRastreando = 'top_rastreando';

  /// Nome de quem está logado, para o alarme dizer QUEM está chamando.
  ///
  /// Gravado sempre que o perfil carrega da rede. Existe porque
  /// `profiles` é fechada para quem recebe o alarme
  /// (`profiles_select_own_or_admin`), então o nome tem de viajar DENTRO
  /// do alarme — e no disparo offline não há rede para buscá-lo.
  ///
  /// Ausente só até o primeiro login com sinal. Nesse caso o alarme sai
  /// sem nome e a faixa diz "Alguém do Top", que é verdade, em vez de
  /// mostrar um uuid.
  static const meuNome = 'meu_nome';
}

/// Colunas de [Tabelas.participantes].
///
/// Nomes idênticos aos do Postgres de propósito: o mesmo `fromMap` serve
/// para linha vinda do Supabase e para linha vinda do SQLite, sem camada
/// de tradução que poderia divergir com o tempo.
abstract final class ColunasParticipante {
  static const id = 'id';
  static const topId = 'top_id';
  static const fullName = 'full_name';
  static const nickname = 'nickname';
  static const familia = 'familia';

  /// Família em minúsculo e sem acento, só local.
  ///
  /// Existe porque o filtro por família comparava `LOWER(familia)` contra o
  /// termo digitado, e `"aguia"` **não achava** `"ÁGUIA"` — o mesmo bug que
  /// [buscaNormalizada] resolve para o nome. Filtrar em SQL exige a coluna
  /// normalizada no banco; normalizar em Dart depois da consulta obrigaria
  /// a carregar o Top inteiro para descartar quase tudo.
  static const familiaNormalizada = 'familia_normalizada';

  static const participantCode = 'participant_code';
  static const phone = 'phone';
  static const birthDate = 'birth_date';
  static const cidade = 'cidade';
  static const estado = 'estado';
  static const emergencyContact = 'emergency_contact';
  static const heightCm = 'height_cm';
  static const weightKg = 'weight_kg';
  static const bloodType = 'blood_type';
  static const biotipo = 'biotipo';
  static const cirurgias = 'cirurgias';
  static const observacaoHakuna = 'observacao_hakuna';
  static const atividadeFisica = 'atividade_fisica_semanal';

  /// `text[]` no Postgres vira JSON aqui — SQLite não tem array.
  static const comorbidades = 'comorbidades';

  static const alergias = 'alergias';
  static const planoSaude = 'plano_saude';
  static const medicamentos = 'medicamentos_continuos';
  static const restricoes = 'restricoes_fisicas';
  static const tagUid = 'tag_uid';
  static const notes = 'notes';
  static const active = 'active';

  /// Só local: quando esta linha foi baixada. Serve para a tela avisar
  /// "dados de 3 h atrás" em vez de fingir que estão a zero.
  static const baixadoEm = 'baixado_em';

  /// Coluna derivada, gravada em minúsculo e sem acento no momento do
  /// cache. É ela que a busca consulta: calcular acento a cada tecla, em
  /// 215 linhas, é trabalho repetido à toa.
  static const buscaNormalizada = 'busca_normalizada';

  static const criar =
      '''
    CREATE TABLE ${Tabelas.participantes} (
      $id                       TEXT PRIMARY KEY,
      $topId                    TEXT NOT NULL,
      $fullName                 TEXT NOT NULL,
      $nickname                 TEXT,
      $familia                  TEXT,
      $familiaNormalizada       TEXT NOT NULL DEFAULT '',
      $participantCode          TEXT,
      $phone                    TEXT,
      $birthDate                TEXT,
      $cidade                   TEXT,
      $estado                   TEXT,
      $emergencyContact         TEXT,
      $heightCm                 REAL,
      $weightKg                 REAL,
      $bloodType                TEXT,
      $biotipo                  TEXT,
      $cirurgias                TEXT,
      $observacaoHakuna         TEXT,
      $atividadeFisica          TEXT,
      $comorbidades             TEXT NOT NULL DEFAULT '[]',
      $alergias                 TEXT,
      $planoSaude               TEXT,
      $medicamentos             TEXT,
      $restricoes               TEXT,
      $tagUid                   TEXT,
      $notes                    TEXT,
      $active                   INTEGER NOT NULL DEFAULT 1,
      $baixadoEm                INTEGER NOT NULL,
      $buscaNormalizada         TEXT NOT NULL DEFAULT ''
    )
  ''';

  static const indices = [
    'CREATE INDEX idx_cache_part_top ON ${Tabelas.participantes} ($topId, $fullName)',
    'CREATE INDEX idx_cache_part_busca ON ${Tabelas.participantes} ($topId, $buscaNormalizada)',
    'CREATE INDEX idx_cache_part_familia ON ${Tabelas.participantes} ($topId, $familiaNormalizada)',
  ];
}

/// Colunas de [Tabelas.ultimaAfericao].
///
/// Guarda só o que reclassifica gravidade (PA e SpO₂), não o atendimento
/// inteiro — o atendimento é append-only e vive na fila do outbox. Aqui é
/// estado derivado: pode ser reconstruído e não é fonte da verdade de nada.
abstract final class ColunasAfericao {
  static const participantId = 'participant_id';
  static const topId = 'top_id';
  static const systolicBp = 'systolic_bp';
  static const diastolicBp = 'diastolic_bp';
  static const spo2 = 'spo2';

  /// Instante da aferição. É por ele que uma medida mais nova substitui a
  /// anterior — e não pela ordem de chegada, que offline não significa nada.
  static const medidoEm = 'medido_em';

  static const criar =
      '''
    CREATE TABLE ${Tabelas.ultimaAfericao} (
      $participantId  TEXT PRIMARY KEY,
      $topId          TEXT NOT NULL,
      $systolicBp     INTEGER,
      $diastolicBp    INTEGER,
      $spo2           INTEGER,
      $medidoEm       INTEGER NOT NULL
    )
  ''';

  static const indices = [
    'CREATE INDEX idx_cache_afericao_top ON ${Tabelas.ultimaAfericao} ($topId)',
  ];
}

/// Colunas de [Tabelas.tags].
abstract final class ColunasTag {
  static const token = 'token';
  static const id = 'id';
  static const participantId = 'participant_id';
  static const topId = 'top_id';
  static const status = 'status';
  static const issuedAt = 'issued_at';
  static const baixadoEm = 'baixado_em';

  /// `token` é a chave primária, não `id`: a leitura NFC chega com o token
  /// e nada mais. Essa é a busca que precisa ser instantânea no mato.
  static const criar =
      '''
    CREATE TABLE ${Tabelas.tags} (
      $token          TEXT PRIMARY KEY,
      $id             TEXT NOT NULL,
      $participantId  TEXT NOT NULL,
      $topId          TEXT NOT NULL,
      $status         TEXT NOT NULL,
      $issuedAt       TEXT,
      $baixadoEm      INTEGER NOT NULL
    )
  ''';

  static const indices = [
    'CREATE INDEX idx_cache_tag_participante ON ${Tabelas.tags} ($participantId)',
    'CREATE INDEX idx_cache_tag_top ON ${Tabelas.tags} ($topId, $status)',
  ];
}

/// Colunas de [Tabelas.regrasTriagem].
///
/// Cacheadas porque sem elas a ficha mostra "Sem triagem" offline — e a cor
/// é justamente o que o Hakuna olha primeiro.
abstract final class ColunasRegraTriagem {
  static const id = 'id';
  static const color = 'color';
  static const label = 'label';
  static const minAge = 'min_age';
  static const maxAge = 'max_age';
  static const minComorbidities = 'min_comorbidities';
  static const maxComorbidities = 'max_comorbidities';
  static const priority = 'priority';
  static const active = 'active';
  static const baixadoEm = 'baixado_em';

  static const criar =
      '''
    CREATE TABLE ${Tabelas.regrasTriagem} (
      $id                INTEGER PRIMARY KEY,
      $color             TEXT NOT NULL,
      $label             TEXT NOT NULL,
      $minAge            INTEGER NOT NULL,
      $maxAge            INTEGER,
      $minComorbidities  INTEGER NOT NULL,
      $maxComorbidities  INTEGER NOT NULL,
      $priority          INTEGER NOT NULL,
      $active            INTEGER NOT NULL DEFAULT 1,
      $baixadoEm         INTEGER NOT NULL
    )
  ''';

  static const indices = [
    'CREATE INDEX idx_cache_regra_prioridade '
        'ON ${Tabelas.regrasTriagem} ($active, $priority)',
  ];
}

/// Colunas de [Tabelas.mensagens].
///
/// Guarda mensagem de equipe (`team_messages`) e do chat clínico
/// (`top_hakuna_messages`) na MESMA tabela, separadas por [entidade]. São
/// duas tabelas no Postgres por causa de RLS diferente, mas no disco do
/// aparelho a forma é a mesma e duplicar o esquema só criaria duas
/// migrações para manter em sincronia.
///
/// Nomes idênticos aos do Postgres, como nas outras: o mesmo `fromMap`
/// serve para linha vinda do Supabase e para linha vinda do SQLite.
abstract final class ColunasMensagem {
  /// Chave primária LOCAL. Duas formas, e a diferença importa:
  ///
  ///     <entidade>|srv|<id do servidor>    veio do Supabase
  ///     <entidade>|loc|<client_id>         veio do rádio, sem servidor
  ///
  /// Não é o `id` cru porque `team_messages.id` e
  /// `top_hakuna_messages.id` são sequências independentes no Postgres —
  /// as duas têm id 1, e numa tabela só uma sobrescreveria a outra.
  ///
  /// Mensagem que chegou por rádio **não tem id de servidor** (ela nunca
  /// passou por lá), então a identidade dela é o `client_id` gerado na
  /// origem. Quando a mesma mensagem chegar pelo Supabase, a linha `loc`
  /// é apagada e a `srv` fica — ver `CacheLocal.salvarMensagens`.
  static const chave = 'chave';

  /// `team_messages` ou `top_hakuna_messages`.
  static const entidade = 'entidade';

  static const id = 'id';
  static const clientId = 'client_id';
  static const topId = 'top_id';

  /// Null no chat clínico, que não é por equipe.
  static const team = 'team';

  static const senderId = 'sender_id';

  /// Nome de quem escreveu, quando a mensagem veio pelo rádio.
  ///
  /// `profiles` é fechada para quem recebe, e sem rede não há como
  /// resolver uuid em nome. Mesma razão de `top_alerts.sender_name`.
  /// Null nas que vieram do servidor, onde a tela já resolve o nome.
  static const senderName = 'sender_name';

  static const body = 'body';
  static const isAlert = 'is_alert';

  /// O servidor confirmou a autoria desta mensagem.
  ///
  /// **Falso = chegou por rádio local e NÃO está autenticada.** Qualquer
  /// aparelho ao alcance pode afirmar "fulano disse X"; a RLS impede isso
  /// no servidor, o rádio não impede nada.
  ///
  /// Numa emergência a diferença é séria — "o coordenador mandou descer"
  /// forjado move 200 pessoas. A tela **tem de** mostrar isso. Esconder
  /// seria pior que não ter a funcionalidade.
  static const confirmada = 'confirmada';

  /// Epoch em ms. Inteiro e não texto: é por ele que se ordena e se poda,
  /// e comparar ISO-8601 como string funciona por acidente do formato.
  static const createdAt = 'created_at';
  static const editedAt = 'edited_at';

  static const criar =
      '''
    CREATE TABLE ${Tabelas.mensagens} (
      $chave      TEXT PRIMARY KEY,
      $entidade   TEXT    NOT NULL,
      -- NULL no que chegou por radio: nunca passou pelo servidor, entao
      -- nao tem id de sequencia. A identidade dessas e o client_id.
      $id         INTEGER,
      $clientId   TEXT,
      $topId      TEXT    NOT NULL,
      $team       TEXT,
      $senderId   TEXT    NOT NULL,
      $senderName TEXT,
      $body       TEXT    NOT NULL,
      $isAlert    INTEGER NOT NULL DEFAULT 0,
      -- 1 por padrao: tudo que vem do Supabase e autenticado pela RLS.
      -- So o radio local grava 0 aqui.
      $confirmada INTEGER NOT NULL DEFAULT 1,
      $createdAt  INTEGER NOT NULL,
      $editedAt   INTEGER
    )
  ''';

  /// Índice da consulta que a tela faz: as mensagens de um chat, da mais
  /// nova para a mais velha. Sem ele é varredura completa a cada abertura,
  /// e esta tabela cresce a cada mensagem de cada equipe.
  static const criarIndice =
      '''
    CREATE INDEX idx_mensagens_chat
      ON ${Tabelas.mensagens} ($topId, $entidade, $team, $createdAt DESC)
  ''';

  /// Acha a linha que veio do rádio para apagá-la quando a mesma
  /// mensagem chegar pelo servidor. Sem este índice, confirmar uma
  /// mensagem varreria a tabela inteira — e isso acontece a cada lote
  /// que o Supabase entrega.
  static const criarIndiceClientId =
      '''
    CREATE INDEX idx_mensagens_client_id
      ON ${Tabelas.mensagens} ($clientId)
  ''';
}
