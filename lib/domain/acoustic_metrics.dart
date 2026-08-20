/// Sound level figures for one noise event.
///
/// Everything is A-weighted and expressed in dB(A), against the fixed
/// full-scale reference in [LevelReference]. The figure the complaint turns on
/// is [excessOverAmbientDb]: how far the loudest moment rose above the
/// quietest. That comparison is between two readings from the same microphone
/// in the same minute, so whatever the handset's absolute error is, it appears
/// in both and cancels.
class AcousticMetrics {
  const AcousticMetrics({
    required this.laEqDb,
    required this.laMaxDb,
    required this.ambientLa90Db,
    required this.preRollSeconds,
    this.ambientSeconds = 0,
    required this.peakWindowLaEqDb,
    required this.peakWindowStartMs,
    required this.peakWindowDurationMs,
    required this.eventDurationMs,
    required this.clipped,
    required this.sampleRate,
    this.levelTrace = const <double>[],
    this.traceIntervalMs = 250,
    this.note = '',
  });

  /// A recording that produced no usable sound measurement.
  ///
  /// The microphone can be busy, muted by another app, or simply deliver
  /// nothing at all, and none of that is a reason to lose the complaint. A
  /// letter that says only "an aircraft was audible at this address at this
  /// time" is still a complaint; the sound level is evidence that strengthens
  /// it, not the thing that entitles the user to make it.
  const AcousticMetrics.unmeasured({this.note = ''})
      : laEqDb = 0,
        laMaxDb = 0,
        ambientLa90Db = null,
        preRollSeconds = 0,
        ambientSeconds = 0,
        peakWindowLaEqDb = 0,
        peakWindowStartMs = 0,
        peakWindowDurationMs = 0,
        eventDurationMs = 0,
        clipped = false,
        sampleRate = 0,
        levelTrace = const <double>[],
        traceIntervalMs = 250;

  factory AcousticMetrics.fromJson(Map<String, Object?> json) =>
      AcousticMetrics(
        note: json['note'] as String? ?? '',
        laEqDb: (json['laEqDb'] as num).toDouble(),
        laMaxDb: (json['laMaxDb'] as num).toDouble(),
        ambientLa90Db: (json['ambientLa90Db'] as num?)?.toDouble(),
        // Absent in v1 records, which always had the full pre-roll by
        // construction: there was no way to snap without one.
        preRollSeconds: (json['preRollSeconds'] as num?)?.toDouble() ?? 30,
        // Records written before the recording started at the press had the
        // background inside the trace, so the two figures were the same thing.
        ambientSeconds: (json['ambientSeconds'] as num?)?.toDouble() ??
            (json['preRollSeconds'] as num?)?.toDouble() ??
            30,
        peakWindowLaEqDb: (json['peakWindowLaEqDb'] as num).toDouble(),
        peakWindowStartMs: json['peakWindowStartMs'] as int,
        peakWindowDurationMs: json['peakWindowDurationMs'] as int,
        eventDurationMs: json['eventDurationMs'] as int,
        clipped: (json['clipped'] as int) == 1,
        // 'calibrated' and 'calibrationOffsetDb' appear in records written
        // before the calibration setting was removed. They are read past
        // deliberately: the scale is fixed now, and an old row's stored offset
        // would only reintroduce a distinction the app no longer makes.
        sampleRate: (json['sampleRate'] as num).toDouble(),
        // Absent in records written before the chart existed. An empty trace
        // means "no chart", not "a flat line at zero".
        levelTrace: <double>[
          for (final Object? v in (json['levelTrace'] as List<Object?>?) ??
              const <Object?>[])
            (v as num).toDouble(),
        ],
        traceIntervalMs: (json['traceIntervalMs'] as num?)?.toInt() ?? 250,
      );

  /// Equivalent continuous level over the whole analysed event window.
  final double laEqDb;

  /// Maximum level with IEC "fast" (125 ms) time weighting. This is the number
  /// airports and environmental health teams actually respond to.
  final double laMaxDb;

