import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noise_alert/core/constants.dart';
import 'package:noise_alert/data/audio/a_weighting.dart';

void main() {
  group('A-weighting frequency response', () {
    test('matches IEC 61672-1 Table 3 at 48 kHz', () {
      final AWeighting weighting =
          AWeighting(AudioConfig.sampleRate.toDouble());

      for (final (double frequency, double expected)
          in kAWeightingReferenceDb) {
        final double actual = weighting.responseDb(frequency);

        if (frequency >= 16000) {
          // The bilinear transform warps frequency towards Nyquist, so at
          // fs/3 the digital filter over-attenuates — about 6 dB low here.
          // IEC 61672-1 leaves the lower tolerance at 16 kHz effectively
          // unbounded for both classes, and aircraft noise has nothing up
          // there anyway, so over-attenuation is acceptable; being *above*
          // nominal would not be.
          expect(actual, lessThan(expected + 0.5), reason: 'at $frequency Hz');
          expect(actual, greaterThan(-20), reason: 'at $frequency Hz');
          continue;
        }

        final double tolerance = frequency <= 4000 ? 0.6 : 1.0;
        expect(
          actual,
          closeTo(expected, tolerance),
          reason: 'at $frequency Hz',
        );
      }
    });

    test('is unity gain at 1 kHz by definition', () {
      final AWeighting weighting =
          AWeighting(AudioConfig.sampleRate.toDouble());
      expect(weighting.responseDb(1000), closeTo(0, 0.05));
    });

    test('16 kHz sampling is refused as too low for the 12.2 kHz pole pair',
        () {
      // The filter is still constructable at 16 kHz, but the top section
      // collapses against Nyquist and the response is no longer A-weighting.
      // This is why AudioConfig.sampleRate is 48 kHz and not the more common
      // 16 kHz voice rate.
      expect(AWeighting.minimumRecommendedSampleRate, greaterThan(16000));
      expect(
        AudioConfig.sampleRate,
        greaterThanOrEqualTo(AWeighting.minimumRecommendedSampleRate),
      );
    });

    test('a filtered 1 kHz tone keeps its amplitude', () {
      const double fs = 48000;
      final AWeighting weighting = AWeighting(fs);
      final Float64List tone = Float64List(4800);
      for (int i = 0; i < tone.length; i++) {
        tone[i] = math.sin(2 * math.pi * 1000 * i / fs);
      }

      final List<double> out = weighting.filterBuffer(tone);

      // Skip the filter's settling transient.
      double peak = 0;
      for (int i = 480; i < out.length; i++) {
        peak = math.max(peak, out[i].abs());
      }
      expect(peak, closeTo(1.0, 0.02));
    });

    test('rejects low frequencies hard, as the weighting demands', () {
      final AWeighting weighting = AWeighting(48000);
      expect(weighting.responseDb(20), lessThan(-45));
      expect(weighting.responseDb(50), lessThan(-28));
    });
  });
}
