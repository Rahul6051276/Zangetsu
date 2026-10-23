import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:watch_app/core/download/download_manager.dart';
import 'package:watch_app/core/download/download_record.dart';
import 'package:watch_app/core/playback/resume_store.dart';
import 'package:watch_app/features/downloads/downloads_screen.dart';

class _FakeDownloadManager extends ChangeNotifier implements DownloadManager {
  @override
  Map<String, List<DownloadRecord>> get byShow => const {};

  @override
  List<DownloadRecord> get all => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DownloadRecord _record() => DownloadRecord(
  id: 'd1',
  sourceId: 'src',
  showId: 'show',
  showTitle: 'Show',
  showUrl: '/show/1',
  episodeId: 'ep1',
  episodeUrl: '',
  episodeNumber: 3,
  episodeTitle: 'Pilot',
  category: 'sub',
  quality: '1080p',
  status: DownloadStatus.done,
  progress: 1,
  bytesTotal: 120 * 1024 * 1024,
  filePath: '/tmp/ep1.mkv',
  subtitles: const [OfflineSubtitle(lang: 'en', path: '/tmp/ep1.vtt')],
  createdAt: 0,
);

void main() {
  late Directory dir;
  late ResumeStore resume;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('watch_tile_meta');
    Hive.init(dir.path);
    await Hive.openBox<Map>(ResumeStore.boxName);
    resume = ResumeStore();
  });

  tearDown(() async {
    await Hive.close();
    await dir.delete(recursive: true);
  });

  testWidgets('finished download shows quality, CC and watch progress', (
    tester,
  ) async {
    await tester.runAsync(
      () => resume.save(
        'src',
        '/show/1',
        'ep1',
        const Duration(minutes: 8, seconds: 32),
        const Duration(minutes: 24, seconds: 10),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DownloadTile(
            record: _record(),
            manager: _FakeDownloadManager(),
            resume: resume,
          ),
        ),
      ),
    );
    expect(find.textContaining('1080p · CC EN · 8:32 / 24:10'), findsOneWidget);

    // A saved position from another screen refreshes the line in place.
    await tester.runAsync(
      () => resume.save(
        'src',
        '/show/1',
        'ep1',
        const Duration(minutes: 12),
        const Duration(minutes: 24, seconds: 10),
      ),
    );
    await tester.pump();
    expect(find.textContaining('12:00 / 24:10'), findsOneWidget);
  });
}
