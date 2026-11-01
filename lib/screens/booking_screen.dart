import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/api_error.dart';
import '../core/dates.dart';
import '../data/entity_definitions.dart';
import '../models/app_role.dart';
import '../models/entity_record.dart';
import '../models/rental_quote.dart';
import '../repositories/rental_service.dart';
import '../repositories/repository_registry.dart';
import '../state/auth_state.dart';
import '../state/record_form_controller.dart';
import '../widgets/confirm_action.dart';
import '../widgets/data_states.dart';
import '../widgets/page_frame.dart';
import '../widgets/quote_panel.dart';
import '../widgets/record_fields.dart';

class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key, this.id, this.equipmentId});
  final int? id, equipmentId;
  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  RecordFormController? _controller;
  Map<String, List<EntityRecord>> _options = {};
  List<EntityRecord>? _available;
  RentalQuote? _quote;
  ApiError? _error;
  bool _loading = true, _busy = false, _started = false;
  String _dateKey = '';
  int _formRevision = 0;
  int? _equipmentFilter;
  String get _dates =>
      '${_controller?.values['start_on']}/${_controller?.values['end_on']}/${_controller?.values['location_id']}';
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _equipmentFilter = widget.equipmentId;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final registry = context.read<RepositoryRegistry>();
      final record = widget.id == null
          ? null
          : await registry.of('rentals').findById(widget.id!);
      if (widget.id != null && record == null) {
        throw const ApiError(
          ApiErrorKind.notFound,
          'Аренда не найдена или недоступна.',
        );
      }
      if (record != null &&
          (record.isDeleted || record['status'] != 'reserved')) {
        throw const ApiError(
          ApiErrorKind.conflict,
          'Изменять можно только действующее бронирование до выдачи.',
        );
      }
      final options = await registry.options([
        'customers',
        'locations',
        'services',
        'loyalty_cards',
      ]);
      if (!mounted) return;
      final client = context.read<AuthState>().role == AppRole.client;
      final initial = <String, dynamic>{
        ...?record?.values,
        'unit_ids': record?.unitIds ?? <int>[],
        'service_ids': record?.serviceIds ?? <int>[],
        if (client) 'customer_id': options['customers']?.firstOrNull?.id,
        if (record == null && options['locations']?.isNotEmpty == true)
          'location_id': options['locations']!.first.id,
      };
      _controller?.removeListener(_changed);
      _controller?.dispose();
      _controller = RecordFormController(definitionOf('rentals'), initial)
        ..addListener(_changed);
      _options = options;
      _dateKey = _dates;
      _formRevision = _controller!.revision;
      if (record != null) {
        _available = (record['rental_items'] as List)
            .map(
              (item) => EntityRecord({
                'id': item['unit_id'],
                'inventory_code': item['inventory_code'],
                'equipment_name': item['equipment_name'],
                'daily_rate': item['daily_rate'],
                'deposit': item['deposit'],
              }),
            )
            .toList();
      }
    } on ApiError catch (e) {
      if (mounted) _error = e;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changed() {
    if (_controller == null ||
        !mounted ||
        _controller!.revision == _formRevision) {
      return;
    }
    _formRevision = _controller!.revision;
    if (_dateKey != _dates) {
      _dateKey = _dates;
      _available = null;
      _controller!.values['unit_ids'] = <int>[];
      _controller!.errors.remove('unit_ids');
    }
    setState(() => _quote = null);
  }

  @override
  void dispose() {
    _controller?.removeListener(_changed);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _checkAvailability() async {
    final ctrl = _controller!;
    final start = parseDate(ctrl.values['start_on']),
        end = parseDate(ctrl.values['end_on']);
    final location = int.tryParse('${ctrl.values['location_id']}');
    if (start == null ||
        end == null ||
        !end.isAfter(start) ||
        end.difference(start).inDays > 90 ||
        location == null) {
      ctrl.serverErrors({
        if (start == null) 'start_on': 'Укажите дату',
        if (end == null ||
            start == null ||
            !end.isAfter(start) ||
            end.difference(start).inDays > 90)
          'end_on': 'Продолжительность: от 1 до 90 суток',
        if (location == null) 'location_id': 'Выберите пункт',
      });
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _quote = null;
    });
    try {
      final result = await context.read<RentalService>().available(
        start: isoDate(start),
        end: isoDate(end),
        location: location,
        rentalId: widget.id,
      );
      if (!mounted) return;
      _available = result;
      final previous = List<int>.from(ctrl.values['unit_ids'] as List);
      ctrl.values['unit_ids'] = previous
          .where((id) => result.any((e) => e.id == id))
          .toList();
      if (previous.length != (ctrl.values['unit_ids'] as List).length) {
        ctrl.serverErrors({
          'unit_ids':
              'Часть выбранного снаряжения стала недоступна. Проверьте список.',
        });
      }
    } on ApiError catch (e) {
      if (mounted) {
        ctrl.serverErrors(e.fields);
        _error = e;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _calculate() async {
    final ctrl = _controller!;
    if (_busy || !ctrl.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final quote = await context.read<RentalService>().quote(
        ctrl.payload,
        id: widget.id,
      );
      if (mounted) _quote = quote;
    } on ApiError catch (e) {
      if (mounted) {
        ctrl.serverErrors(e.fields);
        _error = e;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    final ctrl = _controller!;
    if (_busy || _quote == null || !ctrl.validate()) return;
    final quote = _quote!;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = context.read<RepositoryRegistry>().of('rentals');
      final item = EntityRecord({
        ...ctrl.payload,
        'expected_total': quote.total,
        if (widget.id != null) 'id': widget.id,
      });
      final result = widget.id == null
          ? await repo.create(item)
          : await repo.update(item);
      if (!mounted) return;
      showNotice(
        context,
        widget.id == null
            ? 'Снаряжение забронировано'
            : 'Бронирование обновлено',
      );
      context.go(
        '${context.read<AuthState>().role == AppRole.client ? '/my-rentals' : '/manage/rentals'}/${result.id}',
      );
    } on ApiError catch (e) {
      if (mounted) {
        ctrl.serverErrors(e.fields);
        _error = e;
        _quote = null;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  RentalQuote? _preview() {
    if (_controller == null || _available == null) return null;
    final v = _controller!.payload,
        ids = List<int>.from(_controller!.values['unit_ids'] as List? ?? []);
    final first = parseDate(v['start_on']), last = parseDate(v['end_on']);
    if (first == null || last == null || ids.isEmpty) return null;
    final days = last.difference(first).inDays;
    if (days < 1 || days > 90) return null;
    final chosen = _available!.where((e) => ids.contains(e.id)).toList();
    if (chosen.length != ids.length) return null;
    final services = List<int>.from(v['service_ids'] as List);
    final extra = (_options['services'] ?? [])
        .where((e) => services.contains(e.id))
        .fold<int>(0, (a, e) => a + (e['price'] as num).toInt());
    var loyalty = 0;
    final today = businessToday();
    for (final card in _options['loyalty_cards'] ?? <EntityRecord>[]) {
      final issued = parseDate(card['issued_on']),
          expires = parseDate(card['expires_on']);
      if (card['customer_id'] == v['customer_id'] &&
          issued != null &&
          expires != null &&
          !today.isBefore(issued) &&
          !today.isAfter(expires)) {
        loyalty = (card['discount_percent'] as num).toInt();
      }
    }
    final price = TariffPreview.calculate(
      days: days,
      dailyRate: chosen.fold<int>(
        0,
        (a, e) => a + (e['daily_rate'] as num).toInt(),
      ),
      loyalty: loyalty,
      services: extra,
      deposit: chosen.fold<int>(0, (a, e) => a + (e['deposit'] as num).toInt()),
    );
    return RentalQuote({
      'days': days,
      'discount_percent': price.discount,
      'base_cost': price.base,
      'discount_amount': price.base - (price.total - extra),
      'services_cost': extra,
      'total_cost': price.total,
      'deposit': price.deposit,
      'due_now': price.dueNow,
    });
  }

  @override
  Widget build(BuildContext context) {
    final client = context.watch<AuthState>().role == AppRole.client;
    final quote = _quote ?? _preview();
    final visible = _equipmentFilter == null
        ? _available
        : _available
              ?.where((e) => e['equipment_id'] == _equipmentFilter)
              .toList();
    return PageFrame(
      title: widget.id == null ? 'Собрать свой поход' : 'Изменить бронирование',
      subtitle:
          'Выберите пункт и даты. Проверьте доступность снаряжения и получите расчёт.',
      maxWidth: 1040,
      child: _loading
          ? const LoadingState()
          : _controller == null
          ? ErrorState(error: _error!, onRetry: _load)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) ...[
                  ErrorNotice(message: _error!.message),
                  const SizedBox(height: 16),
                ],
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(
                      MediaQuery.sizeOf(context).width < 600 ? 16 : 28,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.explore_outlined),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Ваш маршрут начинается здесь',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          'Дата возврата не включается в стоимость: с 10-го по 12-е — двое суток. Скидка за 7+ суток — 10%, за 14+ — 15%; вместе с картой — не более 20%.',
                        ),
                        const SizedBox(height: 20),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _checkAvailability,
                              icon: const Icon(Icons.event_available_outlined),
                              label: Text(
                                _busy ? 'Подождите…' : 'Проверить доступность',
                              ),
                            ),
                            if (_equipmentFilter != null)
                              TextButton(
                                onPressed: () =>
                                    setState(() => _equipmentFilter = null),
                                child: const Text('Показать все модели'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        RecordFields(
                          controller: _controller!,
                          options: _options,
                          disabled: _busy,
                          hidden: client ? {'customer_id'} : {},
                          availableUnits: visible,
                          unitsHint:
                              'Можно выбрать несколько экземпляров. Доступность проверяется повторно при бронировании.',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                if (quote != null) ...[
                  QuotePanel(quote: quote, confirmed: _quote != null),
                  const SizedBox(height: 20),
                ],
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _calculate,
                      icon: const Icon(Icons.calculate_outlined),
                      label: const Text('Рассчитать стоимость'),
                    ),
                    FilledButton.icon(
                      onPressed: _busy || _quote == null ? null : _save,
                      icon: const Icon(Icons.check),
                      label: Text(
                        widget.id == null
                            ? 'Забронировать'
                            : 'Сохранить изменения',
                      ),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => context.go(
                              client ? '/my-rentals' : '/manage/rentals',
                            ),
                      child: const Text('Отмена'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
