import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tour_rental/app.dart';
import 'package:tour_rental/core/api_error.dart';
import 'package:tour_rental/core/dates.dart';
import 'package:tour_rental/core/permissions.dart';
import 'package:tour_rental/core/supabase_api.dart';
import 'package:tour_rental/core/validators.dart';
import 'package:tour_rental/data/entity_definitions.dart';
import 'package:tour_rental/models/app_role.dart';
import 'package:tour_rental/models/entity_record.dart';
import 'package:tour_rental/models/list_query.dart';
import 'package:tour_rental/models/rental_quote.dart';
import 'package:tour_rental/repositories/supabase_entity_repository.dart';
import 'package:tour_rental/state/auth_state.dart';
import 'support/fake_http.dart';
import 'support/fake_repositories.dart';
import 'package:tour_rental/models/page_result.dart';
import 'package:tour_rental/state/entity_list_state.dart';

void main() {
  test('Moscow day changes at 21:00 UTC, independent of the device zone', () {
    expect(
      isoDate(businessToday(DateTime.parse('2026-11-01T20:59:00Z'))),
      '2026-11-01',
    );
    expect(
      isoDate(businessToday(DateTime.parse('2026-11-01T21:01:00Z'))),
      '2026-11-02',
    );
  });
  test('Calendar validation rejects normalized impossible dates', () {
    expect(parseDate('2026-02-30'), isNull);
    expect(parseDate('2026-13-01'), isNull);
    expect(parseDate('2028-02-29'), isNotNull);
  });
  test('Contact and password formats have explicit bounds', () {
    expect(Validators.email('bad@'), isNotNull);
    expect(Validators.email('anna@pohod.example'), isNull);
    expect(Validators.password('lettersOnly'), isNotNull);
    expect(Validators.password('ValidPass!42'), isNull);
    final phone = definitionOf('customers').field('phone')!;
    expect(Validators.field(phone, '+7 (900) 000-00-01'), isNull);
    expect(Validators.field(phone, '123'), isNotNull);
  });
  test(
    'Server-compatible form limits reject fractional and out-of-range prices',
    () {
      final price = definitionOf('equipment').field('daily_rate')!;
      for (final value in ['0', '50001', '3.5', 'abc']) {
        expect(Validators.field(price, value), isNotNull);
      }
      expect(Validators.field(price, '700'), isNull);
    },
  );
  test('A card expiry date must be later than its issue date', () {
    final errors = Validators.record(definitionOf('loyalty_cards'), {
      'customer_id': 1,
      'number': 'TR-000001',
      'discount_percent': 5,
      'issued_on': '2026-11-02',
      'expires_on': '2026-11-01',
    }, now: DateTime.utc(2026, 11, 2));
    expect(errors.keys, contains('expires_on'));
  });
  test('Rental date interval and selected items are required', () {
    final errors = Validators.record(definitionOf('rentals'), {
      'customer_id': 1,
      'location_id': 1,
      'start_on': '2026-11-02',
      'end_on': '2026-11-02',
      'unit_ids': <int>[],
      'service_ids': <int>[],
    }, now: DateTime.utc(2026, 11, 2, 9));
    expect(errors.keys, containsAll(['end_on', 'unit_ids']));
  });
  test(
    'Tariff at seven days combines discounts but excludes services and deposit',
    () {
      final q = TariffPreview.calculate(
        days: 7,
        dailyRate: 700,
        loyalty: 5,
        services: 300,
        deposit: 6000,
      );
      expect(q.base, 4900);
      expect(q.discount, 15);
      expect(q.total, 4465);
      expect(q.dueNow, 10465);
    },
  );
  test('Tariff caps the combined discount at twenty percent', () {
    final q = TariffPreview.calculate(
      days: 14,
      dailyRate: 700,
      loyalty: 10,
      services: 300,
      deposit: 6000,
    );
    expect(q.discount, 20);
    expect(q.total, 8140);
    expect(q.deposit, 6000);
    expect(
      () => TariffPreview.calculate(days: 91, dailyRate: 700),
      throwsArgumentError,
    );
  });
  test('All three exclusive role screens reject the other two roles', () {
    final exclusive = {
      AppRole.client: '/my-rentals',
      AppRole.employee: '/desk',
      AppRole.admin: '/admin/users',
    };
    for (final entry in exclusive.entries) {
      for (final role in AppRole.values) {
        expect(mayOpen(role, entry.value), role == entry.key);
      }
    }
    expect(mayOpen(AppRole.client, '/manage'), isFalse);
    expect(mayOpen(AppRole.client, '/manage/equipment'), isFalse);
  });
  test(
    'Query URL round trip preserves filters, order, page, and archive state',
    () {
      const q = ListQuery(
        keyword: 'Палатка',
        page: 3,
        pageSize: 5,
        sort: 'daily_rate',
        ascending: true,
        deleted: DeletedFilter.deleted,
        filters: {'category_id': '1', 'brand_id': '2', 'price_min': '500'},
      );
      final result = ListQuery.fromUri(
        Uri(path: '/catalog', queryParameters: q.parameters),
      );
      expect(result.parameters, q.parameters);
      expect(ListQuery.fromUri(Uri.parse('/catalog?page=-3&size=999')).page, 1);
    },
  );
  test('Search delimiters are removed and all filters go to the server', () {
    final repo = SupabaseEntityRepository(
      SupabaseApi(),
      definitionOf('equipment'),
    );
    final p = repo.parameters(
      const ListQuery(
        keyword: 'палатка),id.eq.1',
        page: 2,
        pageSize: 5,
        sort: 'DROP TABLE',
        filters: {
          'category_id': '1',
          'brand_id': '2',
          'price_min': '500',
          'price_max': '1000',
        },
      ),
    );
    expect(p['offset'], 5);
    expect(p['category_id'], 'eq.1');
    expect(p['brand_id'], 'eq.2');
    expect(p['and'], '(daily_rate.gte.500,daily_rate.lte.1000)');
    expect(p['order'], 'id.desc,id.desc');
    expect(p['or'], isNot(contains('),id.eq.1')));
    repo.api.close();
  });
  test('Repository preserves M:N links when updating a fetched record', () {
    final repo = SupabaseEntityRepository(
      SupabaseApi(),
      definitionOf('rentals'),
    );
    final item = EntityRecord({
      'id': 1,
      'rental_items': [
        {'unit_id': 4},
        {'unit_id': 8},
      ],
      'rental_services': [
        {'service_id': 2},
      ],
      'notes': 'Изменён комментарий',
    });
    expect(repo.payload(item)['unit_ids'], [4, 8]);
    expect(repo.payload(item)['service_ids'], [2]);
    repo.api.close();
  });
  test('HTTP 422 JSON details become inline field errors', () {
    final error = ApiError.fromDio(
      DioException(
        requestOptions: RequestOptions(path: '/services'),
        type: DioExceptionType.badResponse,
        response: Response(
          requestOptions: RequestOptions(path: '/services'),
          statusCode: 422,
          data: {
            'code': 'TR422',
            'message': 'Проверьте поля',
            'details': jsonEncode({'price': 'Цена должна быть положительной'}),
          },
        ),
      ),
    );
    expect(error.kind, ApiErrorKind.validation);
    expect(error.fields['price'], 'Цена должна быть положительной');
  });
  test('An expired refresh token clears the session', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
    dio.httpClientAdapter = FakeHttpAdapter(
      (r) => const FakeResponse({
        'error_code': 'refresh_token_not_found',
      }, status: 400),
    );
    final store = MemorySessionStore({
      'access_token': 'old',
      'refresh_token': 'invalid',
      'expires_at': 0,
      'user_id': 'user-1',
    });
    final auth = AuthState(SupabaseApi(dio: dio), store);
    await auth.restore();
    expect(auth.signedIn, isFalse);
    expect(store.value, isNull);
    expect(auth.ready, isTrue);
    auth.dispose();
    dio.close();
  });
  test(
    'Concurrent HTTP 401 responses share one refresh and replay with the new token',
    () async {
      final allOldRequests = Completer<void>();
      var old = 0, refreshes = 0;
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      dio.httpClientAdapter = FakeHttpAdapter((r) async {
        if (r.path == '/rest/v1/profiles') {
          return const FakeResponse([
            {'id': 'user-1', 'full_name': 'Анна', 'role': 'client'},
          ]);
        }
        if (r.path == '/auth/v1/token') {
          refreshes++;
          await allOldRequests.future;
          return FakeResponse({
            'access_token': 'new',
            'refresh_token': 'new-refresh',
            'expires_in': 3600,
            'user': {'id': 'user-1'},
          });
        }
        if (r.headers['Authorization'] == 'Bearer old') {
          old++;
          if (old == 3) allOldRequests.complete();
          return const FakeResponse({'message': 'Expired'}, status: 401);
        }
        return const FakeResponse({'ok': true});
      });
      final store = MemorySessionStore({
        'access_token': 'old',
        'refresh_token': 'refresh',
        'user_id': 'user-1',
        'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
      });
      final api = SupabaseApi(dio: dio);
      final auth = AuthState(api, store);
      await auth.restore();
      final responses = await Future.wait(
        List.generate(3, (_) => api.request('/rest/v1/probe')),
      );
      expect(refreshes, 1);
      expect(responses.every((r) => r.data['ok'] == true), isTrue);
      expect(store.value?['access_token'], 'new');
      auth.dispose();
      dio.close();
    },
  );
  test(
    'UI role demonstration cannot replace the canonical server profile',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      dio.httpClientAdapter = FakeHttpAdapter(
        (r) => const FakeResponse([
          {'id': 'user-1', 'full_name': 'Анна', 'role': 'client'},
        ]),
      );
      final store = MemorySessionStore({
        'access_token': 'token',
        'refresh_token': 'refresh',
        'user_id': 'user-1',
        'expires_at': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600,
      }, 'admin');
      final auth = AuthState(SupabaseApi(dio: dio), store, allowRoleDemo: true);
      await auth.restore();
      expect(auth.role, AppRole.admin);
      expect(auth.profile!.role, AppRole.client);
      expect(auth.hasDemoOverride, isTrue);
      auth.dispose();
      dio.close();
    },
  );
  test('Return URLs reject external hosts and authentication loops', () {
    expect(safeNext('https://other.example'), isNull);
    expect(safeNext('//other.example'), isNull);
    expect(safeNext('/login'), isNull);
    expect(safeNext('/catalog?f_category_id=1'), '/catalog?f_category_id=1');
  });
  test(
    'Registration stores the session and canonical profile without a password',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
      dio.httpClientAdapter = FakeHttpAdapter(
        (r) => r.path == '/auth/v1/signup'
            ? const FakeResponse({
                'access_token': 'qa-access',
                'refresh_token': 'qa-refresh',
                'expires_in': 3600,
                'user': {'id': 'user-new'},
              })
            : const FakeResponse([
                {
                  'id': 'user-new',
                  'full_name': 'Новый клиент',
                  'role': 'client',
                },
              ]),
      );
      final store = MemorySessionStore();
      final auth = AuthState(SupabaseApi(dio: dio), store);
      expect(
        await auth.register(
          fullName: 'Новый клиент',
          email: 'new@example.test',
          phone: '+79000000004',
          password: 'ValidPass!42',
        ),
        isTrue,
      );
      expect(auth.signedIn, isTrue);
      expect(auth.profile!.role, AppRole.client);
      expect(store.value?['refresh_token'], 'qa-refresh');
      expect(store.value!.containsKey('password'), isFalse);
      auth.dispose();
      dio.close();
    },
  );
  test('A late response cannot overwrite a newer search result', () async {
    final old = Completer<PageResult<EntityRecord>>(),
        recent = Completer<PageResult<EntityRecord>>();
    final repo = MemoryRepository()
      ..findOverride = (q) => q.keyword == 'old' ? old.future : recent.future;
    final state = EntityListState(repo);
    final first = state.load(const ListQuery(keyword: 'old'));
    final second = state.load(const ListQuery(keyword: 'new'));
    recent.complete(
      PageResult(
        items: [
          EntityRecord({'id': 2, 'name': 'Новый результат'}),
        ],
        total: 1,
        page: 1,
        pageSize: 10,
      ),
    );
    await second;
    old.complete(
      PageResult(
        items: [
          EntityRecord({'id': 1, 'name': 'Старый результат'}),
        ],
        total: 1,
        page: 1,
        pageSize: 10,
      ),
    );
    await first;
    expect(state.page!.items.single.label, 'Новый результат');
    state.dispose();
  });
}
