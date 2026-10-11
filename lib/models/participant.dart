/// Faixa de IMC, na mesma escala que o app oficial mostra na barra
/// colorida (Ab · Nm · Sp · Ob1 · Ob2 · Ob3).
enum FaixaImc { abaixo, normal, sobrepeso, obesidade1, obesidade2, obesidade3 }

extension FaixaImcUi on FaixaImc {
  String get sigla => switch (this) {
    FaixaImc.abaixo => 'Ab',
    FaixaImc.normal => 'Nm',
    FaixaImc.sobrepeso => 'Sp',
    FaixaImc.obesidade1 => 'Ob1',
    FaixaImc.obesidade2 => 'Ob2',
    FaixaImc.obesidade3 => 'Ob3',
  };

  String get label => switch (this) {
    FaixaImc.abaixo => 'Abaixo do peso',
    FaixaImc.normal => 'Peso normal',
    FaixaImc.sobrepeso => 'Sobrepeso',
    FaixaImc.obesidade1 => 'Obesidade grau I',
    FaixaImc.obesidade2 => 'Obesidade grau II',
    FaixaImc.obesidade3 => 'Obesidade grau III',
  };
}

/// Participante (Senderista) de um Top.
///
/// **Não é usuário do app.** Só Legendários — quem tem número — entram no
/// app; o Senderista existe aqui como registro, criado e mantido pela
/// equipe. Tabela `top_participants`.
///
/// Cada Top tem o seu conjunto: a mesma pessoa em dois Tops são dois
/// registros, com peso, tag e ficha próprios daquele evento.
class Participant {
  final String id;
  final String topId;

  /// Preenchido só quando o participante também é Legendário com conta.
  final String? linkedProfileId;

  final String? participantCode;
  final String fullName;
  final String? nickname;

  /// Grupo de senderistas a que ele pertence. É um dos dois filtros de
  /// busca da lista, junto com o nome.
  final String? familia;

  final String? phone;
  final DateTime? birthDate;
  final String? cidade;
  final String? estado;
  final String? emergencyContact;

  // --- medidas ---
  final double? heightCm;
  final double? weightKg;

  // --- clínico ---
  final String? bloodType;
  final String? biotipo;
  final String? cirurgias;
  final String? observacaoHakuna;
  final String? atividadeFisicaSemanal;

  /// Só condição clínica. É esta lista que a triagem conta para decidir a
  /// cor — por isso plano de saúde e alergia ficam em campos próprios, e
  /// não aqui dentro. No app oficial os três vinham juntos sob
  /// "COMORBIDADES", o que inflaria a contagem.
  final List<String> comorbidades;

  final String? alergias;
  final String? planoSaude;
  final String? medicamentosContinuos;
  final String? restricoesFisicas;

  final String? tagUid;
  final String? notes;
  final bool active;

  /// Cadastro feito para TESTAR o app, não pessoa real do evento.
  ///
  /// Existe para separar teste de real sem depender de convenção de nome
  /// ("TESTE AUTOCADASTRO (apagar depois)" era o que havia, e nome não é
  /// dado). A lista mostra selo, e é por este campo que a ação "apagar
  /// todos os testes" encontra o que apagar.
  final bool isTeste;

  Participant({
    required this.id,
    required this.topId,
    required this.fullName,
    this.linkedProfileId,
    this.participantCode,
    this.nickname,
    this.familia,
    this.phone,
    this.birthDate,
    this.cidade,
    this.estado,
    this.emergencyContact,
    this.heightCm,
    this.weightKg,
    this.bloodType,
    this.biotipo,
    this.cirurgias,
    this.observacaoHakuna,
    this.atividadeFisicaSemanal,
    this.comorbidades = const [],
    this.alergias,
    this.planoSaude,
    this.medicamentosContinuos,
    this.restricoesFisicas,
    this.tagUid,
    this.notes,
    this.active = true,
    this.isTeste = false,
  });

