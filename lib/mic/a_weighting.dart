import 'dart:math' as math;

import 'package:noise_alert/mic/biquad.dart';

/// IEC 61672-1 A-weighting, built as a cascade of three biquads.
///
/// The analog prototype is
///
///   H(s) = K * s^4 / ((s+w1)^2 (s+w2) (s+w3) (s+w4)^2)
///
/// with the standard pole frequencies below. Each second-order factor is
/// bilinear-transformed independently, then the whole chain is normalised so
/// that the response at 1 kHz is exactly 0 dB. That final normalisation is what
/// makes the plain (un-prewarped) bilinear transform good enough: it removes
/// the systematic gain error, leaving only a small deviation near Nyquist.
///
/// Use a 48 kHz sample rate. At 16 kHz the 12.2 kHz pole pair sits so close to
/// Nyquist that the high-frequency end of the curve falls outside IEC class 2
/// tolerance, harmless for jet noise, but the filter would no longer be
/// honestly describable as "A-weighted".
class AWeighting {
  AWeighting(this.sampleRate) : _cascade = _design(sampleRate);

  static const double f1 = 20.598997;
  static const double f2 = 107.65265;
  static const double f3 = 737.86223;
  static const double f4 = 12194.217;

  /// Sample rate below which the design is no longer trustworthy.
  static const double minimumRecommendedSampleRate = 44100;

  final double sampleRate;
  final BiquadCascade _cascade;


  static BiquadCascade _design(double sampleRate) {
    final double w1 = 2 * math.pi * f1;
    final double w2 = 2 * math.pi * f2;
    final double w3 = 2 * math.pi * f3;
    final double w4 = 2 * math.pi * f4;

    // s^2 / (s + w1)^2
    final Biquad s1 = Biquad.bilinear(
      b2: 1,
      b1: 0,
      b0: 0,
      a2: 1,
      a1: 2 * w1,
      a0: w1 * w1,
      sampleRate: sampleRate,
    );

    // s^2 / ((s + w2)(s + w3))
    final Biquad s2 = Biquad.bilinear(
      b2: 1,
      b1: 0,
      b0: 0,
      a2: 1,
      a1: w2 + w3,
      a0: w2 * w3,
      sampleRate: sampleRate,
    );

    // 1 / (s + w4)^2
    final Biquad s3 = Biquad.bilinear(
      b2: 0,
      b1: 0,
      b0: 1,
      a2: 1,
      a1: 2 * w4,
      a0: w4 * w4,
      sampleRate: sampleRate,
    );

    final BiquadCascade raw = BiquadCascade(<Biquad>[s1, s2, s3]);
    final double gainAt1k = raw.magnitudeAt(1000, sampleRate);
    // Fold the 0 dB @ 1 kHz normalisation into the last section.
    return BiquadCascade(<Biquad>[s1, s2, s3.withGain(1.0 / gainAt1k)]);
  }

  void reset() => _cascade.reset();

  double process(double sample) => _cascade.process(sample);

  /// Weighting applied at [frequency], in dB (negative below/above 1 kHz).
  double responseDb(double frequency) =>
      20 * math.log(_cascade.magnitudeAt(frequency, sampleRate)) / math.ln10;

  /// Filters [input] in place-free fashion, returning a new list.
  ///
  /// Resets filter state first, so this is for one-shot offline analysis of a
  /// complete buffer rather than for streaming.
  List<double> filterBuffer(List<double> input) {
    reset();
    final List<double> out = List<double>.filled(input.length, 0);
    for (int i = 0; i < input.length; i++) {
      out[i] = _cascade.process(input[i]);
    }
    return out;
  }
}

/// Nominal A-weighting values from IEC 61672-1 Table 3, for tests and display.
///
/// A list of pairs rather than a map: Dart will not allow a `const` map keyed
/// by double, and the ordering matters when this is plotted.
const List<(double, double)> kAWeightingReferenceDb = <(double, double)>[
  (31.5, -39.4),
  (63, -26.2),
  (125, -16.1),
  (250, -8.6),
  (500, -3.2),
  (1000, 0.0),
  (2000, 1.2),
  (4000, 1.0),
  (8000, -1.1),
  (16000, -6.6),
];
