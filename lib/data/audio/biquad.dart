import 'dart:math' as math;

/// A single direct-form-I biquad section.
///
/// Coefficients are already normalised so that `a0 == 1`.
class Biquad {
  Biquad({
    required this.b0,
    required this.b1,
    required this.b2,
    required this.a1,
    required this.a2,
  });

  /// Builds a digital biquad from an analog section
  ///
  ///   H(s) = (b2*s^2 + b1*s + b0) / (a2*s^2 + a1*s + a0)
  ///
  /// using the bilinear transform at [sampleRate] (no frequency pre-warping;
  /// the cascade is gain-normalised at 1 kHz afterwards instead, which is what
  /// actually matters for a weighting filter).
  factory Biquad.bilinear({
    required double b2,
    required double b1,
    required double b0,
    required double a2,
    required double a1,
    required double a0,
    required double sampleRate,
  }) {
    final double c = 2.0 * sampleRate;
    final double cc = c * c;

    final double nb0 = b2 * cc + b1 * c + b0;
    final double nb1 = 2.0 * b0 - 2.0 * b2 * cc;
    final double nb2 = b2 * cc - b1 * c + b0;

    final double na0 = a2 * cc + a1 * c + a0;
    final double na1 = 2.0 * a0 - 2.0 * a2 * cc;
    final double na2 = a2 * cc - a1 * c + a0;

    return Biquad(
      b0: nb0 / na0,
      b1: nb1 / na0,
      b2: nb2 / na0,
      a1: na1 / na0,
      a2: na2 / na0,
    );
  }

  final double b0;
  final double b1;
  final double b2;
  final double a1;
  final double a2;

  double _x1 = 0;
  double _x2 = 0;
  double _y1 = 0;
  double _y2 = 0;

  void reset() {
    _x1 = _x2 = _y1 = _y2 = 0;
  }

  double process(double x) {
    final double y = b0 * x + b1 * _x1 + b2 * _x2 - a1 * _y1 - a2 * _y2;
    _x2 = _x1;
    _x1 = x;
    _y2 = _y1;
    _y1 = y;
    return y;
  }

  /// Linear magnitude response at [frequency] Hz for a given [sampleRate].
  double magnitudeAt(double frequency, double sampleRate) {
    final double w = 2 * math.pi * frequency / sampleRate;
    final double cw = math.cos(w);
    final double sw = math.sin(w);
    final double c2w = math.cos(2 * w);
    final double s2w = math.sin(2 * w);

    final double numRe = b0 + b1 * cw + b2 * c2w;
    final double numIm = -(b1 * sw + b2 * s2w);
    final double denRe = 1 + a1 * cw + a2 * c2w;
    final double denIm = -(a1 * sw + a2 * s2w);

    final double num = math.sqrt(numRe * numRe + numIm * numIm);
    final double den = math.sqrt(denRe * denRe + denIm * denIm);
    return num / den;
  }

  /// Scales this section's numerator by [gain].
  Biquad withGain(double gain) => Biquad(
        b0: b0 * gain,
        b1: b1 * gain,
        b2: b2 * gain,
        a1: a1,
        a2: a2,
      );
}

/// An ordered chain of [Biquad] sections.
class BiquadCascade {
  BiquadCascade(this.sections);

  final List<Biquad> sections;

  void reset() {
    for (final Biquad s in sections) {
      s.reset();
    }
  }

  double process(double x) {
    double y = x;
    for (final Biquad s in sections) {
      y = s.process(y);
    }
    return y;
  }

  double magnitudeAt(double frequency, double sampleRate) {
    double m = 1;
    for (final Biquad s in sections) {
      m *= s.magnitudeAt(frequency, sampleRate);
    }
    return m;
  }
}

/// RBJ cookbook low-pass, used for anti-alias filtering before decimation.
Biquad lowPassBiquad({
  required double cutoffHz,
  required double sampleRate,
  double q = 0.7071067811865476,
}) {
  final double w0 = 2 * math.pi * cutoffHz / sampleRate;
  final double cosW0 = math.cos(w0);
  final double alpha = math.sin(w0) / (2 * q);

  final double b0 = (1 - cosW0) / 2;
  final double b1 = 1 - cosW0;
  final double b2 = (1 - cosW0) / 2;
  final double a0 = 1 + alpha;
  final double a1 = -2 * cosW0;
  final double a2 = 1 - alpha;

  return Biquad(
    b0: b0 / a0,
    b1: b1 / a0,
    b2: b2 / a0,
    a1: a1 / a0,
    a2: a2 / a0,
  );
}
