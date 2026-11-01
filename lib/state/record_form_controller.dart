import 'package:flutter/foundation.dart';
import '../core/dates.dart';
import '../core/validators.dart';
import '../models/entity_definition.dart';

class RecordFormController extends ChangeNotifier {
  RecordFormController(this.definition, Map<String, dynamic> initial)
    : values = {...initial} {
    for (final f in definition.fields) {
      if (values.containsKey(f.key)) continue;
      values[f.key] = switch (f.kind) {
        FieldKind.multiReference => <int>[],
        FieldKind.integer => f.min,
        FieldKind.choice => f.choices.keys.firstOrNull,
        FieldKind.date => isoDate(
          businessToday().add(
            Duration(
              days: f.key == 'expires_on'
                  ? 365
                  : f.key == 'end_on'
                  ? 1
                  : 0,
            ),
          ),
        ),
        _ => null,
      };
    }
  }
  final EntityDefinition definition;
  final Map<String, dynamic> values;
  Map<String, String> errors = {};
  int revision = 0;
  void set(String key, Object? value) {
    values[key] = value;
    revision++;
    errors.remove(key);
    notifyListeners();
  }

  Map<String, dynamic> get payload => {
    for (final f in definition.fields)
      f.key: switch (f.kind) {
        FieldKind.integer ||
        FieldKind.reference => int.tryParse('${values[f.key]}'),
        FieldKind.multiReference => List<int>.from(
          values[f.key] as List? ?? [],
        ),
        _ =>
          ['sku', 'inventory_code', 'number'].contains(f.key)
              ? ('${values[f.key] ?? ''}').trim().toUpperCase()
              : ('${values[f.key] ?? ''}').trim(),
      },
  };
  bool validate() {
    errors = Validators.record(definition, values);
    notifyListeners();
    return errors.isEmpty;
  }

  void serverErrors(Map<String, String> value) {
    errors = {...value};
    notifyListeners();
  }
}
