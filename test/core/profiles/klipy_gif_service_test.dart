import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/profiles/klipy_gif_service.dart';
import 'package:watch_app/core/profiles/profile_avatar_reference.dart';

void main() {
  test('search uses safe GIF results and preserves provider order', () async {
    final adapter = _Adapter();
    final service = KlipyGifService(
      Dio()..httpClientAdapter = adapter,
      apiKey: 'test-key',
    );

    final results = await service.search(' cat, dance! ');

    expect(results.map((gif) => gif.slug), ['first-gif', 'second-gif']);
    expect(results.first.thumbnailUrl, 'https://static.klipy.com/first-xs.gif');
    expect(results.first.avatarUrl, 'https://static.klipy.com/first-sm.gif');
    expect(adapter.request!.uri.path, '/api/v1/test-key/gifs/search');
    expect(adapter.request!.queryParameters['q'], ' cat, dance! ');
    expect(adapter.request!.queryParameters['content_filter'], 'high');
    expect(adapter.request!.queryParameters['format_filter'], 'gif');
  });

  test(
    'avatar reference resolves directly from KLIPY and is reused in memory',
    () async {
      final adapter = _Adapter();
      final service = KlipyGifService(
        Dio()..httpClientAdapter = adapter,
        apiKey: 'test-key',
      );

      final first = await service.avatarUrlForSlug('first-gif');
      final second = await service.avatarUrlForSlug('first-gif');

      expect(first, 'https://static.klipy.com/first-sm.gif');
      expect(second, first);
      expect(adapter.requests, 1);
      expect(adapter.request!.uri.path, '/api/v1/test-key/gifs/items');
      expect(adapter.request!.queryParameters['slugs'], 'first-gif');
    },
  );

  test('failed avatar lookup can retry after connectivity returns', () async {
    final adapter = _Adapter()..failNextItems = true;
    final service = KlipyGifService(
      Dio()..httpClientAdapter = adapter,
      apiKey: 'test-key',
    );

    expect(await service.avatarUrlForSlug('first-gif'), isNull);
    expect(
      await service.avatarUrlForSlug('first-gif'),
      'https://static.klipy.com/first-sm.gif',
    );
    expect(adapter.requests, 2);
  });

  test('profile avatar references contain a validated slug', () {
    expect(klipyAvatarReference('one-piece-zoro'), 'klipy:one-piece-zoro');
    expect(klipyAvatarSlug('klipy:one-piece-zoro'), 'one-piece-zoro');
    expect(klipyAvatarSlug('klipy:../private'), isNull);
  });

  test('parses KLIPY slugs with uppercase IDs and repeated hyphens', () {
    final gif = KlipyGif.fromJson(_item('hi-6365--kK1W3DOGN', 'zoro'));

    expect(gif?.slug, 'hi-6365--kK1W3DOGN');
  });
}

class _Adapter implements HttpClientAdapter {
  RequestOptions? request;
  int requests = 0;
  bool failNextItems = false;

  @override
  Future<ResponseBody> fetch(RequestOptions options, _, _) async {
    request = options;
    requests++;
    if (options.path.endsWith('/items') && failNextItems) {
      failNextItems = false;
      throw DioException(requestOptions: options);
    }
    final results = [
      _item('first-gif', 'first'),
      _item('second-gif', 'second'),
    ];
    final body = options.path.endsWith('/items')
        ? {
            'result': true,
            'data': {
              'data': [results.first],
            },
          }
        : {
            'result': true,
            'data': {'data': results},
          };
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, dynamic> _item(String slug, String name) => {
  'slug': slug,
  'title': name,
  'file': {
    'xs': {
      'gif': {'url': 'https://static.klipy.com/$name-xs.gif'},
    },
    'sm': {
      'gif': {'url': 'https://static.klipy.com/$name-sm.gif'},
    },
  },
};
