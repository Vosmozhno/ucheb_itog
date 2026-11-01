import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'core/app_theme.dart';
import 'core/permissions.dart';
import 'data/entity_definitions.dart';
import 'screens/admin_screens.dart';
import 'screens/auth_screen.dart';
import 'screens/booking_screen.dart';
import 'screens/entity_list_screen.dart';
import 'screens/manage_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/record_detail_screen.dart';
import 'screens/record_editor_screen.dart';
import 'state/auth_state.dart';
import 'widgets/app_shell.dart';
import 'widgets/data_states.dart';

String? safeNext(String? value) {
  if (value == null || !value.startsWith('/') || value.startsWith('//')) {
    return null;
  }
  final uri = Uri.tryParse(value);
  return uri != null &&
          ![
            '/login',
            '/register',
            '/loading',
            '/startup-error',
          ].contains(uri.path) &&
          !uri.hasScheme &&
          !uri.hasAuthority
      ? value
      : null;
}

GoRouter createRouter(AuthState auth) => GoRouter(
  refreshListenable: auth,
  redirect: (context, state) {
    final path = state.uri.path;
    if (!auth.ready) {
      return path == '/loading'
          ? null
          : Uri(
              path: '/loading',
              queryParameters: {'next': state.uri.toString()},
            ).toString();
    }
    final next = safeNext(state.uri.queryParameters['next']);
    if (auth.startupError != null) {
      return path == '/startup-error' ? null : '/startup-error';
    }
    if (!auth.signedIn) {
      if (path == '/login' || path == '/register') return null;
      return Uri(
        path: '/login',
        queryParameters: {
          if (path != '/loading') 'next': state.uri.toString(),
          if (path == '/loading' && next != null) 'next': next,
        },
      ).toString();
    }
    if (path == '/' ||
        ['/loading', '/login', '/register', '/startup-error'].contains(path)) {
      return next != null && mayOpen(auth.role, Uri.parse(next).path)
          ? next
          : roleHome(auth.role);
    }
    if (!mayOpen(auth.role, path)) return '/forbidden';
    final entity = state.pathParameters['entity'];
    if (entity != null && !entityDefinitions.any((d) => d.key == entity)) {
      return '/not-found';
    }
    return null;
  },
  routes: [
    GoRoute(path: '/', redirect: (context, state) => '/catalog'),
    GoRoute(
      path: '/loading',
      builder: (context, state) => const Scaffold(
        body: Center(child: LoadingState(label: 'Восстанавливаем сессию…')),
      ),
    ),
    GoRoute(
      path: '/startup-error',
      builder: (context, state) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (auth.startupError != null)
                    ErrorState(
                      error: auth.startupError!,
                      onRetry: auth.restore,
                    ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: auth.expire,
                    child: const Text('Перейти ко входу'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
    GoRoute(
      path: '/login',
      builder: (context, state) =>
          AuthScreen(next: state.uri.queryParameters['next']),
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) =>
          AuthScreen(register: true, next: state.uri.queryParameters['next']),
    ),
    ShellRoute(
      builder: (context, state, child) =>
          AppShell(path: state.uri.path, child: child),
      routes: [
        GoRoute(
          path: '/catalog',
          builder: (context, state) => EntityListScreen(
            entity: 'equipment',
            uri: state.uri,
            mode: EntityListMode.catalog,
          ),
          routes: [
            GoRoute(
              path: ':id',
              builder: (context, state) => RecordDetailScreen(
                entity: 'equipment',
                id: int.tryParse(state.pathParameters['id']!) ?? 0,
                catalog: true,
              ),
            ),
          ],
        ),
        GoRoute(
          path: '/my-rentals',
          builder: (context, state) => EntityListScreen(
            entity: 'rentals',
            uri: state.uri,
            mode: EntityListMode.myRentals,
          ),
          routes: [
            GoRoute(
              path: ':id/edit',
              builder: (context, state) => BookingScreen(
                id: int.tryParse(state.pathParameters['id']!) ?? 0,
              ),
            ),
            GoRoute(
              path: ':id',
              builder: (context, state) => RecordDetailScreen(
                entity: 'rentals',
                id: int.tryParse(state.pathParameters['id']!) ?? 0,
                personal: true,
              ),
            ),
          ],
        ),
        GoRoute(
          path: '/book',
          builder: (context, state) => BookingScreen(
            equipmentId: int.tryParse(
              state.uri.queryParameters['equipment'] ?? '',
            ),
          ),
        ),
        GoRoute(
          path: '/profile',
          builder: (context, state) => const ProfileScreen(),
        ),
        GoRoute(
          path: '/desk',
          builder: (context, state) => EntityListScreen(
            entity: 'rentals',
            uri: state.uri,
            mode: EntityListMode.desk,
          ),
        ),
        GoRoute(
          path: '/admin/overview',
          builder: (context, state) => const AdminOverviewScreen(),
        ),
        GoRoute(
          path: '/admin/users',
          builder: (context, state) => const AdminUsersScreen(),
        ),
        GoRoute(
          path: '/manage',
          builder: (context, state) => const ManageScreen(),
          routes: [
            GoRoute(
              path: ':entity',
              builder: (context, state) => EntityListScreen(
                key: ValueKey(state.pathParameters['entity']),
                entity: state.pathParameters['entity']!,
                uri: state.uri,
              ),
              routes: [
                GoRoute(
                  path: 'new',
                  builder: (context, state) =>
                      state.pathParameters['entity'] == 'rentals'
                      ? const BookingScreen()
                      : RecordEditorScreen(
                          entity: state.pathParameters['entity']!,
                          back: state.uri.queryParameters['back'],
                        ),
                ),
                GoRoute(
                  path: ':id/edit',
                  builder: (context, state) =>
                      state.pathParameters['entity'] == 'rentals'
                      ? BookingScreen(
                          id: int.tryParse(state.pathParameters['id']!) ?? 0,
                        )
                      : RecordEditorScreen(
                          entity: state.pathParameters['entity']!,
                          id: int.tryParse(state.pathParameters['id']!) ?? 0,
                          back: state.uri.queryParameters['back'],
                        ),
                ),
                GoRoute(
                  path: ':id',
                  builder: (context, state) => RecordDetailScreen(
                    entity: state.pathParameters['entity']!,
                    id: int.tryParse(state.pathParameters['id']!) ?? 0,
                  ),
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: '/forbidden',
          builder: (context, state) => _MessageScreen(
            title: 'Доступ запрещён',
            message: 'Этот раздел недоступен для вашей роли.',
            destination: roleHome(auth.role),
          ),
        ),
        GoRoute(
          path: '/not-found',
          builder: (context, state) => const _MessageScreen(
            title: 'Страница не найдена',
            message: 'Проверьте адрес или откройте каталог.',
            destination: '/catalog',
          ),
        ),
      ],
    ),
  ],
  errorBuilder: (context, state) => const Scaffold(
    body: _MessageScreen(
      title: 'Страница не найдена',
      message: 'Проверьте адрес или откройте каталог.',
      destination: '/catalog',
    ),
  ),
);

class TourRentalApp extends StatelessWidget {
  const TourRentalApp({super.key, required this.router});
  final GoRouter router;
  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Поход · Прокат снаряжения',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    routerConfig: router,
    locale: const Locale('ru'),
    supportedLocales: const [Locale('ru')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
  );
}

class _MessageScreen extends StatelessWidget {
  const _MessageScreen({
    required this.title,
    required this.message,
    required this.destination,
  });
  final String title, message, destination;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: EmptyState(
        title: title,
        message: message,
        action: FilledButton(
          onPressed: () => context.go(destination),
          child: const Text('На главную'),
        ),
      ),
    ),
  );
}
