import '../models/app_role.dart';

bool mayOpen(AppRole role, String path) {
  if (path == '/my-rentals' ||
      path.startsWith('/my-rentals/') ||
      path == '/profile') {
    return role == AppRole.client;
  }
  if (path == '/desk' || path.startsWith('/desk/')) {
    return role == AppRole.employee;
  }
  if (path.startsWith('/admin/')) return role == AppRole.admin;
  if (path == '/manage' || path.startsWith('/manage/')) return role.canManage;
  return true;
}

String roleHome(AppRole role) => switch (role) {
  AppRole.client => '/my-rentals',
  AppRole.employee => '/desk',
  AppRole.admin => '/admin/overview',
};
