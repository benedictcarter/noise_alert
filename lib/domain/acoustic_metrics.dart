/// Sound level figures for one noise event.
///
/// Everything is A-weighted and expressed in dB(A). Whether those numbers mean
/// anything in absolute terms depends on [calibrated] — see
/// `CalibrationSettings`. An uncalibrated reading is still perfectly useful as
/// a *relative* figure (how far above the ambient background the aircraft was),
/// which is why [ambientLa90Db] and [excessOverAmbientDb] exist.
class AcousticMetrics {
  const AcousticMetrics({
    required this.laEqDb,
    required this.laMaxDb,
    required this.ambientLa90Db,
    required this.preRollSeconds,
    required this.peakWindowLaEqDb,
    required this.peakWindowStartMs,
    required this.peakWindowDurationMs,
    required this.eventDurationMs,
    required this.clipped,
    required this.calibrated,
    required this.calibrationOffsetDb,
    required this.sampleRate,
    this.levelTrace = const <double>[],
    this.traceIntervalMs = 250,
  });

  factory AcousticMetrics.fromJson(Map<String, Object?> json) =>
      AcousticMetrics(
        laEqDb: (json['laEqDb'] as num).toDouble(),
        laMaxDb: (json['laMaxDb'] as num).toDouble(),
        ambientLa90Db: (json['ambientLa90Db'] as num?)?.toDouble(),
        // Absent in v1 records, which always had the full pre-roll by
        // construction: there was no way to snap without one.
        preRollSeconds: (json['preRollSeconds'] as num?)?.toDouble() ?? 30,
        peakWindowLaEqDb: (json['peakWindowLaEqDb'] as num).toDouble(),
        peakWindowStartMs: json['peakWindowStartMs'] as int,
        peakWindowDurationMs: json['peakWindowDurationMs'] as int,
        eventDurationMs: json['eventDurationMs'] as int,
        clipped: (json['clipped'] as int) == 1,
        calibrated: (json['calibrated'] as int) == 1,
        calibrationOffsetDb: (json['calibrationOffsetDb'] as num).toDouble(),
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

  /// Background level from the pre-roll: the level exceeded 90% of the time.
  ///
  /// Null when there was too little pre-roll to measure a background at all —
  /// a snap fired seconds after the microphone opened has nothing to compare
  /// the event against. Reporting a number derived from un-recorded silence
  /// would make every such event look far more excessive than it was.
  final double? ambientLa90Db;

  /// Seconds of audio in the analysed window that precede the button press.
  /// Quoted in the letter so the recipient can see the event was captured
  /// whole rather than caught halfway through.
  final double preRollSeconds;

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

  final bool calibrated;
  final double calibrationOffsetDb;
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

  bool get hasTrace => levelTrace.length >= 2;

  /// How far the event rose above the local background. Valid even when
  /// uncalibrated, because the offset cancels — which is why it is the figure
  /// the complaint leads on. Null when no background could be measured.
  double? get excessOverAmbientDb {
    final double? ambient = ambientLa90Db;
    return ambient == null ? null : laMaxDb - ambient;
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'laEqDb': laEqDb,
        'laMaxDb': laMaxDb,
        'ambientLa90Db': ambientLa90Db,
        'preRollSeconds': preRollSeconds,
        'peakWindowLaEqDb': peakWindowLaEqDb,
        'peakWindowStartMs': peakWindowStartMs,
        'peakWindowDurationMs': peakWindowDurationMs,
        'eventDurationMs': eventDurationMs,
        'clipped': clipped ? 1 : 0,
        'calibrated': calibrated ? 1 : 0,
        'calibrationOffsetDb': calibrationOffsetDb,
        'sampleRate': sampleRate,
        // One decimal place: the chart is a few hundred pixels wide and the
        // measurement is not calibrated to better than a decibel anyway, so
        // full float precision would triple the row size for nothing.
        'levelTrace': <double>[
          for (final double v in levelTrace)
            double.parse(v.toStringAsFixed(1)),
        ],
        'traceIntervalMs': traceIntervalMs,
      };
}
