class EntityRecord {
  EntityRecord(Map<String, dynamic> data) : values = Map.unmodifiable(data);
  final Map<String, dynamic> values;
  int get id => (values['id'] as num?)?.toInt() ?? 0;
  bool get isDeleted => values['deleted_at'] != null;
  String get label {
    for (final key in ['name', 'full_name', 'inventory_code', 'number']) {
      if (values[key] case final String value when value.isNotEmpty) {
        return value;
      }
    }
    return '№$id';
  }

  String get optionLabel {
    final equipment = values['equipment'];
    final name =
        values['equipment_name'] ??
        (equipment is Map ? equipment['name'] : null);
    return name == null ? label : '$label · $name';
  }

  Object? operator [](String key) => values[key];
  EntityRecord copyWith(Map<String, dynamic> changes) =>
      EntityRecord({...values, ...changes});
  List<int> get unitIds => _relationIds('rental_items', 'unit_id');
  List<int> get serviceIds => _relationIds('rental_services', 'service_id');
  List<int> _relationIds(String relation, String key) =>
      ((values[relation] as List?) ?? [])
          .map((e) => (e[key] as num).toInt())
          .toList();
}
