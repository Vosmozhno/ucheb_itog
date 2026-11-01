import 'dart:convert';
import 'dart:io';
import 'package:tour_rental/core/api_error.dart';
import 'package:tour_rental/core/supabase_api.dart';

Future<void> denied(Future<dynamic> Function() action) async {
  try {
    await action();
    throw StateError('A client received administrator access');
  } on ApiError catch (e) {
    if (e.status != 403) rethrow;
  }
}

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    throw StateError(
      'Pass the path to a private QA account JSON file: email, password.',
    );
  }
  final account = Map<String, dynamic>.from(
    jsonDecode(await File(args.single).readAsString()),
  );
  final api = SupabaseApi();
  try {
    Map<String, dynamic> session;
    try {
      session = Map<String, dynamic>.from(
        (await api.request(
          '/auth/v1/signup',
          method: 'POST',
          authenticated: false,
          data: {
            'email': account['email'],
            'password': account['password'],
            'data': {
              'full_name': 'Михаил Походников',
              'phone': '+79000000004',
              'role': 'admin',
            },
          },
        )).data,
      );
    } on ApiError catch (e) {
      if (e.status != 400 && e.status != 422) rethrow;
      session = Map<String, dynamic>.from(
        (await api.request(
          '/auth/v1/token',
          method: 'POST',
          authenticated: false,
          query: {'grant_type': 'password'},
          data: {'email': account['email'], 'password': account['password']},
        )).data,
      );
    }
    var token = session['access_token'] as String;
    api.accessToken = () async => token;
    final profile =
        (await api.request(
              '/rest/v1/profiles',
              query: {'select': 'id,role'},
            )).data
            as List;
    if (profile.length != 1 || profile.first['role'] != 'client') {
      throw StateError('Registration trusted a user-supplied role');
    }
    final customers =
        (await api.request(
              '/rest/v1/customers',
              query: {'select': 'id,full_name'},
            )).data
            as List;
    final cards =
        (await api.request(
              '/rest/v1/loyalty_cards',
              query: {'select': 'id,customer_id'},
            )).data
            as List;
    if (customers.length != 1 ||
        cards.length != 1 ||
        cards.first['customer_id'] != customers.first['id']) {
      throw StateError('Registration did not create the 1:1 card');
    }
    if (((await api.request('/rest/v1/rentals')).data as List).isNotEmpty) {
      throw StateError('New customer can see foreign rentals');
    }
    await denied(() => api.rpc('list_users', {}));
    await denied(
      () => api.rpc('quote_rental', {
        'p_data': {
          'unit_ids': [1],
        },
        'p_id': 1,
      }),
    );
    final refreshed = await api.request(
      '/auth/v1/token',
      method: 'POST',
      authenticated: false,
      query: {'grant_type': 'refresh_token'},
      data: {'refresh_token': session['refresh_token']},
    );
    token = refreshed.data['access_token'] as String;
    await api.request('/rest/v1/profiles', query: {'select': 'id,role'});
    await api.request(
      '/auth/v1/logout',
      method: 'POST',
      query: {'scope': 'local'},
    );
    stdout.writeln(
      'PASS signup: canonical client role, customer + unique card, ownership isolation, denied admin RPC, real token refresh',
    );
    stdout.writeln(
      'QA account: ${account['email']} (password remains in the private input file)',
    );
  } finally {
    api.close();
  }
}
