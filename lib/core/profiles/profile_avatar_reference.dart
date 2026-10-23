const String klipyAvatarPrefix = 'klipy:';
const Set<String> _klipyAvatarHosts = {
  'static.klipy.com',
  'static1.klipy.com',
  'static2.klipy.com',
};

bool isKlipyAvatarReference(String? value) =>
    value?.startsWith(klipyAvatarPrefix) ?? false;

bool isKlipyAvatarMediaUrl(String? value) {
  final uri = value == null ? null : Uri.tryParse(value);
  return uri != null &&
      uri.scheme == 'https' &&
      _klipyAvatarHosts.contains(uri.host);
}

String? klipyAvatarSlug(String? value) {
  if (!isKlipyAvatarReference(value)) return null;
  final slug = value!.substring(klipyAvatarPrefix.length);
  return RegExp(r'^[A-Za-z0-9]+(?:-+[A-Za-z0-9]+)*$').hasMatch(slug)
      ? slug
      : null;
}

String klipyAvatarReference(String slug) => '$klipyAvatarPrefix$slug';