  factory Participant.fromMap(Map<String, dynamic> map) {
    return Participant(
      id: map['id'] as String,
      topId: map['top_id'] as String,
      fullName: map['full_name'] as String,
      linkedProfileId: map['linked_profile_id'] as String?,
      participantCode: map['participant_code'] as String?,
      nickname: map['nickname'] as String?,
      familia: map['familia'] as String?,
      phone: map['phone'] as String?,
      birthDate: map['birth_date'] != null
          ? DateTime.parse(map['birth_date'] as String)
          : null,
      cidade: map['cidade'] as String?,
      estado: map['estado'] as String?,
      emergencyContact: map['emergency_contact'] as String?,
      heightCm: (map['height_cm'] as num?)?.toDouble(),
      weightKg: (map['weight_kg'] as num?)?.toDouble(),
      bloodType: map['blood_type'] as String?,
      biotipo: map['biotipo'] as String?,
      cirurgias: map['cirurgias'] as String?,
      observacaoHakuna: map['observacao_hakuna'] as String?,
      atividadeFisicaSemanal: map['atividade_fisica_semanal'] as String?,
      comorbidades:
          (map['comorbidades'] as List<dynamic>?)?.cast<String>() ?? const [],
      alergias: map['alergias'] as String?,
      planoSaude: map['plano_saude'] as String?,
      medicamentosContinuos: map['medicamentos_continuos'] as String?,
      restricoesFisicas: map['restricoes_fisicas'] as String?,
      tagUid: map['tag_uid'] as String?,
      notes: map['notes'] as String?,
      active: map['active'] as bool? ?? true,
      isTeste: map['is_teste'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'top_id': topId,
    'is_teste': isTeste,
    'full_name': fullName,
    'linked_profile_id': linkedProfileId,
    'participant_code': participantCode,
    'nickname': nickname,
    'familia': familia,
    'phone': phone,
    'birth_date': birthDate?.toIso8601String().split('T').first,
    'cidade': cidade,
    'estado': estado,
    'emergency_contact': emergencyContact,
    'height_cm': heightCm,
    'weight_kg': weightKg,
    'blood_type': bloodType,
    'biotipo': biotipo,
    'cirurgias': cirurgias,
    'observacao_hakuna': observacaoHakuna,
    'atividade_fisica_semanal': atividadeFisicaSemanal,
    'comorbidades': comorbidades,
    'alergias': alergias,
    'plano_saude': planoSaude,
    'medicamentos_continuos': medicamentosContinuos,
    'restricoes_fisicas': restricoesFisicas,
    'tag_uid': tagUid,
    'notes': notes,
    'active': active,
  };

  /// Idade em anos completos. Null se a data de nascimento não foi
  /// informada — e aí a triagem também não classifica.
  int? get idade {
    final b = birthDate;
    if (b == null) return null;
    final agora = DateTime.now();
    var anos = agora.year - b.year;
    if (agora.month < b.month ||
        (agora.month == b.month && agora.day < b.day)) {
      anos--;
    }
    return anos;
  }

  /// IMC = peso / altura². Null quando falta peso ou altura, ou quando a
  /// altura é zero — dividir por zero daria infinito na tela.
  double? get imc {
    final peso = weightKg;
    final alturaCm = heightCm;
    if (peso == null || alturaCm == null || alturaCm <= 0) return null;
    final alturaM = alturaCm / 100;
    return peso / (alturaM * alturaM);
  }

  /// Faixa do IMC pelos cortes da OMS.
  FaixaImc? get faixaImc {
    final valor = imc;
    if (valor == null) return null;
    if (valor < 18.5) return FaixaImc.abaixo;
    if (valor < 25) return FaixaImc.normal;
    if (valor < 30) return FaixaImc.sobrepeso;
    if (valor < 35) return FaixaImc.obesidade1;
    if (valor < 40) return FaixaImc.obesidade2;
    return FaixaImc.obesidade3;
  }

  /// Quantas comorbidades a triagem deve contar.
  int get totalComorbidades => comorbidades.length;

  /// Nome + apelido, como a lista mostra.
  String get displayLabel => nickname != null && nickname!.isNotEmpty
      ? '$fullName ($nickname)'
      : fullName;

  /// "FRANCA - SÃO PAULO", como no cabeçalho da ficha.
  String? get localidade {
    final c = cidade?.trim();
    final e = estado?.trim();
    if ((c == null || c.isEmpty) && (e == null || e.isEmpty)) return null;
    if (c == null || c.isEmpty) return e;
    if (e == null || e.isEmpty) return c;
    return '$c - $e';
  }

  /// Casa com o termo digitado na busca: nome, sobrenome, pedaço de
  /// qualquer um deles, apelido ou código. A busca por família é separada,
  /// porque é o outro filtro da tela.
  bool combinaCom(String termo) {
    final t = termo.trim().toLowerCase();
    if (t.isEmpty) return true;
    final alvos = [fullName, nickname, participantCode, familia];
    return alvos.any((a) => a != null && a.toLowerCase().contains(t));
  }
}
