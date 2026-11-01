import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api_error.dart';
import '../core/dates.dart';
import '../models/app_role.dart';
import '../repositories/rental_service.dart';
import '../state/auth_state.dart';
import '../widgets/confirm_action.dart';
import '../widgets/data_states.dart';
import '../widgets/page_frame.dart';
import '../widgets/status_badge.dart';

class AdminOverviewScreen extends StatefulWidget {
  const AdminOverviewScreen({super.key});
  @override
  State<AdminOverviewScreen> createState() => _AdminOverviewScreenState();
}

class _AdminOverviewScreenState extends State<AdminOverviewScreen> {
  Map<String, dynamic>? _data;
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
      final result = await context.read<RentalService>().summary();
      if (mounted) _data = result;
    } on ApiError catch (e) {
      if (mounted) _error = e;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Обзор проката',
    subtitle: 'Снаряжение, текущие аренды и стоимость завершённых заказов.',
    actions: [
      OutlinedButton.icon(
        onPressed: _loading ? null : _load,
        icon: const Icon(Icons.refresh),
        label: const Text('Обновить'),
      ),
    ],
    child: _loading
        ? const LoadingState()
        : _error != null
        ? ErrorState(error: _error!, onRetry: _load)
        : LayoutBuilder(
            builder: (context, c) {
              final data = _data!,
                  width = c.maxWidth >= 1000
                      ? (c.maxWidth - 48) / 4
                      : c.maxWidth >= 600
                      ? (c.maxWidth - 16) / 2
                      : c.maxWidth;
              final metrics = [
                (
                  'Моделей снаряжения',
                  '${data['equipment']}',
                  Icons.backpack_outlined,
                ),
                ('Экземпляров', '${data['units']}', Icons.inventory_2_outlined),
                (
                  'Текущих аренд',
                  '${data['active_rentals']}',
                  Icons.calendar_month_outlined,
                ),
                ('Клиентов', '${data['customers']}', Icons.people_outline),
              ];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [
                      for (final metric in metrics)
                        SizedBox(
                          width: width,
                          child: Card(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    metric.$3,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                  const SizedBox(height: 24),
                                  Text(
                                    metric.$2,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.headlineLarge,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(metric.$1),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Стоимость завершённых аренд'),
                          const SizedBox(height: 10),
                          Text(
                            money(data['completed_cost']),
                            style: Theme.of(context).textTheme.headlineLarge,
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Аренда, услуги и начисленная доплата за просрочку. Возвратные залоги не включены.',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  if ((data['overdue'] as num) > 0) ...[
                    Card(
                      color: const Color(0xFFFFEECF),
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          'Ожидают просроченный возврат: ${data['overdue']}. Выданное снаряжение остаётся недоступным до приёмки.',
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Статусы аренд',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          if ((data['statuses'] as Map).isEmpty)
                            const Text('Аренд пока нет.')
                          else
                            Wrap(
                              spacing: 20,
                              runSpacing: 16,
                              children: [
                                for (final entry
                                    in (data['statuses'] as Map).entries)
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      StatusBadge('${entry.key}'),
                                      const SizedBox(width: 10),
                                      Text(
                                        '${entry.value}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Снаряжение по пунктам',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          for (final location in data['locations'] as List)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text('${location['name']}'),
                                      ),
                                      Text('${location['units']} экз.'),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  LinearProgressIndicator(
                                    value:
                                        (location['units'] as num) /
                                        ((data['units'] as num) > 0
                                            ? (data['units'] as num)
                                            : 1),
                                    minHeight: 8,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
  );
}

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});
  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen> {
  int _roleVersion = 0;
  List<Map<String, dynamic>>? _users;
  ApiError? _error;
  bool _loading = true, _busy = false, _started = false;
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
      final data = await context.read<RentalService>().users();
      if (mounted) _users = data;
    } on ApiError catch (e) {
      if (mounted) _error = e;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _change(Map<String, dynamic> user, String role) async {
    if (!await confirmAction(
      context,
      title: 'Изменить роль?',
      message:
          '${user['email']}: ${AppRole.parse(user['role']).label} → ${AppRole.parse(role).label}. Изменятся доступные действия пользователя.',
      confirm: 'Изменить',
    )) {
      if (mounted) setState(() => _roleVersion++);
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<RentalService>().changeRole('${user['id']}', role);
      await _load();
      if (mounted) showNotice(context, 'Роль изменена');
    } on ApiError catch (e) {
      if (mounted) showNotice(context, e.message);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _roleVersion++;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Пользователи и роли',
    subtitle:
        'Права проверяются сервером при каждом обращении. Собственную роль изменить нельзя.',
    child: _loading
        ? const LoadingState()
        : _error != null
        ? ErrorState(error: _error!, onRetry: _load)
        : _users!.isEmpty
        ? const EmptyState()
        : Column(
            children: [
              if (_busy) const LinearProgressIndicator(),
              for (final user in _users!)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: LayoutBuilder(
                        builder: (context, c) => Wrap(
                          spacing: 20,
                          runSpacing: 16,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            SizedBox(
                              width: c.maxWidth > 650
                                  ? c.maxWidth - 260
                                  : c.maxWidth,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${user['full_name']}',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 4),
                                  Text('${user['email']}'),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Создан: ${displayDate(user['created_at'])}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 220,
                              child: DropdownButtonFormField<String>(
                                isExpanded: true,
                                key: ValueKey(
                                  '${user['id']}:${user['role']}:$_roleVersion',
                                ),
                                initialValue: '${user['role']}',
                                decoration: const InputDecoration(
                                  labelText: 'Роль',
                                ),
                                items: [
                                  for (final role in AppRole.values)
                                    DropdownMenuItem(
                                      value: role.code,
                                      child: Text(
                                        role.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged:
                                    _busy ||
                                        user['id'] ==
                                            context.read<AuthState>().userId
                                    ? null
                                    : (role) {
                                        if (role != null &&
                                            role != user['role']) {
                                          _change(user, role);
                                        }
                                      },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
  );
}
