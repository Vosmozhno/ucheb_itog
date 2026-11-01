import '../models/list_query.dart';
import '../models/page_result.dart';

abstract interface class EntityRepository<T, Q extends ListQuery> {
  int get revision;
  Future<List<T>> all({bool includeDeleted = false});
  Future<PageResult<T>> find(Q query);
  Future<T?> findById(int id);
  Future<T> create(T item);
  Future<T> update(T item);
  Future<void> softDelete(int id);
  Future<void> hardDelete(int id);
  Future<void> restore(int id);
  Future<int> deleteMany(List<int> ids);
}

// Optional capability, independent of a specific HTTP package or backend.
typedef CancelAction = void Function();
typedef RegisterCancellation = void Function(CancelAction cancel);

abstract interface class CancelableEntityRepository<T, Q extends ListQuery>
    implements EntityRepository<T, Q> {
  Future<PageResult<T>> findCancelable(
    Q query, {
    RegisterCancellation? registerCancel,
  });
}
