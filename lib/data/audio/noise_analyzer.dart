import 'dart:math' as math;
import 'dart:typed_data';

import '../../core/constants.dart';
import '../../domain/acoustic_metrics.dart';
import 'a_weighting.dart';

/// Read-only view of normalised (-1..1) audio.
///
/// The analyser reads samples through this rather than taking a `Float64List`,
/// because a recording that runs until the user presses STOP can be minutes
/// long: at 48 kHz a five-minute event is 14.4 million samples, and holding
/// that as doubles costs 115 MB before any working arrays. Held as the PCM16 it
/// arrived as, the same event costs 29 MB.
abstract class SampleSource {
  int get length;
  double operator [](int index);
  SampleSource slice(int start, int end);
}

class FloatSamples implements SampleSource {
  const FloatSamples(this._data);

  final Float64List _data;

  @override
  int get length => _data.length;

  @override
  double operator [](int index) => _data[index];

  @override
  SampleSource slice(int start, int end) =>
      FloatSamples(Float64List.sublistView(_data, start, end));
}

class Pcm16Samples implements SampleSource {
  const Pcm16Samples(this._data);

  final Int16List _data;

  @override
  int get length => _data.length;

  @override
  double operator [](int index) => _data[index] / 32768.0;

  @override
  SampleSource slice(int start, int end) =>
      Pcm16Samples(Int16List.sublistView(_data, start, end));
}

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

  /// Below this much audio there is no meaningful background to quote.
  ///
  /// Ten blocks of 125 ms is the bare minimum for an L90 to mean anything. A
  /// recording shorter than this is all aircraft and no street, so its quiet
  /// floor would be the aircraft itself and the rise above it would be nearly
  /// zero -- a figure that reads as "this was not loud" when the truth is
  /// "this was not measured for long enough to say".
  static const double minAmbientSeconds = 3;

  /// Cadence of the level-over-time trace. 250 ms gives 200 points for a 50 s
  /// event: enough to show the rise and fall of a flyover, few enough to store
  /// in the row and draw without decimation.
  static const int defaultTraceIntervalMs = 250;

  /// Granularity everything windowed is built from.
  ///
  /// The energy of each 25 ms block is summed in a single streaming pass and
  /// only those sums are kept, so the memory cost of the analysis is 1/1200 of
  /// the recording rather than three times it. 25 divides the 125 ms
  /// statistical window, the 250 ms trace and the 50 ms peak-search hop
  /// exactly, so nothing downstream loses resolution by going through it.
  static const int analysisBlockMs = 25;

  /// [samples] must be normalised to -1.0..1.0 and unweighted.
  ///
  /// The background is measured from [samples] itself -- see [analyzeSource].
  /// [ambient] is only a fallback for a recording too short to contain a quiet
  /// moment of its own.
  AcousticMetrics analyze({
    required Float64List samples,
    required double sampleRate,
    int ambientSampleCount = 0,
    SampleSource? ambient,
    int traceIntervalMs = defaultTraceIntervalMs,
    double peakWindowSeconds = 10,
    double? preRollSeconds,
  }) =>
      analyzeSource(
        samples: FloatSamples(samples),
        sampleRate: sampleRate,
        ambientSampleCount: ambientSampleCount,
        ambient: ambient,
        traceIntervalMs: traceIntervalMs,
        peakWindowSeconds: peakWindowSeconds,
        preRollSeconds: preRollSeconds,
      );

  /// As [analyze], but reading the event from any [SampleSource].
  ///
  /// The background comes from the recording itself: the level exceeded 90% of
  /// the time across the whole of it. The app starts recording the moment it
  /// opens and stops when the user says so, so the recording routinely holds
  /// the street before and after the aircraft as well as the aircraft, and the
  /// quiet parts of it are the fairest available statement of what the street
  /// sounds like without a jet over it. Measuring the background from a
  /// separate pre-roll, as this used to, means no background at all whenever
  /// the recording began at the press -- which is now every recording.
  ///
  /// [ambient] and [ambientSampleCount] survive as a fallback for a recording
  /// shorter than [minAmbientSeconds], where there is no quiet moment inside
  /// the recording to find.
  AcousticMetrics analyzeSource({
    required SampleSource samples,
    required double sampleRate,
    int ambientSampleCount = 0,
    SampleSource? ambient,
    int traceIntervalMs = defaultTraceIntervalMs,
    double peakWindowSeconds = 10,
    double? preRollSeconds,
  }) {
    final int n = samples.length;
    if (n == 0) {
      throw ArgumentError('samples must not be empty');
    }

    final int blockSamples =
        math.max(1, (sampleRate * analysisBlockMs / 1000).round());
    final int blocks = n ~/ blockSamples;
    final Float64List blockEnergy = Float64List(blocks);

    // --- the single streaming pass ---------------------------------------
    // Everything that needs every sample is computed here: clipping, the
    // overall energy, the fast-weighted maximum, and the per-block energies
    // that every windowed figure below is derived from. Nothing of the
    // recording's own length is retained.
    final AWeighting weighting = AWeighting(sampleRate);
    final double alpha =
        1 - math.exp(-1 / (sampleRate * fastTimeConstantSeconds));
    // Let the exponential average settle before trusting it, otherwise the
    // very first samples produce a spurious low reading rather than a high one.
    final int settleSamples =
        math.min(n, (sampleRate * fastTimeConstantSeconds * 3).round());

    bool clipped = false;
    double totalEnergy = 0;
    double running = 0;
    double maxMeanSquare = 0;
    double acc = 0;
    int inBlock = 0;
    int block = 0;

    for (int i = 0; i < n; i++) {
      final double raw = samples[i];
      if (raw.abs() >= clipThreshold) clipped = true;
      final double y = weighting.process(raw);
      final double sq = y * y;
      totalEnergy += sq;
      running += alpha * (sq - running);
      if (i >= settleSamples && running > maxMeanSquare) {
        maxMeanSquare = running;
      }
      if (block < blocks) {
        acc += sq;
        if (++inBlock == blockSamples) {
          blockEnergy[block++] = acc;
          acc = 0;
          inBlock = 0;
        }
      }
    }

    final double laEq = _toDb(totalEnergy / n);
    final double laMax = _toDb(maxMeanSquare);

    // Prefix sums over the block energies make every windowed LAeq an O(1)
    // lookup, at 1/blockSamples of the memory the per-sample version needed.
    final Float64List prefix = Float64List(blocks + 1);
    for (int i = 0; i < blocks; i++) {
      prefix[i + 1] = prefix[i] + blockEnergy[i];
    }

    double levelOfBlocks(int from, int to) {
      final int count = to - from;
      if (count <= 0) return double.negativeInfinity;
      return _toDb((prefix[to] - prefix[from]) / (count * blockSamples));
    }

    // --- the background: how quiet it got ---------------------------------
    // Taken from the recording itself. The L90 of a two-minute recording that
    // contains a forty-second flyover is the street either side of it, which
    // is exactly the comparison the complaint wants to make. Only when the
    // recording is too short for that -- the user stopped almost immediately
    // -- does the separately captured pre-roll get a look in.
    final int minAmbientSamples = (sampleRate * minAmbientSeconds).round();
    final SampleSource? fallback = ambient ??
        (ambientSampleCount > 0
            ? samples.slice(0, math.min(ambientSampleCount, n))
            : null);

    SampleSource? backgroundSource;
    if (n >= minAmbientSamples) {
      backgroundSource = samples;
    } else if (fallback != null && fallback.length >= minAmbientSamples) {
      backgroundSource = fallback;
    }

    final int ambientLength = backgroundSource?.length ?? 0;
    final double? ambientL90 = backgroundSource == null
        ? null
        : _l90(backgroundSource, sampleRate: sampleRate);

    // --- loudest peakWindowSeconds slice ----------------------------------
    final int windowBlocks = blocks == 0
        ? 0
        : math.min(
            blocks,
            math.max(1, (peakWindowSeconds * 1000 / analysisBlockMs).round()),
          );
    final int hop = math.max(1, (50 / analysisBlockMs).round());
    int bestStart = 0;
    double bestEnergy = -1;
    for (int start = 0; start + windowBlocks <= blocks; start += hop) {
      final double energy = prefix[start + windowBlocks] - prefix[start];
      if (energy > bestEnergy) {
        bestEnergy = energy;
        bestStart = start;
      }
    }
    final double peakWindowLaEq = windowBlocks == 0
        ? laEq
        : levelOfBlocks(bestStart, bestStart + windowBlocks);
    final int peakWindowSamples =
        windowBlocks == 0 ? n : windowBlocks * blockSamples;

    // --- level over time, for the chart in the letter ---------------------
    final int traceBlocks =
        math.max(1, (traceIntervalMs / analysisBlockMs).round());
    final List<double> trace = <double>[];
    for (int start = 0; start + traceBlocks <= blocks; start += traceBlocks) {
      trace.add(levelOfBlocks(start, start + traceBlocks));
    }

    return AcousticMetrics(
      laEqDb: laEq,
      laMaxDb: laMax,
      ambientLa90Db: ambientL90,
      // Where the press sits inside the trace. Zero whenever the recording was
      // started by the press, which is every event this build captures.
      preRollSeconds: preRollSeconds ??
          (ambient != null ? 0 : ambientSampleCount / sampleRate),
      ambientSeconds: ambientLength / sampleRate,
      peakWindowLaEqDb: peakWindowLaEq,
      peakWindowStartMs: (bestStart * blockSamples / sampleRate * 1000).round(),
      peakWindowDurationMs: (peakWindowSamples / sampleRate * 1000).round(),
      eventDurationMs: (n / sampleRate * 1000).round(),
      clipped: clipped,
      levelTrace: trace,
      traceIntervalMs: traceIntervalMs,
      sampleRate: sampleRate,
    );
  }

  /// The level exceeded 90% of the time, over its own A-weighting pass.
  ///
  /// A second pass rather than a reuse of the 25 ms block energies above,
  /// because a percentile needs the 125 ms statistical window the standard is
  /// written in, and because the fallback source is a different buffer
  /// entirely.
  double _l90(SampleSource source, {required double sampleRate}) {
    final int blockSamples =
        math.max(1, (sampleRate * shortTermWindowMs / 1000).round());
    final AWeighting weighting = AWeighting(sampleRate);
    final List<double> levels = <double>[];
    final int n = source.length;

    double acc = 0;
    double total = 0;
    int inBlock = 0;
    for (int i = 0; i < n; i++) {
      final double y = weighting.process(source[i]);
      final double sq = y * y;
      total += sq;
      acc += sq;
      if (++inBlock == blockSamples) {
        levels.add(_toDb(acc / blockSamples));
        acc = 0;
        inBlock = 0;
      }
    }

    if (levels.isEmpty) return _toDb(total / n);
    return _percentile(levels, 0.10);
  }

  /// [fraction] 0.10 gives L90 (the level exceeded 90% of the time).
  ///
  /// Not 0.0. The true minimum is a single 125 ms block, and one dropout,
  /// buffer underrun or momentary gap in the traffic puts it twenty decibels
  /// below anything real -- which would then be subtracted from the peak and
  /// reported as the rise. The tenth percentile is what "the quietest it got"
  /// actually means once you have to defend the number.
  static double _percentile(List<double> values, double fraction) {
    final List<double> sorted = List<double>.of(values)..sort();
    final int index =
        (fraction * (sorted.length - 1)).round().clamp(0, sorted.length - 1);
    return sorted[index];
  }

  static double _toDb(double meanSquare) {
    if (meanSquare <= 0) return LevelReference.fullScaleDbSpl - 200;
    return 10 * math.log(meanSquare) / math.ln10 +
        LevelReference.fullScaleDbSpl;
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

/// Normalised doubles for `[start, end)` of an Int16 recording.
///
/// Used to hand the WAV writer only the slice it is about to save, rather than
/// converting a whole multi-minute recording to doubles for the sake of ten
/// seconds of it.
Float64List pcm16SliceToFloat(Int16List samples, int start, int end) {
  final Float64List out = Float64List(end - start);
  for (int i = 0; i < out.length; i++) {
    out[i] = samples[start + i] / 32768.0;
  }
  return out;
}
