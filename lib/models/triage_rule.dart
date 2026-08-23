import 'package:flutter/material.dart';

enum TriageColor { blue, green, yellow, red }

TriageColor? triageColorFromString(String? value) {
  return TriageColor.values.where((c) => c.name == value).firstOrNull;
}

extension TriageColorUi on TriageColor {
  Color get materialColor => switch (this) {
        TriageColor.blue => Colors.blue,
        TriageColor.green => Colors.green,
        TriageColor.yellow => Colors.amber,
        TriageColor.red => Colors.red,
      };

  String get label => switch (this) {
        TriageColor.blue => 'Azul',
        TriageColor.green => 'Verde',
        TriageColor.yellow => 'Amarelo',
        TriageColor.red => 'Vermelho',
      };
}

/// Regra de triagem editável pelo admin master: define qual [color] se
/// aplica a um paciente cuja idade caia em [minAge, maxAge] E cujo número
/// de comorbidades caia em [minComorbidities, maxComorbidities].
class TriageRule {
  final int id;
  final TriageColor color;
  final String label;
  final int minAge;
  final int? maxAge;
  final int minComorbidities;
  final int maxComorbidities;
  final int priority;
  final bool active;

  TriageRule({
    required this.id,
    required this.color,
    required this.label,
    required this.minAge,
    this.maxAge,
    required this.minComorbidities,
    required this.maxComorbidities,
    required this.priority,
    required this.active,
  });

  factory TriageRule.fromMap(Map<String, dynamic> map) {
    return TriageRule(
      id: map['id'] as int,
      color: triageColorFromString(map['color'] as String?) ?? TriageColor.red,
      label: map['label'] as String,
      minAge: map['min_age'] as int,
      maxAge: map['max_age'] as int?,
      minComorbidities: map['min_comorbidities'] as int,
      maxComorbidities: map['max_comorbidities'] as int,
      priority: map['priority'] as int,
      active: map['active'] as bool,
    );
  }

  bool matches({required int age, required int comorbidityCount}) {
    if (age < minAge) return false;
    if (maxAge != null && age > maxAge!) return false;
    if (comorbidityCount < minComorbidities) return false;
    if (comorbidityCount > maxComorbidities) return false;
    return true;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
