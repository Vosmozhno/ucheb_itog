enum FieldKind {
  text,
  integer,
  email,
  phone,
  date,
  reference,
  choice,
  multiReference,
}

class FieldSpec {
  FieldSpec.fromJson(Map<String, dynamic> json)
    : key = json['key'] as String,
      label = json['label'] as String,
      kind = FieldKind.values.byName(json['type'] as String),
      required = json['required'] as bool? ?? true,
      min = (json['min'] as num?)?.toInt() ?? 0,
      max = (json['max'] as num?)?.toInt() ?? 200,
      reference = json['reference'] as String?,
      wide = json['wide'] as bool? ?? false,
      choices = Map<String, String>.from(json['choices'] as Map? ?? {});
  final String key, label;
  final FieldKind kind;
  final bool required, wide;
  final int min, max;
  final String? reference;
  final Map<String, String> choices;
}

class EntityDefinition {
  EntityDefinition.fromJson(Map<String, dynamic> json)
    : key = json['key'] as String,
      title = json['title'] as String,
      singular = json['singular'] as String,
      fields = (json['fields'] as List)
          .map((f) => FieldSpec.fromJson(Map<String, dynamic>.from(f)))
          .toList(),
      columns = List<String>.from(json['columns']),
      searchFields = List<String>.from(json['searchFields']),
      filterFields = List<String>.from(json['filterFields']),
      select = json['select'] as String;
  final String key, title, singular, select;
  final List<FieldSpec> fields;
  final List<String> columns, searchFields, filterFields;
  FieldSpec? field(String key) {
    for (final f in fields) {
      if (f.key == key) return f;
    }
    return null;
  }

  String labelOf(String key) =>
      field(key)?.label ??
      const {
        'id': '№',
        'status': 'Статус',
        'total_cost': 'Стоимость',
        'created_at': 'Дата создания',
        'updated_at': 'Обновлено',
        'deleted_at': 'Удалено',
        'late_fee': 'Доплата за просрочку',
      }[key] ??
      key;
  Set<String> get sortable => {
    'id',
    'created_at',
    for (final column in columns)
      if (field(column)?.kind != FieldKind.reference &&
          field(column)?.kind != FieldKind.multiReference)
        column,
  };
}
