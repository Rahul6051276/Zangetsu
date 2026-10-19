import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestClient, PostgrestQueryBuilder;

import 'supabase_service.dart';

/// Routes table access to the active cloud backend.
///
/// Older builds keep talking to Supabase. When [vpsClient] is supplied, the
/// same PostgREST calls go to the VPS instead — Supabase stays the auth issuer
/// and its access token is forwarded as the bearer credential.
class CloudPostgrest {
  CloudPostgrest(
    this._service, {
    PostgrestClient? vpsClient,
    String? Function()? accessToken,
  }) : _vpsClient = vpsClient,
       _accessToken = accessToken;

  final SupabaseService _service;
  final PostgrestClient? _vpsClient;
  final String? Function()? _accessToken;

  PostgrestQueryBuilder from(String table) {
    final vpsClient = _vpsClient;
    if (vpsClient == null) return _service.client.from(table);
    final token =
        (_accessToken ??
                () => _service.client.auth.currentSession?.accessToken)()
            ?.trim();
    if (token == null || token.isEmpty) {
      throw StateError('A signed-in session is required for cloud sync');
    }
    return vpsClient.setAuth(token).from(table);
  }
}
