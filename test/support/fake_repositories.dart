import 'dart:async';
import 'package:tour_rental/core/dates.dart';
import 'package:tour_rental/core/supabase_api.dart';
import 'package:tour_rental/data/entity_definitions.dart';
import 'package:tour_rental/models/entity_record.dart';
import 'package:tour_rental/models/list_query.dart';
import 'package:tour_rental/models/page_result.dart';
import 'package:tour_rental/models/rental_quote.dart';
import 'package:tour_rental/repositories/entity_repository.dart';
import 'package:tour_rental/repositories/repository_registry.dart';
import 'package:tour_rental/repositories/rental_service.dart';

class MemoryRepository implements EntityRepository<EntityRecord, ListQuery> {
  MemoryRepository([List<EntityRecord>? records]) : records = records ?? [];
  final List<EntityRecord> records;
  Map<String, dynamic>? lastCreated;
  Future<PageResult<EntityRecord>> Function(ListQuery)? findOverride;
  int _revision = 0;
  @override
  int get revision => _revision;
  @override
  Future<List<EntityRecord>> all({bool includeDeleted = false}) async =>
      records.where((e) => includeDeleted || !e.isDeleted).toList();
  @override
  Future<PageResult<EntityRecord>> find(ListQuery query) async {
    if (findOverride != null) return findOverride!(query);
    final filtered = records
        .where(
          (e) =>
              query.deleted == DeletedFilter.all ||
              e.isDeleted == (query.deleted == DeletedFilter.deleted),
        )
        .toList();
    return PageResult(
      items: filtered,
      total: filtered.length,
      page: query.page,
      pageSize: query.pageSize,
    );
  }

  @override
  Future<EntityRecord?> findById(int id) async {
    for (final item in records) {
      if (item.id == id) return item;
    }
    return null;
  }

  @override
  Future<EntityRecord> create(EntityRecord item) async {
    lastCreated = {...item.values};
    final result = EntityRecord({'id': 100 + records.length, ...item.values});
    records.add(result);
    _revision++;
    return result;
  }

  @override
  Future<EntityRecord> update(EntityRecord item) async {
    records.removeWhere((e) => e.id == item.id);
    records.add(item);
    _revision++;
    return item;
  }

  @override
  Future<void> softDelete(int id) async {
    final old = await findById(id);
    if (old != null) await update(old.copyWith({'deleted_at': '2026-11-02'}));
  }

  @override
  Future<void> restore(int id) async {
    final old = await findById(id);
    if (old != null) await update(old.copyWith({'deleted_at': null}));
  }

  @override
  Future<void> hardDelete(int id) async {
    records.removeWhere((e) => e.id == id);
    _revision++;
  }

  @override
  Future<int> deleteMany(List<int> ids) async {
    for (final id in ids) {
      await softDelete(id);
    }
    return ids.length;
  }
}

class FakeRentalService extends RentalService {
  FakeRentalService() : super(SupabaseApi());
  int quoteCalls = 0;
  List<Map<String, dynamic>> fakeUsers = [];
  @override
  Future<List<EntityRecord>> available({
    required String start,
    required String end,
    required int location,
    int? rentalId,
  }) async => [
    EntityRecord({
      'id': 1,
      'inventory_code': 'INV-001',
      'equipment_name': 'Палатка',
      'equipment_id': 1,
      'daily_rate': 700,
      'deposit': 6000,
    }),
    EntityRecord({
      'id': 2,
      'inventory_code': 'INV-002',
      'equipment_name': 'Палатка',
      'equipment_id': 1,
      'daily_rate': 700,
      'deposit': 6000,
    }),
  ];
  @override
  Future<RentalQuote> quote(Map<String, dynamic> values, {int? id}) async {
    quoteCalls++;
    final days = parseDate(
      values['end_on'],
    )!.difference(parseDate(values['start_on'])!).inDays;
    final count = (values['unit_ids'] as List).length;
    final services = (values['service_ids'] as List).length * 300;
    final base = count * 700 * days;
    return RentalQuote({
      'days': days,
      'discount_percent': 5,
      'base_cost': base,
      'discount_amount': base * .05,
      'services_cost': services,
      'total_cost': base * .95 + services,
      'deposit': count * 6000,
      'due_now': base * .95 + services + count * 6000,
    });
  }

  @override
  Future<List<Map<String, dynamic>>> users() async => fakeUsers;
  @override
  Future<void> changeRole(String id, String role) async {
    for (final user in fakeUsers) {
      if (user['id'] == id) user['role'] = role;
    }
  }
}

RepositoryRegistry fixtureRegistry({MemoryRepository? rentals}) {
  final repos = <String, EntityRepository<EntityRecord, ListQuery>>{
    for (final d in entityDefinitions) d.key: MemoryRepository(),
  };
  repos['locations'] = MemoryRepository([
    EntityRecord({'id': 1, 'name': 'Центральный'}),
  ]);
  repos['customers'] = MemoryRepository([
    EntityRecord({
      'id': 3,
      'full_name': 'Анна',
      'email': 'client@pohod.example',
      'phone': '+79000000003',
    }),
  ]);
  repos['services'] = MemoryRepository([
    EntityRecord({'id': 1, 'name': 'Подготовка', 'price': 300}),
    EntityRecord({'id': 2, 'name': 'Чистка', 'price': 300}),
  ]);
  repos['loyalty_cards'] = MemoryRepository([
    EntityRecord({
      'id': 3,
      'customer_id': 3,
      'number': 'TR-000003',
      'discount_percent': 5,
      'issued_on': isoDate(businessToday().subtract(const Duration(days: 1))),
      'expires_on': isoDate(businessToday().add(const Duration(days: 365))),
    }),
  ]);
  repos['rentals'] = rentals ?? MemoryRepository();
  return RepositoryRegistry.testing(repos);
}

class FakeRentalRepository extends MemoryRepository {
  @override
  Future<EntityRecord> create(EntityRecord item) async {
    final original = await super.create(item);
    final ids = List<int>.from(item['unit_ids'] as List),
        services = List<int>.from(item['service_ids'] as List);
    final days = parseDate(
      item['end_on'],
    )!.difference(parseDate(item['start_on'])!).inDays;
    final rich = original.copyWith({
      'status': 'reserved',
      'base_cost': ids.length * 700 * days,
      'discount_percent': 5,
      'services_cost': services.length * 300,
      'total_cost': item['expected_total'],
      'deposit': ids.length * 6000,
      'late_fee': 0,
      'customer': {'id': 3, 'full_name': 'Анна'},
      'location': {'id': 1, 'name': 'Центральный'},
      'rental_items': [
        for (final id in ids)
          {
            'unit_id': id,
            'inventory_code': 'INV-00$id',
            'equipment_name': 'Палатка',
            'daily_rate': 700,
            'deposit': 6000,
          },
      ],
      'rental_services': [
        for (final id in services)
          {'service_id': id, 'service_name': 'Подготовка', 'price': 300},
      ],
    });
    records.removeWhere((e) => e.id == original.id);
    records.add(rich);
    return rich;
  }
}
