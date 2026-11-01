import 'package:dio/dio.dart';
import '../core/api_error.dart';
import '../core/dates.dart';
import '../core/supabase_api.dart';
import '../models/entity_definition.dart';
import '../models/entity_record.dart';
import '../models/list_query.dart';
import '../models/page_result.dart';
import 'entity_repository.dart';

class SupabaseEntityRepository
    implements CancelableEntityRepository<EntityRecord, ListQuery> {
  SupabaseEntityRepository(this.api, this.definition);
  final SupabaseApi api;
  final EntityDefinition definition;
  int _revision = 0;
  @override
  int get revision => _revision;
  Map<String, dynamic> parameters(ListQuery query) {
    final sort = definition.sortable.contains(query.sort) ? query.sort : 'id';
    final result = <String, dynamic>{
      'select': definition.select,
      'limit': query.pageSize,
      'offset': (query.page - 1) * query.pageSize,
      'order':
          '$sort.${query.ascending ? 'asc' : 'desc'},id.${query.ascending ? 'asc' : 'desc'}',
    };
    if (query.deleted != DeletedFilter.all) {
      result['deleted_at'] = query.deleted == DeletedFilter.deleted
          ? 'not.is.null'
          : 'is.null';
    }
    // Remove PostgREST expression delimiters, keeping search as literal text.
    final search = query.keyword
        .replaceAll(RegExp(r'[(),.*:"\\%_]'), ' ')
        .trim();
    if (search.isNotEmpty) {
      if (definition.key == 'rentals' && int.tryParse(search) != null) {
        result['id'] = 'eq.$search';
      } else {
        result['or'] =
            '(${definition.searchFields.map((f) => '$f.ilike.*$search*').join(',')})';
      }
    }
    for (final key in definition.filterFields) {
      final field = definition.field(key), value = query.filters[key];
      if (value == null || value.isEmpty) continue;
      if (field?.kind == FieldKind.reference && int.tryParse(value) != null) {
        result[key] = 'eq.$value';
      } else if (field?.kind == FieldKind.choice || key == 'status') {
        result[key] = 'eq.$value';
      } else if (key == 'country') {
        result[key] =
            'ilike.*${value.replaceAll(RegExp(r'[(),.*:"\\%_]'), ' ')}*';
      }
    }
    final and = <String>[];
    for (final entry in {
      'price_min': 'daily_rate.gte',
      'price_max': 'daily_rate.lte',
    }.entries) {
      final value = int.tryParse(query.filters[entry.key] ?? '');
      if (definition.key == 'equipment' && value != null && value >= 0) {
        and.add('${entry.value}.$value');
      }
    }
    for (final entry in {
      'start_from': 'start_on.gte',
      'start_to': 'start_on.lte',
      'created_from': 'created_at.gte',
      'created_to': 'created_at.lte',
    }.entries) {
      final value = query.filters[entry.key];
      if (value != null && parseDate(value) != null) {
        if (entry.key.startsWith('start_') && definition.key != 'rentals') {
          continue;
        }
        and.add(
          '${entry.value}.$value${entry.key == 'created_to' ? 'T23:59:59.999Z' : ''}',
        );
      }
    }
    if (and.isNotEmpty) result['and'] = '(${and.join(',')})';
    return result;
  }

  @override
  Future<PageResult<EntityRecord>> find(ListQuery query) =>
      findCancelable(query);
  @override
  Future<PageResult<EntityRecord>> findCancelable(
    ListQuery query, {
    CancelToken? cancelToken,
    RegisterCancellation? registerCancel,
  }) async {
    final token = cancelToken ?? CancelToken();
    registerCancel?.call(() => token.cancel());
    final response = await api.request(
      '/rest/v1/${definition.key}',
      query: parameters(query),
      headers: {'Prefer': 'count=exact'},
      cancelToken: token,
    );
    final items = (response.data as List)
        .map((e) => EntityRecord(Map<String, dynamic>.from(e)))
        .toList();
    final range = response.headers.value('content-range') ?? '';
    final total = int.tryParse(range.split('/').last) ?? items.length;
    return PageResult(
      items: items,
      total: total,
      page: query.page,
      pageSize: query.pageSize,
    );
  }

  @override
  Future<List<EntityRecord>> all({bool includeDeleted = false}) async {
    final result = <EntityRecord>[];
    var offset = 0;
    while (true) {
      final response = await api.request(
        '/rest/v1/${definition.key}',
        query: {
          'select': definition.select,
          'order': 'id.asc',
          'limit': 200,
          'offset': offset,
          if (!includeDeleted) 'deleted_at': 'is.null',
        },
      );
      final data = response.data as List;
      result.addAll(
        data.map((e) => EntityRecord(Map<String, dynamic>.from(e))),
      );
      if (data.length < 200) break;
      offset += 200;
    }
    return result;
  }

  @override
  Future<EntityRecord?> findById(int id) async {
    final response = await api.request(
      '/rest/v1/${definition.key}',
      query: {'select': definition.select, 'id': 'eq.$id', 'limit': 1},
    );
    final data = response.data as List;
    return data.isEmpty
        ? null
        : EntityRecord(Map<String, dynamic>.from(data.first));
  }

  Map<String, dynamic> payload(EntityRecord item) => {
    for (final field in definition.fields)
      if (item.values.containsKey(field.key)) field.key: item[field.key],
    if (definition.key == 'rentals') ...{
      'unit_ids': item['unit_ids'] ?? item.unitIds,
      'service_ids': item['service_ids'] ?? item.serviceIds,
    },
    if (definition.key == 'rentals' && item['expected_total'] != null)
      'expected_total': item['expected_total'],
  };
  @override
  Future<EntityRecord> create(EntityRecord item) => _save(item, false);
  @override
  Future<EntityRecord> update(EntityRecord item) => _save(item, true);
  Future<EntityRecord> _save(EntityRecord item, bool update) async {
    int id;
    if (definition.key == 'rentals') {
      final data = await api.rpc('save_rental', {
        'p_data': payload(item),
        'p_id': update ? item.id : null,
      });
      id = (data['id'] as num).toInt();
    } else {
      final response = await api.request(
        '/rest/v1/${definition.key}',
        method: update ? 'PATCH' : 'POST',
        data: payload(item),
        query: update ? {'id': 'eq.${item.id}'} : null,
        headers: {'Prefer': 'return=representation'},
      );
      final data = response.data as List;
      if (data.isEmpty) {
        throw const ApiError(
          ApiErrorKind.notFound,
          'Запись не найдена или недоступна.',
        );
      }
      id = (data.first['id'] as num).toInt();
    }
    _revision++;
    return (await findById(id))!;
  }

  Future<int> _mutate(List<int> ids, String action) async {
    final result = await api.rpc('mutate_records', {
      'p_entity': definition.key,
      'p_ids': ids,
      'p_action': action,
    });
    _revision++;
    return (result as num).toInt();
  }

  @override
  Future<void> softDelete(int id) async {
    await _mutate([id], 'soft');
  }

  @override
  Future<void> hardDelete(int id) async {
    await _mutate([id], 'hard');
  }

  @override
  Future<void> restore(int id) async {
    await _mutate([id], 'restore');
  }

  @override
  Future<int> deleteMany(List<int> ids) => _mutate(ids, 'soft');
}
