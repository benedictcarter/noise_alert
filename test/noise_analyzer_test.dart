import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noise_alert/mic/analyzer.dart';
import 'package:noise_alert/mic/metrics.dart';

const double _fs = 48000;
const double _offset = 120; // dB SPL at full scale; see LevelReference.

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
      peakWindowSeconds: 1,
    );

    expect(m.laEqDb, closeTo(_expectedDb(0.1), 0.2));
    expect(m.laMaxDb, closeTo(_expectedDb(0.1), 0.3));
    expect(m.clipped, isFalse);
  });

  test('the peak window lands on the loudest slice, not the first', () {
    // 6 s quiet, then 4 s loud, then 6 s quiet: the shape of an overflight.
    final Float64List samples = _concat(<Float64List>[
      _tone(seconds: 6, amplitude: 0.005),
      _tone(seconds: 4, amplitude: 0.2),
      _tone(seconds: 6, amplitude: 0.005),
    ]);

    final AcousticMetrics m = analyzer.analyze(
      samples: samples,
      sampleRate: _fs,
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
      'the background is the quiet part of the recording, not an average of '
      'it', () {
    // Half quiet street, half aircraft. A mean over the whole recording sits
    // 3 dB below the aircraft, because the aircraft is what dominates the
    // energy, so a mean would report a rise of ~3 dB for a flyover 40 dB
    // above the street. The L90 finds the street.
    final Float64List samples = _concat(<Float64List>[
      _tone(seconds: 10, amplitude: 0.002),
      _tone(seconds: 10, amplitude: 0.2),
    ]);

    final AcousticMetrics m = analyzer.analyze(
      samples: samples,
      sampleRate: _fs,
      peakWindowSeconds: 5,
    );

    expect(m.ambientLa90Db, closeTo(_expectedDb(0.002), 0.5));
    expect(m.excessOverAmbientDb, closeTo(40, 1.0));

    // And it is nowhere near the overall LAeq, which the aircraft owns.
    expect(m.laEqDb, greaterThan(m.ambientLa90Db! + 30));
  });

  test('no pre-roll is needed for a background any more', () {
    // The app records from the moment it opens, so nothing precedes the press.
    // The whole point of measuring the background from the recording itself is
    // that this case, which is now every case, still gets a comparison.
    final Float64List samples = _concat(<Float64List>[
      _tone(seconds: 8, amplitude: 0.002),
      _tone(seconds: 6, amplitude: 0.2),
      _tone(seconds: 8, amplitude: 0.002),
    ]);

    final AcousticMetrics m = analyzer.analyzeSource(
      samples: FloatSamples(samples),
      sampleRate: _fs,
      peakWindowSeconds: 5,
      preRollSeconds: 0,
    );

    expect(m.hasAmbient, isTrue);
    expect(m.ambientLa90Db, closeTo(_expectedDb(0.002), 0.5));
    expect(m.excessOverAmbientDb, closeTo(40, 1.0));
  });

  test('a dropout does not become the background', () {
    // Why L90 and not the true minimum. One 125 ms block of digital silence --
    // a buffer underrun, a moment the microphone was stolen by another app --
    // would otherwise set the floor 100 dB low and turn a 40 dB rise into a
    // preposterous one. Exactly the sort of figure that gets a complaint
    // thrown out.
    final Float64List quiet = _tone(seconds: 10, amplitude: 0.002);
    final Float64List glitch = Float64List((0.2 * _fs).round());
    final Float64List samples = _concat(<Float64List>[
      quiet,
      glitch,
      _tone(seconds: 6, amplitude: 0.2),
    ]);

    final AcousticMetrics m = analyzer.analyze(
      samples: samples,
      sampleRate: _fs,
      peakWindowSeconds: 5,
    );

    expect(m.ambientLa90Db, closeTo(_expectedDb(0.002), 0.5));
    expect(m.excessOverAmbientDb, closeTo(40, 1.0));
  });

  test('clipping is reported so the complaint can say "at least this loud"',
      () {
    final AcousticMetrics m = analyzer.analyze(
      samples: _tone(seconds: 1, amplitude: 1.0),
      sampleRate: _fs,
      peakWindowSeconds: 0.5,
    );
    expect(m.clipped, isTrue);
  });

  test('a 63 Hz rumble is weighted down by roughly the A-curve', () {
    final AcousticMetrics low = analyzer.analyze(
      samples: _tone(seconds: 2, amplitude: 0.1, frequency: 63),
      sampleRate: _fs,
      peakWindowSeconds: 1,
    );
    final AcousticMetrics mid = analyzer.analyze(
      samples: _tone(seconds: 2, amplitude: 0.1),
      sampleRate: _fs,
      peakWindowSeconds: 1,
    );

    expect(mid.laEqDb - low.laEqDb, closeTo(26.2, 1.0));
  });

  test('metrics survive a round trip through JSON', () {
    final AcousticMetrics m = analyzer.analyze(
      samples: _tone(seconds: 1, amplitude: 0.05),
      sampleRate: _fs,
      peakWindowSeconds: 0.5,
    );
    final AcousticMetrics back = AcousticMetrics.fromJson(m.toJson());

    expect(back.laEqDb, m.laEqDb);
    expect(back.laMaxDb, m.laMaxDb);
    expect(back.ambientLa90Db, m.ambientLa90Db);
    expect(back.peakWindowStartMs, m.peakWindowStartMs);
    expect(back.sampleRate, m.sampleRate);
  });

  test('a recording too short to hold a quiet moment quotes no background', () {
    // Under minAmbientSeconds the L90 would just be the aircraft, and the
    // letter would say the flyover was 0 dB above the background, which reads
    // as "this was not loud" when the truth is "this was not recorded for long
    // enough to say". The answer is "not measured".
    final AcousticMetrics m = analyzer.analyzeSource(
      samples: FloatSamples(_tone(seconds: 2, amplitude: 0.2)),
      sampleRate: _fs,
      peakWindowSeconds: 1,
      preRollSeconds: 0,
    );

    expect(m.ambientLa90Db, isNull);
    expect(m.hasAmbient, isFalse);
    expect(m.excessOverAmbientDb, isNull);
    // The event itself is still measured; only the comparison is withheld.
    expect(m.laMaxDb, closeTo(_expectedDb(0.2), 0.3));
  });

  test('a pre-roll rescues a recording that is too short for its own quiet',
      () {
    // The fallback the pre-roll now exists for, and the only case it is used
    // in: the user stopped almost immediately, so there is nothing quiet
    // inside the recording, but the microphone had been listening beforehand.
    final AcousticMetrics m = analyzer.analyzeSource(
      samples: FloatSamples(_tone(seconds: 2, amplitude: 0.2)),
      sampleRate: _fs,
      ambient: FloatSamples(_tone(seconds: 10, amplitude: 0.002)),
      peakWindowSeconds: 1,
      preRollSeconds: 0,
    );

    expect(m.hasAmbient, isTrue);
    expect(m.ambientLa90Db, closeTo(_expectedDb(0.002), 0.5));
  });

  test('exactly minAmbientSeconds of recording is enough to measure', () {
    // The boundary is inclusive, so a recording sitting exactly on it does not
    // flip behaviour on a rounding error in the sample count.
    final AcousticMetrics m = analyzer.analyzeSource(
      samples: FloatSamples(
        _tone(seconds: NoiseAnalyzer.minAmbientSeconds, amplitude: 0.002),
      ),
      sampleRate: _fs,
      peakWindowSeconds: 1,
      preRollSeconds: 0,
    );

    expect(m.ambientLa90Db, closeTo(_expectedDb(0.002), 0.5));
    expect(m.hasAmbient, isTrue);
  });

  test('a short pre-roll survives the JSON round trip as a null ambient', () {
    // Old records have no preRollSeconds key at all; new ones must not lose the
    // distinction between "quiet background" and "background never captured".
    const AcousticMetrics m = AcousticMetrics(
      laEqDb: 68.2,
      laMaxDb: 78.4,
      ambientLa90Db: null,
      preRollSeconds: 0,
      peakWindowLaEqDb: 71.9,
      peakWindowStartMs: 0,
      peakWindowDurationMs: 10000,
      eventDurationMs: 20000,
      clipped: false,
      sampleRate: _fs,
    );

    final AcousticMetrics back = AcousticMetrics.fromJson(m.toJson());

    expect(back.ambientLa90Db, isNull);
    expect(back.preRollSeconds, 0);
    expect(back.hasAmbient, isFalse);
  });

  group('an event that starts at the press', () {
    // The build that this group tests changed what a recording is: RECORD
    // starts the event, so the trace no longer carries a pre-roll and the
    // background has to arrive as a buffer of its own.
    test('the recording supplies its own background, pre-roll or not', () {
      // A recording long enough to contain a quiet moment uses that quiet
      // moment, and ignores the pre-roll entirely. The pre-roll here is a
      // decoy: it is a different level, so if it were being used the assertion
      // below would catch it.
      final Float64List decoy = _tone(seconds: 10, amplitude: 0.02);
      final Float64List recording = _concat(<Float64List>[
        _tone(seconds: 6, amplitude: 0.001),
        _tone(seconds: 8, amplitude: 0.2),
        _tone(seconds: 6, amplitude: 0.001),
      ]);

      final AcousticMetrics m = analyzer.analyzeSource(
        samples: FloatSamples(recording),
        sampleRate: _fs,
        ambient: FloatSamples(decoy),
        preRollSeconds: 0,
      );

      expect(m.ambientLa90Db, closeTo(_expectedDb(0.001), 1.5));
      expect(m.ambientSeconds, closeTo(20, 0.05));
      // Nothing precedes the press any more, so the marker sits at zero.
      expect(m.preRollSeconds, 0);
      expect(m.eventDurationMs, closeTo(20000, 30));
    });

    test('PCM16 samples measure the same as the floats they came from', () {
      // The event is held as Int16List so a five-minute recording fits in
      // memory. That is only safe if it measures identically.
      final Float64List floats = _tone(seconds: 5, amplitude: 0.3);
      final Int16List pcm = Int16List(floats.length);
      for (int i = 0; i < floats.length; i++) {
        pcm[i] = (floats[i] * 32767).round();
      }

      final AcousticMetrics fromFloats = analyzer.analyzeSource(
        samples: FloatSamples(floats),
        sampleRate: _fs,
        preRollSeconds: 0,
      );
      final AcousticMetrics fromPcm = analyzer.analyzeSource(
        samples: Pcm16Samples(pcm),
        sampleRate: _fs,
        preRollSeconds: 0,
      );

      expect(fromPcm.laEqDb, closeTo(fromFloats.laEqDb, 0.05));
      expect(fromPcm.laMaxDb, closeTo(fromFloats.laMaxDb, 0.05));
      expect(fromPcm.levelTrace.length, fromFloats.levelTrace.length);
    });

    test('a long recording is measured in one pass without a copy of itself',
        () {
      // Five minutes at 48 kHz. The old analyzer built three Float64 arrays
      // the length of the recording (about 345 MB) and would have died
      // here; this is the regression guard for that.
      final Int16List pcm = Int16List((300 * _fs).round());
      for (int i = 0; i < pcm.length; i++) {
        pcm[i] = (0.1 * 32767 * math.sin(2 * math.pi * 1000 * i / _fs)).round();
      }

      final AcousticMetrics m = analyzer.analyzeSource(
        samples: Pcm16Samples(pcm),
        sampleRate: _fs,
        preRollSeconds: 0,
      );

      expect(m.laEqDb, closeTo(_expectedDb(0.1), 0.5));
      expect(m.eventDurationMs, closeTo(300000, 50));
    });
  });

  test('the level trace follows the shape of the event', () {
    // 6 s quiet, 4 s loud, 6 s quiet: the trace is what the chart in the
    // letter is drawn from, so it has to show the rise where the rise was.
    final Float64List samples = _concat(<Float64List>[
      _tone(seconds: 6, amplitude: 0.002),
      _tone(seconds: 4, amplitude: 0.2),
      _tone(seconds: 6, amplitude: 0.002),
    ]);

    final AcousticMetrics m = analyzer.analyze(
      samples: samples,
      sampleRate: _fs,
      peakWindowSeconds: 1,
    );

    expect(m.hasTrace, isTrue);
    // 16 s at 250 ms a point.
    expect(m.levelTrace, hasLength(64));

    final int loudest = m.levelTrace.indexOf(
      m.levelTrace.reduce((double a, double b) => a > b ? a : b),
    );
    final double loudestAtSeconds = loudest * m.traceIntervalMs / 1000;
    expect(loudestAtSeconds, greaterThanOrEqualTo(6));
    expect(loudestAtSeconds, lessThan(10));

    // Quiet at both ends, loud in the middle, at roughly the right levels.
    expect(m.levelTrace.first, closeTo(_expectedDb(0.002), 1.5));
    expect(m.levelTrace.last, closeTo(_expectedDb(0.002), 1.5));
    expect(m.levelTrace[loudest], closeTo(_expectedDb(0.2), 1.0));
  });

  test('the trace survives the JSON round trip at one decimal place', () {
    final AcousticMetrics m = analyzer.analyze(
      samples: _tone(seconds: 4, amplitude: 0.1),
      sampleRate: _fs,
      peakWindowSeconds: 1,
    );
    final AcousticMetrics back = AcousticMetrics.fromJson(m.toJson());

    expect(back.levelTrace, hasLength(m.levelTrace.length));
    expect(back.traceIntervalMs, m.traceIntervalMs);
    for (int i = 0; i < m.levelTrace.length; i++) {
      // Rounded on the way out, so equal to within half of the last place.
      expect(back.levelTrace[i], closeTo(m.levelTrace[i], 0.05));
    }
  });

  test('a record written before the chart existed simply has no trace', () {
    // v1 rows carry no levelTrace key at all. An empty trace must read as
    // "no chart to draw", never as a flat line at zero decibels.
    final Map<String, Object?> legacy = <String, Object?>{
      'laEqDb': 68.2,
      'laMaxDb': 78.4,
      'ambientLa90Db': 38.1,
      'peakWindowLaEqDb': 71.9,
      'peakWindowStartMs': 0,
      'peakWindowDurationMs': 10000,
      'eventDurationMs': 50000,
      'clipped': 0,
      // Written by a build that still had a calibration setting. Deliberately
      // left in: the reader must walk past keys it no longer knows rather than
      // throw, or every event logged before this build becomes unopenable.
      'calibrated': 0,
      'calibrationOffsetDb': _offset,
      'sampleRate': _fs,
    };

    final AcousticMetrics m = AcousticMetrics.fromJson(legacy);

    expect(m.levelTrace, isEmpty);
    expect(m.hasTrace, isFalse);
    expect(m.laMaxDb, 78.4);
  });
}
