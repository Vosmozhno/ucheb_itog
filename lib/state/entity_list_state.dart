import 'package:flutter/foundation.dart';
import '../core/api_error.dart';
import '../models/entity_record.dart';
import '../models/list_query.dart';
import '../models/page_result.dart';
import '../repositories/entity_repository.dart';

class EntityListState extends ChangeNotifier {
  EntityListState(this.repository);
  final EntityRepository<EntityRecord, ListQuery> repository;
  ListQuery query = const ListQuery();
  PageResult<EntityRecord>? page;
  bool loading = true, busy = false, _disposed = false;
  ApiError? error;
  CancelAction? _cancel;
  int _generation = 0;
  Future<void> load(ListQuery value) async {
    query = value;
    final generation = ++_generation;
    _cancel?.call();
    _cancel = null;
    loading = true;
    error = null;
    if (!_disposed) notifyListeners();
    try {
      final repo = repository;
      final result = repo is CancelableEntityRepository<EntityRecord, ListQuery>
          ? await repo.findCancelable(
              value,
              registerCancel: (cancel) {
                if (generation == _generation && !_disposed) {
                  _cancel = cancel;
                } else {
                  cancel();
                }
              },
            )
          : await repo.find(value);
      if (_disposed || generation != _generation) return;
      page = result;
    } on ApiError catch (e) {
      if (_disposed ||
          generation != _generation ||
          e.kind == ApiErrorKind.cancelled) {
        return;
      }
      error = e;
    } on Object {
      if (_disposed || generation != _generation) return;
      error = const ApiError(
        ApiErrorKind.unknown,
        'Не удалось загрузить список.',
      );
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> mutate(Future<void> Function() operation) async {
    if (busy) return;
    busy = true;
    if (!_disposed) notifyListeners();
    try {
      await operation();
      await load(query);
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel?.call();
    super.dispose();
  }
}
