import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app.dart';
import 'core/supabase_api.dart';
import 'core/config.dart';
import 'repositories/repository_registry.dart';
import 'repositories/rental_service.dart';
import 'repositories/session_store.dart';
import 'state/auth_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  if (AppConfig.supabaseUrl.isEmpty || AppConfig.publicKey.isEmpty) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'Передайте SUPABASE_URL и SUPABASE_PUBLIC_KEY параметрами сборки',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
    return;
  }
  final preferences = await SharedPreferences.getInstance();
  final api = SupabaseApi();
  final auth = AuthState(api, PreferencesSessionStore(preferences));
  final router = createRouter(auth);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        Provider.value(value: RepositoryRegistry(api)),
        Provider.value(value: RentalService(api)),
      ],
      child: TourRentalApp(router: router),
    ),
  );
  unawaited(auth.restore());
}
