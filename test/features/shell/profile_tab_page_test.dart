import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/features/settings/settings_screen.dart';
import 'package:watch_app/features/shell/root_shell.dart';

void main() {
  test('shared TV rail pages keep Settings at index three', () {
    final pages = buildShellPages(null);

    expect(pages, hasLength(4));
    expect(pages[3], isA<SettingsScreen>());
    expect(pages.last, isA<SettingsScreen>());
  });
}
