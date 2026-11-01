import '../core/supabase_api.dart';
import '../models/entity_record.dart';
import '../models/rental_quote.dart';

class RentalService {
  RentalService(this.api);
  final SupabaseApi api;
  Future<RentalQuote> quote(Map<String, dynamic> values, {int? id}) async =>
      RentalQuote(
        Map<String, dynamic>.from(
          await api.rpc('quote_rental', {'p_data': values, 'p_id': id}),
        ),
      );
  Future<List<EntityRecord>> available({
    required String start,
    required String end,
    required int location,
    int? rentalId,
  }) async {
    final result = await api.rpc('available_units', {
      'p_start': start,
      'p_end': end,
      'p_location': location,
      'p_rental_id': rentalId,
    });
    return (result as List)
        .map((e) => EntityRecord(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> action(int id, String action) async {
    await api.rpc('rental_action', {'p_id': id, 'p_action': action});
  }

  Future<List<Map<String, dynamic>>> users() async =>
      (await api.rpc('list_users', {}) as List)
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
  Future<void> changeRole(String id, String role) async {
    await api.rpc('change_role', {'p_user_id': id, 'p_role': role});
  }

  Future<Map<String, dynamic>> summary() async =>
      Map<String, dynamic>.from(await api.rpc('admin_summary', {}));
  Future<void> updateContacts(Map<String, dynamic> data) async {
    await api.rpc('update_my_contacts', {
      'p_full_name': data['full_name'],
      'p_phone': data['phone'],
      'p_email': data['email'],
    });
  }
}
