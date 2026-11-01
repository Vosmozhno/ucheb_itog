import 'package:flutter/material.dart';
import '../core/dates.dart';
import '../models/entity_definition.dart';
import '../models/entity_record.dart';
import '../models/list_query.dart';
import 'status_badge.dart';

class ListFilters extends StatelessWidget {
  const ListFilters({
    super.key,
    required this.definition,
    required this.query,
    required this.onChanged,
    required this.search,
    this.options = const {},
    this.allowArchive = false,
    this.optionsLoading = false,
  });
  final EntityDefinition definition;
  final ListQuery query;
  final ValueChanged<ListQuery> onChanged;
  final TextEditingController search;
  final Map<String, List<EntityRecord>> options;
  final bool allowArchive, optionsLoading;
  void _filter(String key, String? value) => onChanged(
    query.copyWith(page: 1, filters: {...query.filters, key: value ?? ''}),
  );
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: LayoutBuilder(
        builder: (context, c) {
          final width = c.maxWidth < 600 ? c.maxWidth : (c.maxWidth - 24) / 3;
          Widget sized(Widget child) => SizedBox(width: width, child: child);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 16,
                children: [
                  SizedBox(
                    width: c.maxWidth < 600 ? c.maxWidth : width * 2 + 12,
                    child: TextField(
                      controller: search,
                      decoration: InputDecoration(
                        labelText: definition.key == 'rentals'
                            ? 'Поиск по № или комментарию'
                            : 'Поиск',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: search.text.isNotEmpty
                            ? IconButton(
                                tooltip: 'Очистить поиск',
                                onPressed: () {
                                  search.clear();
                                  onChanged(
                                    query.copyWith(keyword: '', page: 1),
                                  );
                                },
                                icon: const Icon(Icons.close),
                              )
                            : null,
                      ),
                      onChanged: (value) =>
                          onChanged(query.copyWith(keyword: value, page: 1)),
                    ),
                  ),
                  sized(
                    DropdownButtonFormField<String>(
                      key: ValueKey('sort:${query.sort}:${query.ascending}'),
                      initialValue:
                          '${definition.sortable.contains(query.sort) ? query.sort : 'id'}:${query.ascending}',
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Сортировка',
                      ),
                      items: [
                        for (final key in definition.sortable)
                          for (final asc in [false, true])
                            DropdownMenuItem(
                              value: '$key:$asc',
                              child: Text(
                                key == 'id'
                                    ? (asc ? 'Сначала старые' : 'Сначала новые')
                                    : '${definition.labelOf(key)} ${asc ? '↑' : '↓'}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          final parts = value.split(':');
                          onChanged(
                            query.copyWith(
                              sort: parts[0],
                              ascending: parts[1] == 'true',
                              page: 1,
                            ),
                          );
                        }
                      },
                    ),
                  ),
                  for (final key in definition.filterFields)
                    if (key != 'daily_rate' && key != 'start_on')
                      sized(_field(key)),
                  if (definition.key == 'equipment')
                    sized(
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _price(context, 'price_min', 'Цена от, ₽'),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _price(context, 'price_max', 'Цена до, ₽'),
                          ),
                        ],
                      ),
                    ),
                  if (definition.key == 'rentals') ...[
                    sized(_date(context, 'start_from', 'Начало аренды от')),
                    sized(_date(context, 'start_to', 'Начало аренды до')),
                  ],
                  if (allowArchive)
                    sized(
                      DropdownButtonFormField<DeletedFilter>(
                        isExpanded: true,
                        key: ValueKey(query.deleted),
                        initialValue: query.deleted,
                        decoration: const InputDecoration(labelText: 'Записи'),
                        items: const [
                          DropdownMenuItem(
                            value: DeletedFilter.active,
                            child: Text('Действующие'),
                          ),
                          DropdownMenuItem(
                            value: DeletedFilter.deleted,
                            child: Text('Корзина'),
                          ),
                          DropdownMenuItem(
                            value: DeletedFilter.all,
                            child: Text('Все записи'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            onChanged(query.copyWith(deleted: v, page: 1));
                          }
                        },
                      ),
                    ),
                ],
              ),
              if (query.parameters.isNotEmpty) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () {
                      search.clear();
                      onChanged(const ListQuery());
                    },
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Сбросить фильтры'),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    ),
  );
  Widget _price(BuildContext context, String key, String label) {
    var pending = query.filters[key] ?? '';
    String? validate(String? input) {
      if (input == null || input.trim().isEmpty) return null;
      final n = int.tryParse(input);
      if (n == null || n < 0 || n > 50000) return 'От 0 до 50 000';
      final other = int.tryParse(
        query.filters[key == 'price_min' ? 'price_max' : 'price_min'] ?? '',
      );
      if (other != null && (key == 'price_min' ? n > other : n < other)) {
        return 'Проверьте диапазон';
      }
      return null;
    }

    void apply(String value) {
      if (validate(value) == null) _filter(key, value);
    }

    return TextFormField(
      key: ValueKey('$key:${query.filters[key]}'),
      initialValue: pending,
      keyboardType: TextInputType.number,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: validate,
      decoration: InputDecoration(
        labelText: label,
        suffixIcon: IconButton(
          tooltip: 'Применить: $label',
          icon: const Icon(Icons.check, size: 18),
          onPressed: () => apply(pending),
        ),
      ),
      onChanged: (value) => pending = value,
      onFieldSubmitted: apply,
    );
  }

  Widget _field(String key) {
    final field = definition.field(key), value = query.filters[key];
    if (field?.kind == FieldKind.reference) {
      final items = options[field!.reference] ?? [];
      final id = int.tryParse(value ?? '');
      return DropdownButtonFormField<int>(
        key: ValueKey('$key:$id:${items.length}'),
        initialValue: id,
        isExpanded: true,
        decoration: InputDecoration(labelText: field.label),
        items: [
          const DropdownMenuItem<int>(value: null, child: Text('Все')),
          for (final item in items)
            DropdownMenuItem(
              value: item.id,
              child: Text(item.label, overflow: TextOverflow.ellipsis),
            ),
          if (id != null && !items.any((e) => e.id == id))
            DropdownMenuItem(value: id, child: Text('№$id')),
        ],
        onChanged: optionsLoading ? null : (v) => _filter(key, v?.toString()),
      );
    }
    final choices = key == 'status' ? rentalStatuses : field?.choices ?? {};
    if (choices.isNotEmpty) {
      return DropdownButtonFormField<String>(
        key: ValueKey('$key:$value'),
        initialValue: choices.containsKey(value) ? value : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: definition.labelOf(key)),
        items: [
          const DropdownMenuItem<String>(value: null, child: Text('Все')),
          for (final item in choices.entries)
            DropdownMenuItem(value: item.key, child: Text(item.value)),
        ],
        onChanged: (v) => _filter(key, v),
      );
    }
    return TextFormField(
      key: ValueKey('$key:$value'),
      initialValue: value,
      decoration: InputDecoration(labelText: definition.labelOf(key)),
      onFieldSubmitted: (v) => _filter(key, v),
    );
  }

  Widget _date(BuildContext context, String key, String label) =>
      OutlinedButton.icon(
        onPressed: () async {
          final date = await showDatePicker(
            context: context,
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
            initialDate: parseDate(query.filters[key]) ?? businessToday(),
          );
          if (date != null) _filter(key, isoDate(date));
        },
        icon: const Icon(Icons.date_range_outlined),
        label: Text(
          query.filters[key] == null
              ? label
              : '$label: ${displayDate(query.filters[key])}',
        ),
      );
}
