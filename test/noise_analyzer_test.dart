import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noise_alert/data/audio/noise_analyzer.dart';
import 'package:noise_alert/domain/acoustic_metrics.dart';

const double _fs = 48000;
const double _offset = 120; // dB SPL at full scale, the uncalibrated default.

/// A 1 kHz tone, where A-weighting is unity gain, so the expected level can be
/// worked out on paper: 20·log10(amplitude/√2) + offset.
Float64List _tone({
  required double seconds,
  required double amplitude,
  double frequency = 1000,
}) {
  final int n = (seconds * _fs).round();
  final Float64List out = Float64List(n);
  for (int i = 0; i < n; i++) {
    out[i] = amplitude * math.sin(2 * math.pi * frequency * i / _fs);
  }
  return out;
}

Float64List _concat(List<Float64List> parts) {
  final int total = parts.fold(0, (int sum, Float64List p) => sum + p.length);
  final Float64List out = Float64List(total);
  int at = 0;
  for (final Float64List part in parts) {
    out.setRange(at, at + part.length, part);
    at += part.length;
  }
  return out;
}

double _expectedDb(double amplitude) =>
    20 * math.log(amplitude / math.sqrt2) / math.ln10 + _offset;

void main() {
  const NoiseAnalyzer analyzer = NoiseAnalyzer();

  test('LAeq of a steady 1 kHz tone matches the arithmetic', () {
    final AcousticMetrics m = analyzer.analyze(
      samples: _tone(seconds: 3, amplitude: 0.1),
      sampleRate: _fs,
      calibrationOffsetDb: _offset,
      calibrated: false,
      peakWindowSeconds: 1,
    );

    expect(m.laEqDb, closeTo(_expectedDb(0.1), 0.2));
    expect(m.laMaxDb, closeTo(_expectedDb(0.1), 0.3));
    expect(m.calibrated, isFalse);
    expect(m.clipped, isFalse);
  });

  test('the peak window lands on the loudest slice, not the first', () {
    // 6 s quiet, then 4 s loud, then 6 s quiet — the shape of an overflight.
    final Float64List samples = _concat(<Float64List>[
      _tone(seconds: 6, amplitude: 0.005),
      _tone(seconds: 4, amplitude: 0.2),
      _tone(seconds: 6, amplitude: 0.005),
    ]);

    final AcousticMetrics m = analyzer.analyze(
      samples: samples,
      sampleRate: _fs,
      calibrationOffsetDb: _offset,
      calibrated: false,
      ambientSampleCount: (5 * _fs).round(),
      peakWindowSeconds: 4,
    );

    // The loud section starts at 6 s; the window should sit on it.
    expect(m.peakWindowStartMs, closeTo(6000, 250));
    expect(m.peakWindowDurationMs, 4000);
    expect(m.peakWindowLaEqDb, closeTo(_expectedDb(0.2), 0.3));

    // ...and comfortably above the level of the whole 16 s, which is diluted
    // by the quiet parts.
    expect(m.peakWindowLaEqDb, greaterThan(m.laEqDb + 3));
  });

  test(
      'ambient L90 comes from the pre-roll only, so the event does not '
      'inflate the background', () {
    final Float64List samples = _concat(<Float64List>[
      _tone(seconds: 10, amplitude: 0.002),
      _tone(seconds: 10, amplitude: 0.2),
    ]);

    final AcousticMetrics m = analyzer.analyze(
      samples: samples,
      sampleRate: _fs,
      calibrationOffsetDb: _offset,
      calibrated: false,
      ambientSampleCount: (10 * _fs).round(),
      peakWindowSeconds: 5,
    );

    expect(m.ambientLa90Db, closeTo(_expectedDb(0.002), 0.5));

    // The figure that survives an uncalibrated microphone: the offset cancels.
    expect(m.excessOverAmbientDb, closeTo(40, 1.0));

    final AcousticMetrics shifted = analyzer.analyze(
      samples: samples,
      sampleRate: _fs,
      calibrationOffsetDb: _offset + 17,
      calibrated: false,
      ambientSampleCount: (10 * _fs).round(),
      peakWindowSeconds: 5,
    );
    expect(shifted.excessOverAmbientDb, closeTo(m.excessOverAmbientDb, 0.001));
    expect(shifted.laMaxDb, closeTo(m.laMaxDb + 17, 0.001));
  });

  test('clipping is reported so the complaint can say "at least this loud"',
      () {
    final AcousticMetrics m = analyzer.analyze(
      samples: _tone(seconds: 1, amplitude: 1.0),
      sampleRate: _fs,
      calibrationOffsetDb: _offset,
      calibrated: false,
      peakWindowSeconds: 0.5,
    );
    expect(m.clipped, isTrue);
  });

  test('a 63 Hz rumble is weighted down by roughly the A-curve', () {
    final AcousticMetrics low = analyzer.analyze(
      samples: _tone(seconds: 2, amplitude: 0.1, frequency: 63),
      sampleRate: _fs,
      calibrationOffsetDb: _offset,
      calibrated: false,
      peakWindowSeconds: 1,
    );
    final AcousticMetrics mid = analyzer.analyze(
      samples: _tone(seconds: 2, amplitude: 0.1),
      sampleRate: _fs,
      calibrationOffsetDb: _offset,
      calibrated: false,
      peakWindowSeconds: 1,
    );

    expect(mid.laEqDb - low.laEqDb, closeTo(26.2, 1.0));
  });

  test('metrics survive a round trip through JSON', () {
    final AcousticMetrics m = analyzer.analyze(
      samples: _tone(seconds: 1, amplitude: 0.05),
      sampleRate: _fs,
      calibrationOffsetDb: _offset,
      calibrated: false,
      peakWindowSeconds: 0.5,
    );
    final AcousticMetrics back = AcousticMetrics.fromJson(m.toJson());

    expect(back.laEqDb, m.laEqDb);
    expect(back.laMaxDb, m.laMaxDb);
    expect(back.ambientLa90Db, m.ambientLa90Db);
    expect(back.peakWindowStartMs, m.peakWindowStartMs);
    expect(back.calibrated, m.calibrated);
    expect(back.sampleRate, m.sampleRate);
  });
}
