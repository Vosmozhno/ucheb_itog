import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/api_error.dart';
import '../core/dates.dart';
import '../data/entity_definitions.dart';
import '../models/app_role.dart';
import '../models/entity_record.dart';
import '../models/rental_quote.dart';
import '../repositories/repository_registry.dart';
import '../state/auth_state.dart';
import '../widgets/data_states.dart';
import '../widgets/page_frame.dart';
import '../widgets/quote_panel.dart';
import '../widgets/record_value.dart';
import '../widgets/status_badge.dart';

class RecordDetailScreen extends StatefulWidget {
  const RecordDetailScreen({
    super.key,
    required this.entity,
    required this.id,
    this.catalog = false,
    this.personal = false,
  });
  final String entity;
  final int id;
  final bool catalog, personal;
  @override
  State<RecordDetailScreen> createState() => _RecordDetailScreenState();
}

class _RecordDetailScreenState extends State<RecordDetailScreen> {
  EntityRecord? _record;
  ApiError? _error;
  bool _loading = true, _started = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final record = await context
          .read<RepositoryRegistry>()
          .of(widget.entity)
          .findById(widget.id);
      if (record == null) {
        throw const ApiError(
          ApiErrorKind.notFound,
          'Запись не найдена или недоступна.',
        );
      }
      if (mounted) _record = record;
    } on ApiError catch (e) {
      if (mounted) _error = e;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final definition = definitionOf(widget.entity),
        role = context.watch<AuthState>().role,
        record = _record;
    final back = widget.catalog
        ? '/catalog'
        : widget.personal
        ? '/my-rentals'
        : '/manage/${widget.entity}';
    return PageFrame(
      title: record == null
          ? definition.singular
          : widget.entity == 'rentals'
          ? 'Аренда №${record.id}'
          : record.label,
      maxWidth: 1040,
      actions: [
        OutlinedButton.icon(
          onPressed: () => context.go(back),
          icon: const Icon(Icons.arrow_back),
          label: const Text('К списку'),
        ),
      ],
      child: _loading
          ? const LoadingState()
          : _error != null
          ? ErrorState(error: _error!, onRetry: _load)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (record!.isDeleted) ...[
                          const Chip(label: Text('В корзине')),
                          const SizedBox(height: 16),
                        ],
                        if (widget.entity == 'rentals') ...[
                          StatusBadge('${record['status']}'),
                          const SizedBox(height: 20),
                        ],
                        for (final field in definition.fields.where(
                          (f) => !['unit_ids', 'service_ids'].contains(f.key),
                        ))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 18),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  field.label,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                SelectableText(
                                  recordValue(
                                    record,
                                    field.key,
                                    definition: definition,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            if (!record.isDeleted &&
                                ((role.canManage && !widget.catalog) ||
                                    widget.personal) &&
                                (widget.entity != 'rentals' ||
                                    record['status'] == 'reserved'))
                              FilledButton.icon(
                                onPressed: () => context.go(
                                  '${widget.personal ? '/my-rentals' : '/manage/${widget.entity}'}/${record.id}/edit',
                                ),
                                icon: const Icon(Icons.edit_outlined),
                                label: const Text('Редактировать'),
                              ),
                            if (widget.catalog && role == AppRole.client)
                              FilledButton.icon(
                                onPressed: () =>
                                    context.go('/book?equipment=${record.id}'),
                                icon: const Icon(Icons.hiking),
                                label: const Text('Забронировать'),
                              ),
                            if (widget.catalog && role.canManage)
                              OutlinedButton(
                                onPressed: () => context.go(
                                  '/manage/equipment/${record.id}/edit',
                                ),
                                child: const Text('Редактировать'),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (widget.entity == 'rentals') ...[
                  const SizedBox(height: 20),
                  _rentalContents(record),
                  const SizedBox(height: 20),
                  QuotePanel(quote: _savedQuote(record)),
                  if ((record['late_fee'] as num) > 0) ...[
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'Доплата за просрочку: ${money(record['late_fee'])}. Тариф — 50% суточной стоимости за каждые сутки после даты возврата.',
                        ),
                      ),
                    ),
                  ],
                  if (record['issued_at'] != null) ...[
                    const SizedBox(height: 12),
                    Text('Выдано: ${displayDate(record['issued_at'])}'),
                  ],
                  if (record['returned_at'] != null) ...[
                    const SizedBox(height: 8),
                    Text('Возвращено: ${displayDate(record['returned_at'])}'),
                  ],
                ],
              ],
            ),
    );
  }

  Widget _rentalContents(EntityRecord record) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Состав аренды', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          for (final item in record['rental_items'] as List)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.backpack_outlined),
              title: Text('${item['equipment_name']}'),
              subtitle: Text(
                '${item['inventory_code']} · ${money(item['daily_rate'])}/сутки',
              ),
            ),
          if ((record['rental_services'] as List).isNotEmpty) ...[
            const Divider(),
            const SizedBox(height: 12),
            for (final service in record['rental_services'] as List)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_circle_outline),
                title: Text('${service['service_name']}'),
                trailing: Text(money(service['price'])),
              ),
          ],
        ],
      ),
    ),
  );
  RentalQuote _savedQuote(EntityRecord record) {
    final days = parseDate(
      record['end_on'],
    )!.difference(parseDate(record['start_on'])!).inDays;
    final base = record['base_cost'] as num,
        discount = record['discount_percent'] as num;
    return RentalQuote({
      ...record.values,
      'days': days,
      'discount_amount': base * discount / 100,
      'due_now': (record['total_cost'] as num) + (record['deposit'] as num),
    });
  }
}
