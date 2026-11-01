import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:tour_rental/app.dart';
import 'package:tour_rental/core/api_error.dart';
import 'package:tour_rental/core/supabase_api.dart';
import 'package:tour_rental/models/app_role.dart';
import 'package:tour_rental/models/entity_record.dart';
import 'package:tour_rental/models/page_result.dart';
import 'package:tour_rental/repositories/repository_registry.dart';
import 'package:tour_rental/repositories/rental_service.dart';
import 'package:tour_rental/state/auth_state.dart';
import 'package:tour_rental/widgets/data_states.dart';
import 'support/fake_http.dart';
import 'support/fake_repositories.dart';

Future<GoRouter> mountApp(
  WidgetTester tester, {
  String path = '/manage/categories',
  AppRole? role = AppRole.employee,
  RepositoryRegistry? registry,
  FakeRentalService? rental,
  bool settle = true,
  void Function()? onHttp,
  FakeResponse? response,
}) async {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test'));
  dio.httpClientAdapter = FakeHttpAdapter((request) {
    onHttp?.call();
    return response ??
        const FakeResponse({'error_code': 'invalid_credentials'}, status: 400);
  });
  final api = SupabaseApi(dio: dio),
      auth = AuthState(SupabaseApi(dio: dio), MemorySessionStore())
        ..ready = true;
  if (role != null) {
    auth.profile = UserProfile(
      id: 'user-1',
      fullName: 'Тестовый пользователь',
      role: role,
    );
  }
  final router = createRouter(auth)..go(path);
  final service = rental ?? FakeRentalService();
  addTearDown(() {
    router.dispose();
    auth.dispose();
    api.close();
    service.api.close();
  });
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: auth),
        Provider<RepositoryRegistry>.value(
          value: registry ?? fixtureRegistry(),
        ),
        Provider<RentalService>.value(value: service),
      ],
      child: TourRentalApp(router: router),
    ),
  );
  await tester.pump();
  if (settle) await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('A forbidden destination stays forbidden after session restore', (
    tester,
  ) async {
    final router = await mountApp(
      tester,
      path: '/loading?next=%2Fdesk',
      role: AppRole.admin,
    );
    expect(router.routeInformationProvider.value.uri.path, '/forbidden');
    expect(find.text('Этот раздел недоступен для вашей роли.'), findsOneWidget);
  });
  testWidgets('A shared URL can select sorting by creation date', (
    tester,
  ) async {
    await mountApp(
      tester,
      path: '/manage/categories?sort=created_at&direction=asc',
    );
    expect(find.text('Дата создания ↑'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Empty login fields display errors without sending a request', (
    tester,
  ) async {
    var requests = 0;
    await mountApp(
      tester,
      path: '/login',
      role: null,
      onHttp: () => requests++,
    );
    await tester.tap(find.text('Войти'));
    await tester.pump();
    expect(find.text('Обязательное поле'), findsOneWidget);
    expect(find.text('Введите пароль'), findsOneWidget);
    expect(requests, 0);
  });
  testWidgets(
    'A registration email error from the server appears beside the field',
    (tester) async {
      await mountApp(
        tester,
        path: '/register',
        role: null,
        response: const FakeResponse({
          'error_code': 'user_already_exists',
        }, status: 422),
      );
      final values = [
        'Новый клиент',
        '+79000000004',
        'existing@example.test',
        'ValidPass!42',
        'ValidPass!42',
      ];
      for (var i = 0; i < values.length; i++) {
        await tester.enterText(find.byType(TextFormField).at(i), values[i]);
      }
      await tester.ensureVisible(find.text('Зарегистрироваться'));
      await tester.tap(find.text('Зарегистрироваться'));
      await tester.pumpAndSettle();
      expect(find.text('Этот адрес уже зарегистрирован'), findsOneWidget);
    },
  );
  testWidgets('The list moves from loading to the empty state', (tester) async {
    final deferred = Completer<PageResult<EntityRecord>>(),
        repo = MemoryRepository();
    repo.findOverride = (q) => deferred.future;
    final registry = fixtureRegistry();
    registry.repositories['categories'] = repo;
    await mountApp(tester, registry: registry, settle: false);
    expect(find.byType(LoadingState), findsOneWidget);
    deferred.complete(
      const PageResult(items: [], total: 0, page: 1, pageSize: 10),
    );
    await tester.pumpAndSettle();
    expect(find.text('Записей пока нет'), findsOneWidget);
  });
  testWidgets('A failed list request offers retry and then displays data', (
    tester,
  ) async {
    var attempts = 0;
    final repo = MemoryRepository()
      ..findOverride = (q) async {
        attempts++;
        if (attempts == 1) {
          throw const ApiError(ApiErrorKind.network, 'Нет сети');
        }
        return PageResult(
          items: [
            EntityRecord({
              'id': 1,
              'name': 'Палатки теста',
              'description': 'Снаряжение',
            }),
          ],
          total: 1,
          page: 1,
          pageSize: 10,
        );
      };
    final registry = fixtureRegistry();
    registry.repositories['categories'] = repo;
    await mountApp(tester, registry: registry);
    expect(find.text('Нет сети'), findsOneWidget);
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(find.text('Палатки теста'), findsOneWidget);
    expect(attempts, 2);
  });
  testWidgets('A direct employee URL is guarded for the administrator', (
    tester,
  ) async {
    final router = await mountApp(tester, path: '/desk', role: AppRole.admin);
    expect(router.routeInformationProvider.value.uri.path, '/forbidden');
    expect(find.text('Этот раздел недоступен для вашей роли.'), findsOneWidget);
  });
  testWidgets('The sidebar remains accessible beside the nested Navigator', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();
    await mountApp(tester);
    expect(find.bySemanticsLabel('Каталог'), findsOneWidget);
    expect(find.bySemanticsLabel('Справочники'), findsOneWidget);
    semantics.dispose();
  });
  testWidgets(
    'Booking requires a quote and saves multiple units and services',
    (tester) async {
      final repo = FakeRentalRepository(), service = FakeRentalService();
      final router = await mountApp(
        tester,
        path: '/book',
        role: AppRole.client,
        registry: fixtureRegistry(rentals: repo),
        rental: service,
      );
      var save = find.widgetWithText(FilledButton, 'Забронировать');
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      await tester.ensureVisible(find.text('Проверить доступность'));
      await tester.tap(find.text('Проверить доступность'));
      await tester.pumpAndSettle();
      for (var i = 0; i < 2; i++) {
        final checkbox = find.byType(CheckboxListTile).at(i);
        await tester.ensureVisible(checkbox);
        await tester.tap(checkbox);
        await tester.pumpAndSettle();
      }
      final extra = find.widgetWithText(FilterChip, 'Подготовка · 300 ₽');
      await tester.ensureVisible(extra);
      await tester.tap(extra);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Рассчитать стоимость'));
      await tester.tap(find.text('Рассчитать стоимость'));
      await tester.pumpAndSettle();
      expect(service.quoteCalls, 1);
      save = find.widgetWithText(FilledButton, 'Забронировать');
      await tester.ensureVisible(save);
      await tester.tap(save);
      await tester.pumpAndSettle();
      expect(repo.lastCreated?['unit_ids'], [1, 2]);
      expect(repo.lastCreated?['service_ids'], [1]);
      expect(repo.lastCreated?['expected_total'], 1630);
      expect(router.routeInformationProvider.value.uri.path, '/my-rentals/100');
      expect(find.text('Аренда №100'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('Cancelling a role change restores its displayed value', (
    tester,
  ) async {
    final service = FakeRentalService()
      ..fakeUsers = [
        {
          'id': 'user-2',
          'full_name': 'Другой пользователь',
          'email': 'other@pohod.example',
          'role': 'client',
          'created_at': '2026-11-02',
        },
      ];
    await mountApp(
      tester,
      path: '/admin/users',
      role: AppRole.admin,
      rental: service,
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сотрудник').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(service.fakeUsers.single['role'], 'client');
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byType(DropdownButtonFormField<String>),
          )
          .initialValue,
      'client',
    );
  });
  for (final width in [360.0, 768.0, 1920.0]) {
    testWidgets('Booking lays out without overflow at width $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mountApp(tester, path: '/book', role: AppRole.client);
      expect(find.text('Собрать свой поход'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
