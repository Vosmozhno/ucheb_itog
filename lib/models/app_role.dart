enum AppRole {
  client('client', 'Клиент'),
  employee('employee', 'Сотрудник'),
  admin('admin', 'Администратор');

  const AppRole(this.code, this.label);
  final String code;
  final String label;
  bool get canManage => this == employee || this == admin;
  bool get canDeleteForever => this == admin;
  static AppRole parse(Object? value) =>
      values.firstWhere((r) => r.code == value, orElse: () => client);
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.fullName,
    required this.role,
  });
  final String id;
  final String fullName;
  final AppRole role;
  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: json['id'] as String,
    fullName: json['full_name'] as String,
    role: AppRole.parse(json['role']),
  );
}
