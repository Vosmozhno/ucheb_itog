import 'dart:io';
import 'package:tour_rental/core/api_error.dart';
import 'package:tour_rental/core/dates.dart';
import 'package:tour_rental/core/supabase_api.dart';

Future<void> expectStatus(Future<dynamic> Function() action, int status) async {
  try {
    await action();
    throw StateError('Expected HTTP $status');
  } on ApiError catch (e) {
    if (e.status != status) rethrow;
  }
}

Future<void> main() async {
  final password = Platform.environment['DEMO_PASSWORD'];
  if (password == null) throw StateError('Set DEMO_PASSWORD');
  final api = SupabaseApi();
  String? token;
  api.accessToken = () async => token;
  Future<void> login(String role) async {
    token =
        (await api.request(
              '/auth/v1/token',
              method: 'POST',
              authenticated: false,
              query: {'grant_type': 'password'},
              data: {'email': '$role@pohod.example', 'password': password},
            )).data['access_token']
            as String;
  }

  final tag = 'Race check ${DateTime.now().millisecondsSinceEpoch}';
  try {
    await login('admin');
    await expectStatus(
      () => api.request(
        '/rest/v1/units',
        method: 'PATCH',
        query: {'id': 'eq.7'},
        data: {'location_id': 2},
      ),
      409,
    );
    await expectStatus(
      () => api.request(
        '/rest/v1/categories',
        method: 'POST',
        data: {'name': '\t\n'},
      ),
      422,
    );
    await expectStatus(
      () => api.request(
        '/rest/v1/categories',
        method: 'POST',
        data: {'id': 999999, 'name': 'Read only identifier check'},
      ),
      400,
    );
    await login('client');
    final data = {
      'location_id': 1,
      'start_on': isoDate(businessToday().add(const Duration(days: 60))),
      'end_on': isoDate(businessToday().add(const Duration(days: 62))),
      'unit_ids': [2],
      'service_ids': <int>[],
      'notes': tag,
    };
    final results = await Future.wait(
      List.generate(2, (_) async {
        try {
          await api.rpc('save_rental', {'p_data': data});
          return 200;
        } on ApiError catch (e) {
          return e.status ?? 0;
        }
      }),
    );
    if (results.where((s) => s == 200).length != 1 ||
        results.where((s) => s == 409).length != 1) {
      throw StateError('Race result is $results');
    }
    stdout.writeln(
      'PASS integrity: occupied unit immutable, whitespace rejected, generated IDs protected, concurrent reservation returns one success and one HTTP 409',
    );
  } finally {
    await login('admin');
    final rows =
        (await api.request(
              '/rest/v1/rentals',
              query: {'select': 'id', 'notes': 'eq.$tag'},
            )).data
            as List;
    for (final row in rows) {
      await api.rpc('mutate_records', {
        'p_entity': 'rentals',
        'p_ids': [row['id']],
        'p_action': 'soft',
      });
      await api.rpc('mutate_records', {
        'p_entity': 'rentals',
        'p_ids': [row['id']],
        'p_action': 'hard',
      });
    }
    api.close();
  }
}
