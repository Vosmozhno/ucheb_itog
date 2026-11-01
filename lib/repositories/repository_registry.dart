import '../core/supabase_api.dart';
import '../data/entity_definitions.dart';
import '../models/entity_record.dart';
import '../models/list_query.dart';
import 'entity_repository.dart';
import 'supabase_entity_repository.dart';

class RepositoryRegistry {
  RepositoryRegistry(SupabaseApi api)
    : repositories = {
        for (final definition in entityDefinitions)
          definition.key: SupabaseEntityRepository(api, definition),
      };
  RepositoryRegistry.testing(this.repositories);
  final Map<String, EntityRepository<EntityRecord, ListQuery>> repositories;
  EntityRepository<EntityRecord, ListQuery> of(String key) =>
      repositories[key]!;
  Future<Map<String, List<EntityRecord>>> options(Iterable<String> keys) async {
    final names = keys.toSet().toList();
    final lists = await Future.wait(names.map((key) => of(key).all()));
    return {for (var i = 0; i < names.length; i++) names[i]: lists[i]};
  }
}
