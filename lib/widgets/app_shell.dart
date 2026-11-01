import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/app_theme.dart';
import '../models/app_role.dart';
import '../state/auth_state.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.child, required this.path});
  final Widget child;
  final String path;
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthState>();
    final destinations = <({String path, String label, IconData icon})>[
      if (auth.role == AppRole.client)
        (path: '/my-rentals', label: 'Мои аренды', icon: Icons.hiking_outlined),
      if (auth.role == AppRole.employee)
        (
          path: '/desk',
          label: 'Выдача и возврат',
          icon: Icons.assignment_return_outlined,
        ),
      if (auth.role == AppRole.admin)
        (
          path: '/admin/overview',
          label: 'Сводка',
          icon: Icons.dashboard_outlined,
        ),
      (path: '/catalog', label: 'Каталог', icon: Icons.backpack_outlined),
      if (auth.role.canManage) ...[
        (
          path: '/manage/rentals',
          label: 'Аренды',
          icon: Icons.calendar_month_outlined,
        ),
        (
          path: '/manage/equipment',
          label: 'Снаряжение',
          icon: Icons.inventory_2_outlined,
        ),
        (
          path: '/manage',
          label: 'Справочники',
          icon: Icons.folder_copy_outlined,
        ),
      ],
      if (auth.role == AppRole.admin)
        (
          path: '/admin/users',
          label: 'Пользователи',
          icon: Icons.manage_accounts_outlined,
        ),
      if (auth.role == AppRole.client)
        (path: '/profile', label: 'Мой профиль', icon: Icons.person_outline),
    ];
    final wide = MediaQuery.sizeOf(context).width >= 1100;
    Widget navigation() => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(22, 28, 20, 32),
          child: Row(
            children: [
              Icon(Icons.terrain, size: 32, color: AppTheme.forest),
              SizedBox(width: 10),
              Text(
                'ПОХОД',
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final destination in destinations)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    selected:
                        path == destination.path ||
                        (destination.path != '/manage' &&
                            path.startsWith('${destination.path}/')),
                    selectedTileColor: const Color(0xFFE5EEE3),
                    selectedColor: AppTheme.forest,
                    leading: Icon(destination.icon, size: 22),
                    title: Text(
                      destination.label,
                      style: const TextStyle(fontSize: 14),
                    ),
                    onTap: () {
                      if (!wide) Navigator.of(context).pop();
                      context.go(destination.path);
                    },
                  ),
                ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(22),
          child: Text(
            'Снаряжение для\nваших маршрутов',
            style: TextStyle(color: Color(0xFF6A786B), height: 1.6),
          ),
        ),
      ],
    );
    return Scaffold(
      drawer: wide ? null : Drawer(child: SafeArea(child: navigation())),
      appBar: wide
          ? null
          : AppBar(
              title: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.terrain, color: AppTheme.forest),
                  SizedBox(width: 8),
                  Text('Поход'),
                ],
              ),
              actions: [_AccountMenu(auth: auth)],
            ),
      body: SafeArea(
        child: Row(
          children: [
            if (wide) ...[
              SizedBox(
                width: 236,
                child: Material(color: Colors.white, child: navigation()),
              ),
              const VerticalDivider(width: 1),
            ],
            Expanded(
              child: Column(
                children: [
                  if (wide)
                    Container(
                      height: 72,
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      color: Colors.white,
                      child: Row(
                        children: [
                          Text(
                            'Прокат туристического снаряжения',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const Spacer(),
                          _AccountMenu(auth: auth),
                        ],
                      ),
                    ),
                  if (auth.hasDemoOverride)
                    Container(
                      width: double.infinity,
                      color: const Color(0xFFFFEECF),
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'Учебная проверка: роль интерфейса — ${auth.role.label}. Сервер проверяет роль учётной записи.',
                      ),
                    ),
                  Expanded(
                    child: Semantics(
                      container: true,
                      explicitChildNodes: true,
                      child: child,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountMenu extends StatelessWidget {
  const _AccountMenu({required this.auth});
  final AuthState auth;
  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: 'Учётная запись',
    onSelected: (value) async {
      if (value == 'logout') await auth.logout();
      if (value == 'profile' && context.mounted) context.go('/profile');
    },
    itemBuilder: (context) => [
      PopupMenuItem<String>(
        enabled: false,
        child: Text('${auth.profile?.fullName ?? ''}\n${auth.role.label}'),
      ),
      if (auth.role == AppRole.client)
        const PopupMenuItem(value: 'profile', child: Text('Мой профиль')),
      const PopupMenuItem(value: 'logout', child: Text('Выйти')),
    ],
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: const Color(0xFFE5EEE3),
            child: Text(
              auth.profile?.fullName.characters.firstOrNull ?? 'П',
              style: const TextStyle(
                color: AppTheme.forest,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (MediaQuery.sizeOf(context).width >= 600) ...[
            const SizedBox(width: 10),
            Text(auth.role.label),
            const SizedBox(width: 6),
            const Icon(Icons.expand_more, size: 18),
          ],
        ],
      ),
    ),
  );
}
