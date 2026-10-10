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
