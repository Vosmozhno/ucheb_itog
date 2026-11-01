import 'package:flutter/material.dart';
import '../core/dates.dart';
import '../models/entity_definition.dart';
import '../models/entity_record.dart';
import 'status_badge.dart';

String recordValue(
  EntityRecord record,
  String key, {
  EntityDefinition? definition,
}) {
  final value = record[key];
  if (value == null) return '—';
  if (key.endsWith('_id')) {
    final relation = record[key.substring(0, key.length - 3)];
    if (relation is Map) {
      return '${relation['name'] ?? relation['full_name'] ?? '№$value'}';
    }
    return '№$value';
  }
  if ([
    'price',
    'daily_rate',
    'deposit',
    'total_cost',
    'base_cost',
    'late_fee',
    'services_cost',
  ].contains(key)) {
    return money(value);
  }
  if (key.endsWith('_on') || key.endsWith('_at')) return displayDate(value);
  if (key == 'discount_percent') return '$value %';
  final choices = definition?.field(key)?.choices;
  return choices?[value] ?? '$value';
}

class RecordValue extends StatelessWidget {
  const RecordValue({
    super.key,
    required this.record,
    required this.field,
    this.definition,
    this.maxLines = 2,
  });
  final EntityRecord record;
  final String field;
  final EntityDefinition? definition;
  final int maxLines;
  @override
  Widget build(BuildContext context) => field == 'state' || field == 'status'
      ? StatusBadge('${record[field]}')
      : Text(
          recordValue(record, field, definition: definition),
          maxLines: maxLines,
          overflow: TextOverflow.ellipsis,
        );
}
