import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api_error.dart';
import '../core/dates.dart';
import '../data/entity_definitions.dart';
import '../models/entity_record.dart';
import '../repositories/repository_registry.dart';
import '../repositories/rental_service.dart';
import '../state/auth_state.dart';
import '../state/record_form_controller.dart';
import '../widgets/confirm_action.dart';
import '../widgets/data_states.dart';
import '../widgets/page_frame.dart';
import '../widgets/record_fields.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  RecordFormController? _controller;
  EntityRecord? _card;
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
      final registry = context.read<RepositoryRegistry>();
      final contacts = await registry.of('customers').all();
      final cards = await registry.of('loyalty_cards').all();
      if (contacts.isEmpty) {
        throw const ApiError(
          ApiErrorKind.notFound,
          'Профиль клиента отсутствует. Обратитесь к администратору.',
        );
      }
      if (!mounted) return;
      _controller?.dispose();
      _controller = RecordFormController(
        definitionOf('customers'),
        contacts.first.values,
      );
      _card = cards.firstOrNull;
    } on ApiError catch (e) {
      if (mounted) _error = e;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_controller!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await context.read<RentalService>().updateContacts(_controller!.payload);
      if (!mounted) return;
      await context.read<AuthState>().reloadProfile();
      if (mounted) showNotice(context, 'Контакты обновлены');
    } on ApiError catch (e) {
      if (mounted) {
        _controller!.serverErrors(e.fields);
        _error = e;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Мой профиль',
    subtitle: 'Контакты для связи и ваша карта лояльности.',
    maxWidth: 960,
    child: _loading
        ? const LoadingState()
        : _controller == null
        ? ErrorState(error: _error!, onRetry: _load)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_card != null) ...[
                Card(
                  color: const Color(0xFFE5EEE3),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.card_membership_outlined),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Карта ${_card!['number']}',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Скидка ${_card!['discount_percent']} % · действует до ${displayDate(_card!['expires_on'])}',
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Скидка карты суммируется со скидкой за продолжительность. Общая скидка на снаряжение — не более 20%.',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_error != null) ...[
                        ErrorNotice(message: _error!.message),
                        const SizedBox(height: 20),
                      ],
                      RecordFields(
                        controller: _controller!,
                        options: const {},
                        disabled: _busy,
                      ),
                      const SizedBox(height: 24),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _save,
                          icon: const Icon(Icons.check),
                          label: Text(
                            _busy ? 'Сохранение…' : 'Сохранить контакты',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
  );
}
