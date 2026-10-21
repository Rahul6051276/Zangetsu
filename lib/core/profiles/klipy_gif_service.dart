import 'package:dio/dio.dart';

import '../app_config.dart';
import 'profile_avatar_reference.dart';

class KlipyGif {
  const KlipyGif({
    required this.slug,
    required this.title,
    required this.thumbnailUrl,
    required this.avatarUrl,
  });

  final String slug;
  final String title;
  final String thumbnailUrl;
  final String avatarUrl;

  static KlipyGif? fromJson(Object? value) {
    if (value is! Map) return null;
    final slug = value['slug'];
    if (slug is! String ||
        klipyAvatarSlug(klipyAvatarReference(slug)) == null) {
      return null;
    }
    final files = value['file'];
    if (files is! Map) return null;
    final thumbnail = _mediaUrl(files, const ['xs', 'sm', 'md', 'hd']);
    final avatar = _mediaUrl(files, const ['sm', 'md', 'xs', 'hd']);
    if (thumbnail == null || avatar == null) return null;
    final title = value['title'];
    return KlipyGif(
      slug: slug,
      title: title is String ? title : '',
      thumbnailUrl: thumbnail,
      avatarUrl: avatar,
    );
  }
}

class KlipyGifService {
  KlipyGifService(this._dio, {String? apiKey})
    : _apiKey = apiKey ?? kKlipyApiKey;

  static final shared = KlipyGifService(
    Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
      ),
    ),
  );

  static const _host = 'api.klipy.com';
  final Dio _dio;
  final String _apiKey;
  final Map<String, Future<String?>> _avatarUrls = {};

  bool get isConfigured => _apiKey.trim().isNotEmpty;

  Future<List<KlipyGif>> search(
    String query, {
    CancelToken? cancelToken,
  }) async {
    if (!isConfigured || query.trim().isEmpty) return const [];
    final response = await _dio.get<dynamic>(
      _url('gifs/search'),
      queryParameters: {
        'q': query,
        'page': 1,
        'per_page': 24,
        'content_filter': 'high',
        'format_filter': 'gif',
      },
      cancelToken: cancelToken,
    );
    return _rows(
      response.data,
    ).map(KlipyGif.fromJson).whereType<KlipyGif>().toList(growable: false);
  }

  /// Resolves older profiles that stored only a KLIPY slug.
  Future<String?> avatarUrlForSlug(String slug) {
    if (!isConfigured || klipyAvatarSlug(klipyAvatarReference(slug)) == null) {
      return Future.value(null);
    }
    return _avatarUrls.putIfAbsent(slug, () => _resolveAvatar(slug));
  }

  Future<void> registerSelection(KlipyGif gif, String query) async {
    if (!isConfigured) return;
    try {
      await _dio.post<void>(
        _url('gifs/share/${Uri.encodeComponent(gif.slug)}'),
        data: {'q': query},
      );
    } catch (_) {
      // Selection still works if KLIPY's optional usage-tracking call fails.
    }
  }

  Future<String?> _resolveAvatar(String slug) async {
    try {
      final response = await _dio.get<dynamic>(
        _url('gifs/items'),
        queryParameters: {'slugs': slug, 'format_filter': 'gif'},
      );
      for (final row in _rows(response.data)) {
        final gif = KlipyGif.fromJson(row);
        if (gif?.slug == slug) return gif?.avatarUrl;
      }
    } catch (_) {
      // Keep profile rendering usable when the provider is offline.
      _avatarUrls.remove(slug);
    }
    return null;
  }

  String _url(String path) =>
      'https://$_host/api/v1/${Uri.encodeComponent(_apiKey.trim())}/$path';

  static List<Object?> _rows(Object? body) {
    if (body is! Map || body['result'] != true) return const [];
    final data = body['data'];
    if (data is! Map || data['data'] is! List) return const [];
    return (data['data'] as List).cast<Object?>();
  }
}

String? _mediaUrl(Object? files, List<String> sizes) {
  if (files is! Map) return null;
  for (final size in sizes) {
    final formats = files[size];
    if (formats is! Map) continue;
    final image = formats['gif'];
    if (image is! Map || image['url'] is! String) continue;
    final value = image['url'] as String;
    if (isKlipyAvatarMediaUrl(value)) return value;
  }
  return null;
}
