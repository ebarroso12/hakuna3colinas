/// Uma das até 3 imagens de identidade de um Top.
///
/// "A cada Top será tudo novo": logo da trilha, brasão, patrocínio. O Top
/// já tinha **uma** imagem (`tops.emblema_path`); estas são as outras.
///
/// Tabela e não três colunas (`emblema_path_2`, `_3`): com colunas a ordem
/// não se altera sem reescrever valores, apagar a do meio deixa um buraco,
/// e um quarto slot amanhã exige migração. Com `ordem`, os três casos
/// resolvem sozinhos.
class TopImagem {
  const TopImagem({
    required this.topId,
    required this.ordem,
    required this.storagePath,
    this.id,
    this.legenda,
  });

  final String? id;
  final String topId;

  /// 1, 2 ou 3. O teto está no banco também (`check ordem between 1 and 3`)
  /// — a tela é conveniência, a fronteira é o banco.
  final int ordem;

  final String storagePath;
  final String? legenda;

  factory TopImagem.fromMap(Map<String, dynamic> map) => TopImagem(
    id: map['id'] as String?,
    topId: map['top_id'] as String,
    ordem: (map['ordem'] as num).toInt(),
    storagePath: map['storage_path'] as String,
    legenda: map['legenda'] as String?,
  );

  Map<String, dynamic> toMap() => {
    'top_id': topId,
    'ordem': ordem,
    'storage_path': storagePath,
    'legenda': legenda,
  };
}