  /// The background: how quiet it got, taken across the whole recording.
  ///
  /// Not a mean — a mean is dragged upwards by the aircraft, which is the very
  /// thing being measured against. This is the level exceeded 90% of the time
  /// (L90), which is the standard way of writing down "the quiet floor" and is
  /// what the absolute minimum is trying to be. The true minimum is not used
  /// because it is one 125 ms block: a single dropout, buffer glitch or gap
  /// between traffic sets the floor twenty decibels too low and every event
  /// then looks preposterously excessive.
  ///
  /// Null only when the recording was too short for a quiet moment to exist in
  /// it (see `NoiseAnalyzer.minAmbientSeconds`).
  final double? ambientLa90Db;

  /// Seconds of [levelTrace] that precede the button press.
  ///
  /// Zero for anything captured by this build: pressing RECORD starts the
  /// recording, so the trace begins at the press. Non-zero only for records
  /// from the builds that captured a rolling pre-roll into the same window,
  /// where the chart has to mark where the press fell.
  final double preRollSeconds;

  /// Seconds of background recorded *before* the press, from which
  /// [ambientLa90Db] was measured. Not part of [levelTrace].
  final double ambientSeconds;

  bool get hasAmbient => ambientLa90Db != null;

  /// LAeq of the loudest [peakWindowDurationMs] slice — the slice the attached
  /// audio clip covers.
  final double peakWindowLaEqDb;

  /// Offset of the loudest slice from the start of the analysed window.
  final int peakWindowStartMs;
  final int peakWindowDurationMs;
  final int eventDurationMs;

  /// True if raw samples hit the converter rails: the real level was higher
  /// than reported and the figure is a lower bound only.
  final bool clipped;

  final double sampleRate;

  /// Short-term A-weighted level, one value every [traceIntervalMs], covering
  /// the whole analysed window from the start of the pre-roll.
  ///
  /// This is what the chart in the letter is drawn from. It is stored rather
  /// than recomputed because the audio itself is usually discarded: the clip is
  /// optional and only ten seconds long, so by the time a complaint is resent
  /// or reviewed the samples are gone. Roughly 200 numbers for a 50 s event —
  /// cheaper than keeping the audio and enough to show the shape of a flyover.
  final List<double> levelTrace;

  final int traceIntervalMs;

  /// Why there is no measurement, when there is none. Empty otherwise.
  final String note;

  bool get hasTrace => levelTrace.length >= 2;

  /// False when the microphone gave us nothing usable.
  ///
  /// Everything that prints a decibel figure has to ask this first. A zero here
  /// is the absence of a measurement, and printing it as "0.0 dB(A)" would be
  /// a claim about the world rather than a gap in the evidence.
  bool get hasMeasurement => sampleRate > 0 && eventDurationMs > 0;

  /// How far the loudest moment rose above the quietest — the figure the
  /// complaint leads on.
  ///
  /// Both readings come from the same microphone in the same minute, so the
  /// handset's absolute error is in both and cancels: this number is right
  /// even where the dB(A) figures either side of it are a few decibels out.
  /// Null when the recording was too short to contain a quiet moment.
  double? get excessOverAmbientDb {
    final double? ambient = ambientLa90Db;
    return ambient == null ? null : laMaxDb - ambient;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'laEqDb': laEqDb,
        'laMaxDb': laMaxDb,
        'ambientLa90Db': ambientLa90Db,
        'preRollSeconds': preRollSeconds,
        'ambientSeconds': ambientSeconds,
        'peakWindowLaEqDb': peakWindowLaEqDb,
        'peakWindowStartMs': peakWindowStartMs,
        'peakWindowDurationMs': peakWindowDurationMs,
        'eventDurationMs': eventDurationMs,
        'clipped': clipped ? 1 : 0,
        'sampleRate': sampleRate,
        // One decimal place: the chart is a few hundred pixels wide and a
        // phone microphone is not good to better than a decibel anyway, so
        // full float precision would triple the row size for nothing.
        'levelTrace': <double>[
          for (final double v in levelTrace)
            double.parse(v.toStringAsFixed(1)),
        ],
        'traceIntervalMs': traceIntervalMs,
        if (note.isNotEmpty) 'note': note,
      };
}
