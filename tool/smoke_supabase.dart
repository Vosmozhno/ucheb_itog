import 'dart:io';
import 'package:tour_rental/core/api_error.dart';
import 'package:tour_rental/core/dates.dart';
import 'package:tour_rental/core/supabase_api.dart';

Future<void> expectStatus(
  Future<dynamic> Function() operation,
  int status,
) async {
  try {
    await operation();
    throw StateError('Expected HTTP $status');
  } on ApiError catch (error) {
    if (error.status != status) rethrow;
  }
}

Future<void> main() async {
  final password = Platform.environment['DEMO_PASSWORD'];
  if (password == null || password.isEmpty) {
    throw StateError('Set DEMO_PASSWORD for the demo accounts.');
  }
  for (final role in ['admin', 'employee', 'client']) {
    final api = SupabaseApi();
    try {
      final session = await api.request(
        '/auth/v1/token',
        method: 'POST',
        authenticated: false,
        query: {'grant_type': 'password'},
        data: {'email': '$role@pohod.example', 'password': password},
      );
      final token = session.data['access_token'] as String;
      api.accessToken = () async => token;
      final profile =
          (await api.request(
                '/rest/v1/profiles',
                query: {'select': 'id,role'},
              )).data
              as List;
      if (profile.length != 1 || profile.first['role'] != role) {
        throw StateError('Wrong canonical role for $role');
      }
      final equipment = await api.request(
        '/rest/v1/equipment',
        query: {'select': 'id,name', 'limit': 1},
      );
      if ((equipment.data as List).isEmpty) {
        throw StateError('Equipment catalog is missing');
      }
      if (role == 'admin') {
        final users = await api.rpc('list_users', {}) as List;
        final summary = await api.rpc('admin_summary', {}) as Map;
        if (users.length < 3 || (summary['equipment'] as num) < 8) {
          throw StateError('Demo data missing');
        }
      } else {
        await expectStatus(() => api.rpc('list_users', {}), 403);
        await expectStatus(() => api.rpc('admin_summary', {}), 403);
      }
      if (role == 'employee') {
        await expectStatus(
          () => api.request(
            '/rest/v1/services',
            method: 'POST',
            data: {'name': 'Проверка неверной цены', 'price': -1},
          ),
          422,
        );
      }
      if (role == 'client') {
        final contacts =
            (await api.request(
                  '/rest/v1/customers',
                  query: {'select': 'id'},
                )).data
                as List;
        if (contacts.length != 1) {
          throw StateError('Client ownership isolation failed');
        }
        final today = businessToday();
        final quote =
            await api.rpc('quote_rental', {
                  'p_data': {
                    'location_id': 1,
                    'start_on': isoDate(today),
                    'end_on': isoDate(today.add(const Duration(days: 2))),
                    'unit_ids': [1],
                    'service_ids': [1],
                  },
                })
                as Map;
        if (quote['total_cost'] != 1630) {
          throw StateError('Unexpected rental price: ${quote['total_cost']}');
        }
        await expectStatus(
          () => api.rpc('quote_rental', {
            'p_data': {
              'location_id': 1,
              'start_on': isoDate(today),
              'end_on': isoDate(today.add(const Duration(days: 1))),
              'unit_ids': [5],
            },
          }),
          409,
        );
      }
      stdout.writeln(
        'PASS $role: auth, canonical role, scoped REST/RPC access',
      );
      await api.request(
        '/auth/v1/logout',
        method: 'POST',
        query: {'scope': 'local'},
      );
    } finally {
      api.close();
    }
  }
}
