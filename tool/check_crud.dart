import 'dart:io';
import 'package:tour_rental/core/dates.dart';
import 'package:tour_rental/core/supabase_api.dart';
import 'package:tour_rental/data/entity_definitions.dart';
import 'package:tour_rental/models/entity_record.dart';
import 'package:tour_rental/models/list_query.dart';
import 'package:tour_rental/repositories/repository_registry.dart';

Future<void> main() async {
  final password = Platform.environment['DEMO_PASSWORD'];
  if (password == null) throw StateError('Set DEMO_PASSWORD');
  final api = SupabaseApi();
  final created = <({String entity, int id})>[];
  final registry = RepositoryRegistry(api);
  final tag = DateTime.now().millisecondsSinceEpoch.toString();
  final items = <String, EntityRecord>{};
  try {
    final login = await api.request(
      '/auth/v1/token',
      method: 'POST',
      authenticated: false,
      query: {'grant_type': 'password'},
      data: {'email': 'admin@pohod.example', 'password': password},
    );
    api.accessToken = () async => login.data['access_token'] as String;
    final baseline = <String, int>{};
    for (final d in entityDefinitions) {
      baseline[d.key] =
          (await registry.of(d.key).find(const ListQuery(pageSize: 5))).total;
    }
    Future<EntityRecord> add(String entity, Map<String, dynamic> data) async {
      final value = await registry.of(entity).create(EntityRecord(data));
      created.add((entity: entity, id: value.id));
      items[entity] = value;
      return value;
    }

    await add('categories', {
      'name': 'Smoke category $tag',
      'description': 'Временная проверка CRUD',
    });
    await add('brands', {'name': 'Smoke brand $tag', 'country': 'Россия'});
    await add('locations', {
      'name': 'Smoke location $tag',
      'address': 'Тестовая улица, 1',
      'phone': '+79000000010',
    });
    await add('equipment', {
      'name': 'Smoke equipment $tag',
      'sku': 'QA-$tag',
      'category_id': items['categories']!.id,
      'brand_id': items['brands']!.id,
      'daily_rate': 900,
      'deposit': 2000,
      'weight_grams': 2000,
      'description': 'Тестовое снаряжение',
    });
    await add('units', {
      'inventory_code': 'QA-$tag',
      'equipment_id': items['equipment']!.id,
      'location_id': items['locations']!.id,
      'state': 'ready',
      'acquired_on': isoDate(businessToday()),
      'note': '',
    });
    await add('customers', {
      'full_name': 'Тестовый клиент $tag',
      'email': 'qa-$tag@pohod.example',
      'phone': '+79000000011',
    });
    await add('loyalty_cards', {
      'customer_id': items['customers']!.id,
      'number': 'TR-9${(int.parse(tag) % 100000).toString().padLeft(5, '0')}',
      'discount_percent': 3,
      'issued_on': isoDate(businessToday()),
      'expires_on': isoDate(businessToday().add(const Duration(days: 365))),
    });
    await add('services', {
      'name': 'Smoke service $tag',
      'price': 300,
      'description': 'Тестовая услуга',
    });
    await add('rentals', {
      'customer_id': items['customers']!.id,
      'location_id': items['locations']!.id,
      'start_on': isoDate(businessToday().add(const Duration(days: 30))),
      'end_on': isoDate(businessToday().add(const Duration(days: 32))),
      'unit_ids': [items['units']!.id],
      'service_ids': [items['services']!.id],
      'notes': 'Временная проверка CRUD',
    });
    final changes = <String, Map<String, dynamic>>{
      'categories': {'description': 'Описание изменено'},
      'brands': {'country': 'Норвегия'},
      'locations': {'address': 'Обновлённая улица, 2'},
      'equipment': {'daily_rate': 901},
      'units': {'note': 'Примечание изменено'},
      'customers': {'phone': '+79000000012'},
      'loyalty_cards': {'discount_percent': 4},
      'services': {'price': 400},
      'rentals': {'notes': 'Комментарий изменён'},
    };
    for (final entry in changes.entries) {
      final value = await registry
          .of(entry.key)
          .update(items[entry.key]!.copyWith(entry.value));
      for (final field in entry.value.entries) {
        if (value[field.key] != field.value) {
          throw StateError('Update failed: ${entry.key}.${field.key}');
        }
      }
      items[entry.key] = value;
    }
    final rental = items['rentals']!;
    if ((rental['total_cost'] as num) != 2129.92 ||
        (rental['rental_items'] as List).single['daily_rate'] != 901) {
      throw StateError('Price snapshot mismatch');
    }
    for (final entry in created.reversed.toList()) {
      final repo = registry.of(entry.entity);
      await repo.softDelete(entry.id);
      if (!(await repo.findById(entry.id))!.isDeleted) {
        throw StateError('Soft delete failed: ${entry.entity}');
      }
      await repo.restore(entry.id);
      if ((await repo.findById(entry.id))!.isDeleted) {
        throw StateError('Restore failed: ${entry.entity}');
      }
      await repo.softDelete(entry.id);
      await repo.hardDelete(entry.id);
      if (await repo.findById(entry.id) != null) {
        throw StateError('Hard delete failed: ${entry.entity}');
      }
      stdout.writeln(
        'PASS ${entry.entity}: create/read/update/soft delete/restore/hard delete',
      );
    }
    final bulkA = await add('categories', {'name': 'Smoke bulk A $tag'}),
        bulkB = await add('categories', {'name': 'Smoke bulk B $tag'});
    final repo = registry.of('categories');
    if (await repo.deleteMany([bulkA.id, bulkB.id]) != 2) {
      throw StateError('Bulk deletion failed');
    }
    await repo.hardDelete(bulkA.id);
    await repo.hardDelete(bulkB.id);
    for (final d in entityDefinitions) {
      if ((await registry.of(d.key).find(const ListQuery(pageSize: 5))).total !=
          baseline[d.key]) {
        throw StateError('Temporary data remain: ${d.key}');
      }
    }
    stdout.writeln(
      'PASS bulk delete; all temporary records removed; initial counts preserved',
    );
  } finally {
    // Cleanup is limited to IDs created by this run, in reverse dependency order.
    for (final entry in created.reversed) {
      final repo = registry.of(entry.entity),
          item = await registry.of(entry.entity).findById(entry.id);
      if (item == null) continue;
      if (!item.isDeleted) await repo.softDelete(entry.id);
      await repo.hardDelete(entry.id);
    }
    api.close();
  }
}
