import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/api_error.dart';
import '../widgets/equipment_illustration.dart';
import '../core/dates.dart';
import '../data/entity_definitions.dart';
import '../models/app_role.dart';
import '../models/entity_record.dart';
import '../models/list_query.dart';
import '../repositories/repository_registry.dart';
import '../repositories/rental_service.dart';
import '../state/auth_state.dart';
import '../state/entity_list_state.dart';
import '../widgets/confirm_action.dart';
import '../widgets/data_states.dart';
import '../widgets/list_filters.dart';
import '../widgets/page_frame.dart';
import '../widgets/pagination_bar.dart';
import '../widgets/record_value.dart';

enum EntityListMode { manage, catalog, myRentals, desk }

class EntityListScreen extends StatefulWidget {
  const EntityListScreen({
    super.key,
    required this.entity,
    required this.uri,
    this.mode = EntityListMode.manage,
  });
  final String entity;
  final Uri uri;
  final EntityListMode mode;
  @override
  State<EntityListScreen> createState() => _EntityListScreenState();
}

class _EntityListScreenState extends State<EntityListScreen> {
  EntityListState? _state;
  final _search = TextEditingController();
  final _selected = <int>{};
  Map<String, List<EntityRecord>> _options = {};
  bool _optionsLoading = true;
  ApiError? _optionsError;
  Timer? _debounce;
  ListQuery get _query => ListQuery.fromUri(widget.uri);
  bool get _manage => widget.mode == EntityListMode.manage;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_state == null) {
      _state = EntityListState(
        context.read<RepositoryRegistry>().of(widget.entity),
      );
      _search.text = _query.keyword;
      _load();
      _loadOptions();
    }
  }

  @override
  void didUpdateWidget(covariant EntityListScreen old) {
    super.didUpdateWidget(old);
    if (old.uri != widget.uri) {
      _selected.clear();
      if (_search.text != _query.keyword) _search.text = _query.keyword;
      _load();
    }
  }

  Future<void> _load() async {
    await _state!.load(_query);
    _normalizePage();
  }

  void _normalizePage() {
    if (mounted &&
        !_state!.loading &&
        _state!.error == null &&
        _state!.page != null &&
        _query.page > _state!.page!.totalPages) {
      _navigate(_query.copyWith(page: _state!.page!.totalPages));
    }
  }

  Future<void> _loadOptions() async {
    setState(() {
      _optionsLoading = true;
      _optionsError = null;
    });
    try {
      final d = definitionOf(widget.entity);
      final result = await context.read<RepositoryRegistry>().options(
        d.filterFields.map((k) => d.field(k)?.reference).whereType<String>(),
      );
      if (mounted) _options = result;
    } on ApiError catch (e) {
      if (mounted) _optionsError = e;
    } finally {
      if (mounted) setState(() => _optionsLoading = false);
    }
  }

  void _navigate(ListQuery query) {
    if (mounted) {
      context.go(
        Uri(
          path: widget.uri.path,
          queryParameters: query.parameters.isEmpty ? null : query.parameters,
        ).toString(),
      );
    }
  }

  void _change(ListQuery query) {
    _debounce?.cancel();
    if (query.keyword != _query.keyword) {
      _debounce = Timer(
        const Duration(milliseconds: 350),
        () => _navigate(query),
      );
    } else {
      _navigate(query);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _state?.dispose();
    _search.dispose();
    super.dispose();
  }

  String _detail(EntityRecord item) => switch (widget.mode) {
    EntityListMode.catalog => '/catalog/${item.id}',
    EntityListMode.myRentals => '/my-rentals/${item.id}',
    _ => '/manage/${widget.entity}/${item.id}',
  };
  String _edit(EntityRecord item) => widget.mode == EntityListMode.myRentals
      ? '/my-rentals/${item.id}/edit'
      : '/manage/${widget.entity}/${item.id}/edit';
  Future<void> _act(String action, EntityRecord item) async {
    if (_state!.busy) return;
    if (action == 'view') {
      context.go(_detail(item));
      return;
    }
    if (action == 'edit') {
      context.go(_edit(item));
      return;
    }
    if (action == 'book') {
      context.go('/book?equipment=${item.id}');
      return;
    }
    final (title, message, button) = switch (action) {
      'soft' => (
        'Удалить запись?',
        '«${item.label}» будет перемещена в корзину. Её можно восстановить.',
        'Удалить',
      ),
      'hard' => (
        'Удалить навсегда?',
        '«${item.label}» будет удалена окончательно. Восстановление будет невозможно.',
        'Удалить навсегда',
      ),
      'cancel' => (
        'Отменить бронирование?',
        'Снаряжение станет доступно другим клиентам.',
        'Отменить бронирование',
      ),
      'issue' => (
        'Выдать снаряжение?',
        'Подтвердите, что комплект проверен, оплата и залог приняты в пункте проката.',
        'Выдать',
      ),
      'return' => (
        'Принять возврат?',
        'Подтвердите приёмку снаряжения. Доплата за просрочку будет рассчитана автоматически.',
        'Принять возврат',
      ),
      _ => (
        'Восстановить запись?',
        '«${item.label}» снова появится среди действующих записей.',
        'Восстановить',
      ),
    };
    if (!await confirmAction(
      context,
      title: title,
      message: message,
      confirm: button,
      destructive: action == 'hard',
    )) {
      return;
    }
    if (!mounted) return;
    final rental = context.read<RentalService>();
    try {
      await _state!.mutate(() async {
        switch (action) {
          case 'soft':
            await _state!.repository.softDelete(item.id);
          case 'hard':
            await _state!.repository.hardDelete(item.id);
          case 'restore':
            await _state!.repository.restore(item.id);
          default:
            await rental.action(item.id, action);
        }
      });
      if (mounted) {
        _selected.remove(item.id);
        showNotice(context, 'Действие выполнено');
        _normalizePage();
      }
    } on ApiError catch (e) {
      if (mounted) showNotice(context, e.message);
    }
  }

  Future<void> _bulkDelete() async {
    final ids = _selected.toList();
    if (ids.isEmpty || _state!.busy) return;
    if (!await confirmAction(
      context,
      title: 'Удалить ${ids.length} записей?',
      message:
          'Выбранные записи будут перемещены в корзину. При конфликте операция отменяется для всей группы.',
      confirm: 'Удалить',
    )) {
      return;
    }
    if (!mounted) return;
    try {
      await _state!.mutate(() async {
        await _state!.repository.deleteMany(ids);
      });
      if (mounted) {
        setState(() => _selected.clear());
        showNotice(context, 'Записи перемещены в корзину');
        _normalizePage();
      }
    } on ApiError catch (e) {
      if (mounted) showNotice(context, e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = definitionOf(widget.entity),
        role = context.watch<AuthState>().role;
    final title = switch (widget.mode) {
      EntityListMode.catalog => 'Каталог снаряжения',
      EntityListMode.myRentals => 'Мои аренды',
      EntityListMode.desk => 'Выдача и возврат',
      _ => d.title,
    };
    final canCreate = _manage || widget.mode == EntityListMode.myRentals;
    return PageFrame(
      title: title,
      subtitle: switch (widget.mode) {
        EntityListMode.myRentals =>
          'Ваши бронирования, даты поездок и история аренды.',
        EntityListMode.desk =>
          'Выдавайте готовые комплекты и оформляйте возвраты.',
        EntityListMode.catalog =>
          'Подберите снаряжение для своего следующего маршрута.',
        _ => 'Поиск, фильтры и сортировка сохраняются в адресе страницы.',
      },
      actions: [
        if (widget.mode == EntityListMode.catalog)
          FilledButton.icon(
            onPressed: () => context.go(
              role == AppRole.client ? '/book' : '/manage/equipment',
            ),
            icon: Icon(role == AppRole.client ? Icons.hiking : Icons.tune),
            label: Text(
              role == AppRole.client ? 'Забронировать' : 'Управлять каталогом',
            ),
          ),
        if (canCreate)
          FilledButton.icon(
            onPressed: () => context.go(
              widget.entity == 'rentals'
                  ? '/book'
                  : '/manage/${widget.entity}/new',
            ),
            icon: const Icon(Icons.add),
            label: Text(
              widget.entity == 'rentals' ? 'Новое бронирование' : 'Добавить',
            ),
          ),
      ],
      child: _state == null
          ? const LoadingState()
          : AnimatedBuilder(
              animation: _state!,
              builder: (context, _) {
                final state = _state!, page = state.page;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListFilters(
                      definition: d,
                      query: _query,
                      onChanged: _change,
                      search: _search,
                      options: _options,
                      allowArchive: _manage,
                      optionsLoading: _optionsLoading,
                    ),
                    if (_optionsError != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Не удалось загрузить справочники фильтров: ${_optionsError!.message}',
                            ),
                          ),
                          TextButton(
                            onPressed: _loadOptions,
                            child: const Text('Повторить'),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 20),
                    if (_manage && _selected.isNotEmpty) ...[
                      Wrap(
                        spacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('Выбрано: ${_selected.length}'),
                          OutlinedButton.icon(
                            onPressed: state.busy ? null : _bulkDelete,
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Удалить выбранные'),
                          ),
                          TextButton(
                            onPressed: state.busy
                                ? null
                                : () => setState(() => _selected.clear()),
                            child: const Text('Снять выделение'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (state.busy)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: LinearProgressIndicator(),
                      ),
                    if (state.loading)
                      const LoadingState()
                    else if (state.error != null)
                      ErrorState(error: state.error!, onRetry: _load)
                    else if (page == null || page.items.isEmpty)
                      EmptyState(
                        title:
                            _query.keyword.isNotEmpty ||
                                _query.filters.isNotEmpty
                            ? 'Ничего не найдено'
                            : 'Записей пока нет',
                        message: _query.deleted == DeletedFilter.deleted
                            ? 'Корзина пуста.'
                            : 'Измените условия поиска или добавьте запись.',
                      )
                    else ...[
                      LayoutBuilder(
                        builder: (context, c) {
                          if (widget.mode == EntityListMode.catalog) {
                            return Wrap(
                              spacing: 16,
                              runSpacing: 16,
                              children: [
                                for (final item in page.items)
                                  SizedBox(
                                    width: c.maxWidth >= 1080
                                        ? (c.maxWidth - 32) / 3
                                        : c.maxWidth >= 680
                                        ? (c.maxWidth - 16) / 2
                                        : c.maxWidth,
                                    child: _equipmentCard(item, role),
                                  ),
                              ],
                            );
                          }
                          if (c.maxWidth >= 1200) {
                            return Card(
                              child: DataTable(
                                columnSpacing: 20,
                                horizontalMargin: 18,
                                showCheckboxColumn: _manage,
                                columns: [
                                  for (final field in d.columns)
                                    DataColumn(
                                      label: ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 150,
                                        ),
                                        child: Text(
                                          d.labelOf(field),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  const DataColumn(label: Text('Действия')),
                                ],
                                rows: [
                                  for (final item in page.items)
                                    DataRow(
                                      selected: _selected.contains(item.id),
                                      onSelectChanged:
                                          _manage &&
                                              !item.isDeleted &&
                                              !state.busy
                                          ? (selected) => setState(() {
                                              if (selected ?? false) {
                                                _selected.add(item.id);
                                              } else {
                                                _selected.remove(item.id);
                                              }
                                            })
                                          : null,
                                      cells: [
                                        for (final field in d.columns)
                                          DataCell(
                                            ConstrainedBox(
                                              constraints: BoxConstraints(
                                                maxWidth:
                                                    field == d.columns.first
                                                    ? 220
                                                    : 150,
                                              ),
                                              child: RecordValue(
                                                record: item,
                                                field: field,
                                                definition: d,
                                              ),
                                            ),
                                          ),
                                        DataCell(
                                          Wrap(children: _actions(item, role)),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            );
                          }
                          return Wrap(
                            spacing: 16,
                            runSpacing: 16,
                            children: [
                              for (final item in page.items)
                                SizedBox(
                                  width: c.maxWidth >= 760
                                      ? (c.maxWidth - 16) / 2
                                      : c.maxWidth,
                                  child: Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(20),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              if (_manage && !item.isDeleted)
                                                Checkbox(
                                                  value: _selected.contains(
                                                    item.id,
                                                  ),
                                                  semanticLabel:
                                                      'Выбрать ${item.label}',
                                                  onChanged: state.busy
                                                      ? null
                                                      : (selected) => setState(
                                                          () {
                                                            if (selected ??
                                                                false) {
                                                              _selected.add(
                                                                item.id,
                                                              );
                                                            } else {
                                                              _selected.remove(
                                                                item.id,
                                                              );
                                                            }
                                                          },
                                                        ),
                                                ),
                                              Expanded(
                                                child: Text(
                                                  widget.entity == 'rentals'
                                                      ? 'Аренда №${item.id}'
                                                      : item.label,
                                                  style: Theme.of(
                                                    context,
                                                  ).textTheme.titleMedium,
                                                  maxLines: 2,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (item.isDeleted)
                                                const Chip(
                                                  label: Text('В корзине'),
                                                ),
                                            ],
                                          ),
                                          const SizedBox(height: 12),
                                          for (final field in d.columns.where(
                                            (key) =>
                                                key != 'id' &&
                                                key != d.columns.first,
                                          ))
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 10,
                                              ),
                                              child: Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      d.labelOf(field),
                                                      style: TextStyle(
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .onSurfaceVariant,
                                                        fontSize: 13,
                                                      ),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Flexible(
                                                    child: RecordValue(
                                                      record: item,
                                                      field: field,
                                                      definition: d,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          if (item['status'] == 'issued' &&
                                              parseDate(
                                                    item['end_on'],
                                                  )?.isBefore(
                                                    businessToday(),
                                                  ) ==
                                                  true)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 12,
                                              ),
                                              child: Text(
                                                'Просрочен возврат',
                                                style: TextStyle(
                                                  color: Theme.of(
                                                    context,
                                                  ).colorScheme.error,
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                            ),
                                          Wrap(
                                            spacing: 4,
                                            runSpacing: 8,
                                            children: _actions(item, role),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      PaginationBar(
                        page: page,
                        query: _query,
                        onChanged: _navigate,
                      ),
                    ],
                  ],
                );
              },
            ),
    );
  }

  List<Widget> _actions(EntityRecord item, AppRole role) {
    final busy = _state!.busy;
    Widget action(String code, IconData icon, String label) => IconButton(
      tooltip: label,
      onPressed: busy ? null : () => _act(code, item),
      icon: Icon(icon, size: 21),
    );
    return [
      action('view', Icons.open_in_new_outlined, 'Подробнее'),
      if (item.isDeleted && _manage) ...[
        action('restore', Icons.restore, 'Восстановить'),
        if (role.canDeleteForever)
          action('hard', Icons.delete_forever_outlined, 'Удалить навсегда'),
      ] else if (!item.isDeleted) ...[
        if ((_manage || widget.mode == EntityListMode.myRentals) &&
            (widget.entity != 'rentals' || item['status'] == 'reserved'))
          action('edit', Icons.edit_outlined, 'Редактировать'),
        if (_manage) action('soft', Icons.delete_outline, 'В корзину'),
        if (widget.mode == EntityListMode.myRentals &&
            item['status'] == 'reserved')
          action('cancel', Icons.event_busy_outlined, 'Отменить бронирование'),
        if (widget.mode == EntityListMode.desk && item['status'] == 'reserved')
          FilledButton(
            onPressed: busy ? null : () => _act('issue', item),
            child: const Text('Выдать'),
          ),
        if (widget.mode == EntityListMode.desk && item['status'] == 'issued')
          FilledButton(
            onPressed: busy ? null : () => _act('return', item),
            child: const Text('Принять возврат'),
          ),
      ],
    ];
  }

  Widget _equipmentCard(EntityRecord item, AppRole role) {
    final category = (item['category_id'] as num?)?.toInt();
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 132,
            color: const Color(0xFFE9EFE3),
            child: EquipmentIllustration(category: category),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  recordValue(item, 'category_id'),
                  style: const TextStyle(
                    color: Color(0xFF61725E),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 48,
                  child: Text(
                    item.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 40,
                  child: Text(
                    '${item['description'] ?? ''}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF61725E),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      money(item['daily_rate']),
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Text('/ сутки', style: TextStyle(fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Залог ${money(item['deposit'])}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF61725E),
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () => _act('view', item),
                      child: const Text('Подробнее'),
                    ),
                    if (role == AppRole.client)
                      FilledButton(
                        onPressed: () => _act('book', item),
                        child: const Text('В поход'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
