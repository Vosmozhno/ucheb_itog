import 'package:flutter/material.dart';
import '../core/dates.dart';
import '../core/validators.dart';
import '../models/entity_definition.dart';
import '../models/entity_record.dart';
import '../state/record_form_controller.dart';

class RecordFields extends StatefulWidget {
  const RecordFields({
    super.key,
    required this.controller,
    required this.options,
    this.disabled = false,
    this.locked = const {},
    this.hidden = const {},
    this.availableUnits,
    this.unitsHint,
  });
  final RecordFormController controller;
  final Map<String, List<EntityRecord>> options;
  final bool disabled;
  final Set<String> locked, hidden;
  final List<EntityRecord>? availableUnits;
  final String? unitsHint;
  @override
  State<RecordFields> createState() => _RecordFieldsState();
}

class _RecordFieldsState extends State<RecordFields> {
  final _texts = <String, TextEditingController>{};
  @override
  void initState() {
    super.initState();
    for (final f in widget.controller.definition.fields) {
      if ([
        FieldKind.text,
        FieldKind.email,
        FieldKind.phone,
        FieldKind.integer,
        FieldKind.date,
      ].contains(f.kind)) {
        _texts[f.key] = TextEditingController(
          text: '${widget.controller.values[f.key] ?? ''}',
        );
      }
    }
  }

  @override
  void dispose() {
    for (final c in _texts.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) => LayoutBuilder(
      builder: (context, constraints) => Form(
        child: Wrap(
          spacing: 16,
          runSpacing: 20,
          children: [
            for (final f in widget.controller.definition.fields)
              if (!widget.hidden.contains(f.key))
                SizedBox(
                  width: constraints.maxWidth >= 640 && !f.wide
                      ? (constraints.maxWidth - 16) / 2
                      : constraints.maxWidth,
                  child: _field(f),
                ),
          ],
        ),
      ),
    ),
  );
  Widget _field(FieldSpec f) {
    final ctrl = widget.controller;
    final enabled = !widget.disabled && !widget.locked.contains(f.key);
    final label = '${f.label}${f.required ? ' *' : ''}';
    final decoration = InputDecoration(
      labelText: label,
      errorText: ctrl.errors[f.key],
    );
    if (f.kind == FieldKind.reference) {
      final options = [...(widget.options[f.reference] ?? [])];
      final current = int.tryParse('${ctrl.values[f.key]}');
      if (current != null && !options.any((e) => e.id == current)) {
        options.add(
          EntityRecord({'id': current, 'name': '№$current (удалено)'}),
        );
      }
      return DropdownButtonFormField<int>(
        initialValue: current,
        isExpanded: true,
        decoration: decoration.copyWith(
          helperText:
              f.key == 'customer_id' && ctrl.definition.key == 'loyalty_cards'
              ? 'У клиента может быть только одна карта'
              : null,
        ),
        items: [
          for (final item in options)
            DropdownMenuItem(
              value: item.id,
              child: Text(item.optionLabel, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: enabled ? (v) => ctrl.set(f.key, v) : null,
      );
    }
    if (f.kind == FieldKind.choice) {
      return DropdownButtonFormField<String>(
        initialValue: ctrl.values[f.key] as String?,
        isExpanded: true,
        decoration: decoration,
        items: [
          for (final e in f.choices.entries)
            DropdownMenuItem(value: e.key, child: Text(e.value)),
        ],
        onChanged: enabled ? (v) => ctrl.set(f.key, v) : null,
      );
    }
    if (f.kind == FieldKind.multiReference) {
      final isUnits = f.key == 'unit_ids';
      final options = isUnits
          ? widget.availableUnits
          : widget.options[f.reference];
      final ids = List<int>.from(ctrl.values[f.key] as List? ?? []);
      return InputDecorator(
        decoration: decoration.copyWith(
          helperText: isUnits
              ? widget.unitsHint
              : 'Стоимость услуг добавляется один раз за аренду.',
        ),
        child: options == null
            ? const Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Укажите пункт и даты, затем проверьте доступность.',
                ),
              )
            : options.isEmpty
            ? Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  isUnits
                      ? 'На эти даты свободных экземпляров нет. Попробуйте другие даты или пункт.'
                      : 'Доступных услуг пока нет.',
                ),
              )
            : isUnits
            ? ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final item in options)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: false,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(item.optionLabel),
                          subtitle: Text(
                            '${money(item['daily_rate'])}/сутки · залог ${money(item['deposit'])}',
                          ),
                          value: ids.contains(item.id),
                          onChanged: enabled
                              ? (checked) {
                                  final next = [...ids];
                                  if (checked ?? false) {
                                    next.add(item.id);
                                  } else {
                                    next.remove(item.id);
                                  }
                                  ctrl.set(f.key, next);
                                }
                              : null,
                        ),
                    ],
                  ),
                ),
              )
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final item in options)
                    FilterChip(
                      label: Text('${item.label} · ${money(item['price'])}'),
                      selected: ids.contains(item.id),
                      onSelected: enabled
                          ? (checked) {
                              final next = [...ids];
                              if (checked) {
                                next.add(item.id);
                              } else {
                                next.remove(item.id);
                              }
                              ctrl.set(f.key, next);
                            }
                          : null,
                    ),
                ],
              ),
      );
    }
    return TextFormField(
      controller: _texts[f.key],
      enabled: enabled,
      forceErrorText: ctrl.errors[f.key],
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (v) => Validators.field(f, v),
      minLines: f.wide && f.key.contains(RegExp('description|note')) ? 3 : 1,
      maxLines: f.wide && f.key.contains(RegExp('description|note')) ? 4 : 1,
      keyboardType: switch (f.kind) {
        FieldKind.integer => TextInputType.number,
        FieldKind.email => TextInputType.emailAddress,
        FieldKind.phone => TextInputType.phone,
        _ => TextInputType.text,
      },
      decoration: decoration.copyWith(
        helperText: f.kind == FieldKind.date
            ? 'ГГГГ-ММ-ДД'
            : f.key == 'email' && ctrl.definition.key == 'customers'
            ? 'Контактная почта. Адрес входа не меняется.'
            : null,
        suffixIcon: f.kind == FieldKind.date
            ? IconButton(
                tooltip: 'Выбрать дату',
                onPressed: enabled
                    ? () async {
                        final first = DateTime(2020),
                            last = DateTime(2100, 12, 31);
                        final date =
                            parseDate(_texts[f.key]!.text) ?? businessToday();
                        final result = await showDatePicker(
                          context: context,
                          firstDate: first,
                          lastDate: last,
                          initialDate: date.isBefore(first)
                              ? first
                              : date.isAfter(last)
                              ? last
                              : date,
                        );
                        if (result != null) {
                          _texts[f.key]!.text = isoDate(result);
                          ctrl.set(f.key, isoDate(result));
                        }
                      }
                    : null,
                icon: const Icon(Icons.calendar_today_outlined),
              )
            : null,
      ),
      onChanged: (value) => ctrl.set(f.key, value),
    );
  }
}
