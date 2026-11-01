import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/api_error.dart';
import '../data/entity_definitions.dart';
import '../models/entity_record.dart';
import '../repositories/repository_registry.dart';
import '../state/record_form_controller.dart';
import '../widgets/confirm_action.dart';
import '../widgets/data_states.dart';
import '../widgets/page_frame.dart';
import '../widgets/record_fields.dart';

class RecordEditorScreen extends StatefulWidget {
  const RecordEditorScreen({
    super.key,
    required this.entity,
    this.id,
    this.back,
  });
  final String entity;
  final int? id;
  final String? back;
  @override
  State<RecordEditorScreen> createState() => _RecordEditorScreenState();
}

class _RecordEditorScreenState extends State<RecordEditorScreen> {
  RecordFormController? _controller;
  Map<String, List<EntityRecord>> _options = {};
  ApiError? _error;
  bool _loading = true, _busy = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller == null && _loading) _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final registry = context.read<RepositoryRegistry>(),
          definition = definitionOf(widget.entity);
      final record = widget.id == null
          ? null
          : await registry.of(widget.entity).findById(widget.id!);
      if (widget.id != null && record == null) {
        throw const ApiError(ApiErrorKind.notFound, 'Запись не найдена.');
      }
      if (record?.isDeleted ?? false) {
        throw const ApiError(
          ApiErrorKind.conflict,
          'Сначала восстановите запись из корзины.',
        );
      }
      final options = await registry.options(
        definition.fields.map((f) => f.reference).whereType<String>(),
      );
      if (!mounted) return;
      _controller?.dispose();
      _controller = RecordFormController(definition, record?.values ?? {});
      _options = options;
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
    final controller = _controller!;
    if (_busy || !controller.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final repo = context.read<RepositoryRegistry>().of(widget.entity);
      final item = EntityRecord({
        ...controller.payload,
        if (widget.id != null) 'id': widget.id,
      });
      final result = widget.id == null
          ? await repo.create(item)
          : await repo.update(item);
      if (!mounted) return;
      showNotice(context, 'Запись сохранена');
      context.go('/manage/${widget.entity}/${result.id}', extra: widget.back);
    } on ApiError catch (e) {
      if (mounted) {
        controller.serverErrors(e.fields);
        setState(() => _error = e);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = definitionOf(widget.entity);
    return PageFrame(
      title: widget.id == null
          ? 'Добавить: ${d.singular.toLowerCase()}'
          : 'Редактирование: ${d.singular.toLowerCase()}',
      subtitle: 'Поля со звёздочкой обязательны для заполнения.',
      maxWidth: 960,
      child: _loading
          ? const LoadingState()
          : _controller == null
          ? ErrorState(error: _error!, onRetry: _load)
          : Card(
              child: Padding(
                padding: EdgeInsets.all(
                  MediaQuery.sizeOf(context).width < 600 ? 16 : 28,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_error != null) ...[
                      ErrorNotice(message: _error!.message),
                      const SizedBox(height: 20),
                    ],
                    RecordFields(
                      controller: _controller!,
                      options: _options,
                      disabled: _busy,
                    ),
                    const SizedBox(height: 28),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: _busy ? null : _save,
                          icon: const Icon(Icons.check),
                          label: Text(_busy ? 'Сохранение…' : 'Сохранить'),
                        ),
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => context.go(
                                  widget.back ?? '/manage/${widget.entity}',
                                ),
                          child: const Text('Отмена'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
