abstract final class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
  );
  // This is a public client key. RLS and RPC permissions protect all records.
  static const publicKey = String.fromEnvironment(
    'SUPABASE_PUBLIC_KEY',
  );
  static const authRoleDemo = bool.fromEnvironment('AUTH_ROLE_DEMO');
}
