import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestClient;
import 'package:watch_app/core/playback/watch_history.dart';
import 'package:watch_app/core/supabase/supabase_service.dart';

void main() {
  late HttpServer server;
  late PostgrestClient client;
  late List<String?> authorizations;
  late List<String> paths;
  String? token;

  setUp(() async {
    authorizations = [];
    paths = [];
    token = 'first-token';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      authorizations.add(
        request.headers.value(HttpHeaders.authorizationHeader),
      );
      paths.add(request.uri.path);
      await request.drain<void>();
      request.response.statusCode = HttpStatus.noContent;
      await request.response.close();
    });
    client = PostgrestClient('http://127.0.0.1:${server.port}');
  });

  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
  });

  test('watch-history VPS requests use the current access token', () async {
    final remote = HistoryRemote(
      SupabaseService(),
      vpsClient: client,
      accessToken: () => token,
    );
    const row = <String, dynamic>{
      'user_key': 'user-1',
      'source_id': 'source',
      'show_id': 'show',
      'updated_at': 1,
    };

    await remote.upsert(row);
    token = 'refreshed-token';
    await remote.upsert(row);

    expect(paths, ['/history', '/history']);
    expect(authorizations, ['Bearer first-token', 'Bearer refreshed-token']);
  });

  test('profile-scoped history uses its own table', () async {
    final remote = HistoryRemote(
      SupabaseService(),
      vpsClient: client,
      accessToken: () => token,
    );

    await remote.upsert(const <String, dynamic>{
      'user_key': 'user-1',
      'profile_id': 'profile-1',
      'source_id': 'source',
      'show_id': 'show',
      'updated_at': 1,
    });

    expect(paths, ['/profile_history']);
  });

  test('missing session fails closed without contacting VPS', () async {
    token = null;
    final remote = HistoryRemote(
      SupabaseService(),
      vpsClient: client,
      accessToken: () => token,
    );

    await expectLater(
      remote.upsert(const <String, dynamic>{
        'user_key': 'user-1',
        'source_id': 'source',
        'show_id': 'show',
      }),
      throwsStateError,
    );
    expect(paths, isEmpty);
  });
}
