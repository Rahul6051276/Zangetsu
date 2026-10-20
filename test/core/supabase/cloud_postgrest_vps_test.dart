import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestClient;
import 'package:watch_app/core/backup/backup_cloud.dart';
import 'package:watch_app/core/playback/category_store.dart';
import 'package:watch_app/core/playback/my_list.dart';
import 'package:watch_app/core/profiles/viewer_profile.dart';
import 'package:watch_app/core/reading/read_history.dart';
import 'package:watch_app/core/supabase/cloud_postgrest.dart';
import 'package:watch_app/core/supabase/supabase_service.dart';

/// Every remote that can be routed to the VPS must send the Supabase access
/// token and hit the VPS path, not the Supabase one.
void main() {
  late HttpServer server;
  late PostgrestClient client;
  late List<String?> authorizations;
  late List<String> paths;
  late List<Map<String, dynamic>> requestBodies;
  String? token;

  setUp(() async {
    authorizations = [];
    paths = [];
    requestBodies = [];
    token = 'first-token';
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      authorizations.add(
        request.headers.value(HttpHeaders.authorizationHeader),
      );
      paths.add(request.uri.path);
      final body = await utf8.decoder.bind(request).join();
      if (body.isNotEmpty) {
        requestBodies.add(jsonDecode(body) as Map<String, dynamic>);
      }
      if (request.method == 'GET') {
        request.response
          ..statusCode = HttpStatus.ok
          ..headers.contentType = ContentType.json
          ..write('[]');
      } else {
        request.response.statusCode = HttpStatus.noContent;
      }
      await request.response.close();
    });
    client = PostgrestClient('http://127.0.0.1:${server.port}');
  });

  tearDown(() async {
    await client.dispose();
    await server.close(force: true);
  });

  test('my-list rows route to the VPS list tables', () async {
    final remote = MyListRemote(
      SupabaseService(),
      vpsClient: client,
      accessToken: () => token,
    );

    await remote.upsert(const <String, dynamic>{
      'user_key': 'user-1',
      'source_id': 'source',
      'item_id': 'item',
    });
    token = 'refreshed-token';
    await remote.upsert(const <String, dynamic>{
      'user_key': 'user-1',
      'profile_id': 'profile-1',
      'source_id': 'source',
      'item_id': 'item',
    });

    expect(paths, ['/mylist', '/profile_mylist']);
    expect(authorizations, ['Bearer first-token', 'Bearer refreshed-token']);
  });

  test('categories route to the VPS category tables', () async {
    final remote = CategoryRemote(
      SupabaseService(),
      vpsClient: client,
      accessToken: () => token,
    );

    await remote.upsertCategory(const <String, dynamic>{
      'user_key': 'user-1',
      'name': 'Favorites',
    });
    await remote.upsertCategory(const <String, dynamic>{
      'user_key': 'user-1',
      'profile_id': 'profile-1',
      'name': 'Favorites',
    });

    expect(paths, ['/list_categories', '/profile_list_categories']);
  });

  test('reading history routes to the VPS reading tables', () async {
    final remote = ReadingHistoryRemote(
      SupabaseService(),
      vpsClient: client,
      accessToken: () => token,
    );

    await remote.upsert(const <String, dynamic>{
      'user_key': 'user-1',
      'source_id': 'source',
      'show_id': 'show',
      'updated_ms': 1,
    });
    await remote.upsert(const <String, dynamic>{
      'user_key': 'user-1',
      'profile_id': 'profile-1',
      'source_id': 'source',
      'show_id': 'show',
      'updated_ms': 1,
    });

    expect(paths, ['/reading_history', '/profile_reading_history']);
  });

  test('viewer profiles route to the VPS profile table', () async {
    final remote = ViewerProfileRemote(
      SupabaseService(),
      vpsClient: client,
      accessToken: () => token,
    );

    await remote.upsert(
      'user-1',
      const ViewerProfile(
        id: 'profile-1',
        name: 'Viewer',
        accentColor: 0xFF4D8DFF,
        materialYou: true,
        amoled: false,
      ),
    );

    expect(paths, ['/viewer_profiles']);
    expect(authorizations, ['Bearer first-token']);
    expect(requestBodies.single['accent_color'], 0xFF4D8DFF);
    expect(requestBodies.single['material_you'], isTrue);
    expect(requestBodies.single['amoled'], isFalse);
  });

  test('backups route to the VPS backup table', () async {
    final remote = BackupRemote(
      SupabaseService(),
      vpsClient: client,
      accessToken: () => token,
    );

    await remote.upsertRow(const <String, dynamic>{
      'user_key': 'user-1',
      'payload': '{}',
    });

    expect(paths, ['/backups']);
  });

  test('missing session fails closed without contacting VPS', () async {
    token = null;
    final remote = BackupRemote(
      SupabaseService(),
      vpsClient: client,
      accessToken: () => token,
    );

    await expectLater(
      remote.upsertRow(const <String, dynamic>{
        'user_key': 'user-1',
        'payload': '{}',
      }),
      throwsStateError,
    );
    expect(paths, isEmpty);
  });

  test('missing VPS client never falls back to Supabase table access', () {
    final cloud = CloudPostgrest(SupabaseService());

    expect(
      () => cloud.from('mylist'),
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'VPS cloud backend is not configured',
        ),
      ),
    );
  });
}
