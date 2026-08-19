import 'dart:math' as math;
import 'dart:typed_data';

import '../../domain/acoustic_metrics.dart';
import 'a_weighting.dart';

/// Turns a buffer of raw PCM into the dB(A) figures that go in a complaint.
class NoiseAnalyzer {
  const NoiseAnalyzer({
    this.shortTermWindowMs = 125,
    this.fastTimeConstantSeconds = 0.125,
    this.clipThreshold = 0.995,
  });

  /// Block length used for the statistical (percentile) levels.
  final int shortTermWindowMs;

  /// IEC "fast" exponential time constant, used for LAmax.
  final double fastTimeConstantSeconds;

  /// |sample| at or above this (full scale = 1.0) counts as clipped.
  final double clipThreshold;

  /// [samples] must be normalised to -1.0..1.0 and unweighted.
  ///
  /// [ambientSampleCount] is how many samples at the *start* of the buffer are
  /// treated as pre-event background. Pass 0 to fall back to using the whole
  /// buffer for the ambient statistic.
  AcousticMetrics analyze({
    required Float64List samples,
    required double sampleRate,
    required double calibrationOffsetDb,
    required bool calibrated,
    int ambientSampleCount = 0,
    double peakWindowSeconds = 10,
  }) {
    if (samples.isEmpty) {
      throw ArgumentError('samples must not be empty');
    }

    final bool clipped = _detectClipping(samples);

    final AWeighting weighting = AWeighting(sampleRate);
    final Float64List weighted = Float64List(samples.length);
    for (int i = 0; i < samples.length; i++) {
      weighted[i] = weighting.process(samples[i]);
    }

    // Prefix sums of energy make every windowed LAeq an O(1) lookup.
    final Float64List energyPrefix = Float64List(weighted.length + 1);
    for (int i = 0; i < weighted.length; i++) {
      energyPrefix[i + 1] = energyPrefix[i] + weighted[i] * weighted[i];
    }

    double levelOf(int start, int end) {
      final int n = end - start;
      if (n <= 0) return double.negativeInfinity;
      final double meanSquare = (energyPrefix[end] - energyPrefix[start]) / n;
      return _toDb(meanSquare, calibrationOffsetDb);
    }

    final double laEq = levelOf(0, weighted.length);

    // --- LAmax, fast time weighting -------------------------------------
    final double alpha =
        1 - math.exp(-1 / (sampleRate * fastTimeConstantSeconds));
    double running = 0;
    double maxMeanSquare = 0;
    // Let the exponential average settle before trusting it, otherwise the
    // very first samples produce a spurious low reading rather than a high one.
    final int settleSamples = math.min(
        weighted.length, (sampleRate * fastTimeConstantSeconds * 3).round());
    for (int i = 0; i < weighted.length; i++) {
      final double sq = weighted[i] * weighted[i];
      running += alpha * (sq - running);
      if (i >= settleSamples && running > maxMeanSquare) {
        maxMeanSquare = running;
      }
    }
    final double laMax = _toDb(maxMeanSquare, calibrationOffsetDb);

    // --- ambient L90 from the pre-roll ----------------------------------
    final int ambientEnd = ambientSampleCount > 0
        ? math.min(ambientSampleCount, weighted.length)
        : weighted.length;
    final int blockSamples =
        math.max(1, (sampleRate * shortTermWindowMs / 1000).round());
    final List<double> shortTermLevels = <double>[];
    for (int start = 0;
        start + blockSamples <= ambientEnd;
        start += blockSamples) {
      shortTermLevels.add(levelOf(start, start + blockSamples));
    }
    final double ambientL90 = shortTermLevels.isEmpty
        ? levelOf(0, ambientEnd)
        : _percentile(shortTermLevels, 0.10);

    // --- loudest peakWindowSeconds slice --------------------------------
    final int windowSamples = math.min(
        weighted.length, math.max(1, (sampleRate * peakWindowSeconds).round()));
    int bestStart = 0;
    double bestEnergy = -1;
    final int hop = math.max(1, (sampleRate * 0.05).round()); // 50 ms hop
    for (int start = 0;
        start + windowSamples <= weighted.length;
        start += hop) {
      final double energy =
          energyPrefix[start + windowSamples] - energyPrefix[start];
      if (energy > bestEnergy) {
        bestEnergy = energy;
        bestStart = start;
      }
    }
    final double peakWindowLaEq = levelOf(bestStart, bestStart + windowSamples);

    return AcousticMetrics(
      laEqDb: laEq,
      laMaxDb: laMax,
      ambientLa90Db: ambientL90,
      peakWindowLaEqDb: peakWindowLaEq,
      peakWindowStartMs: (bestStart / sampleRate * 1000).round(),
      peakWindowDurationMs: (windowSamples / sampleRate * 1000).round(),
      eventDurationMs: (weighted.length / sampleRate * 1000).round(),
      clipped: clipped,
      calibrated: calibrated,
      calibrationOffsetDb: calibrationOffsetDb,
      sampleRate: sampleRate,
    );
  }

  bool _detectClipping(Float64List samples) {
    for (int i = 0; i < samples.length; i++) {
      if (samples[i].abs() >= clipThreshold) return true;
    }
    return false;
  }

  /// [fraction] 0.10 gives L90 (the level exceeded 90% of the time).
  static double _percentile(List<double> values, double fraction) {
    final List<double> sorted = List<double>.of(values)..sort();
    final int index =
        (fraction * (sorted.length - 1)).round().clamp(0, sorted.length - 1);
    return sorted[index];
  }

  static double _toDb(double meanSquare, double offsetDb) {
    if (meanSquare <= 0) return offsetDb - 200;
    return 10 * math.log(meanSquare) / math.ln10 + offsetDb;
  }
}

/// Converts interleaved little-endian PCM16 bytes to normalised doubles.
Float64List pcm16ToFloat(Uint8List bytes) {
  final int count = bytes.lengthInBytes ~/ 2;
  final ByteData view = ByteData.sublistView(bytes, 0, count * 2);
  final Float64List out = Float64List(count);
  for (int i = 0; i < count; i++) {
    out[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return out;
}
