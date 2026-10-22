import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/di/injector.dart';
import 'package:watch_app/core/supabase/auth_user.dart';
import 'package:watch_app/features/auth/auth_cubit.dart';

void main() {
  const cachedUser = AuthUser(
    id: 'cached',
    name: 'User',
    email: 'u@example.com',
  );

  test('cached signed-in account owns local writes without a session', () {
    const state = AuthState(
      status: AuthStatus.authenticated,
      user: cachedUser,
      needsReconnect: true,
    );
    expect(localSyncUserId(state, null), 'cached');
  });

  test('signed-out state never uses a lingering session identity', () {
    const state = AuthState(status: AuthStatus.unauthenticated);
    expect(localSyncUserId(state, 'old-session'), isNull);
  });

  test('session identity is available before auth restoration completes', () {
    expect(localSyncUserId(const AuthState(), 'session'), 'session');
  });
}
