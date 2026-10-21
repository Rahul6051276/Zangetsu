import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/app_mode.dart';

void main() {
  test('AppMode exposes the injected isTv value', () {
    expect(const AppMode(isTv: true).isTv, isTrue);
    expect(const AppMode(isTv: false).isTv, isFalse);
  });

  test('TV preview can force TV mode only in a debug build', () {
    expect(
      resolveIsTvMode(
        deviceIsTv: true,
        forceTvPreview: false,
        debugBuild: false,
      ),
      isTrue,
    );
    expect(
      resolveIsTvMode(
        deviceIsTv: false,
        forceTvPreview: false,
        debugBuild: true,
      ),
      isFalse,
    );
    expect(
      resolveIsTvMode(
        deviceIsTv: false,
        forceTvPreview: true,
        debugBuild: true,
      ),
      isTrue,
    );
    expect(
      resolveIsTvMode(
        deviceIsTv: false,
        forceTvPreview: true,
        debugBuild: false,
      ),
      isFalse,
    );
  });
}
