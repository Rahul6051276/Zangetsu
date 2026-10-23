import 'package:flutter_test/flutter_test.dart';
import 'package:watch_app/core/playback/playback_prefs.dart';

void main() {
  test('enhancement off uses MPV default scalers', () {
    expect(mpvScalerOptions(enhancementEnabled: false, highQuality: false), {
      'scale': 'lanczos',
      'cscale': 'lanczos',
      'dscale': 'hermite',
    });
  });

  test('enhancement mid tier keeps the existing fast scalers', () {
    expect(mpvScalerOptions(enhancementEnabled: true, highQuality: false), {
      'scale': 'bilinear',
      'cscale': 'bilinear',
      'dscale': 'bilinear',
    });
  });

  test('enhancement high tier keeps the existing quality scalers', () {
    expect(mpvScalerOptions(enhancementEnabled: true, highQuality: true), {
      'scale': 'spline36',
      'cscale': 'spline36',
      'dscale': 'mitchell',
    });
  });
}
