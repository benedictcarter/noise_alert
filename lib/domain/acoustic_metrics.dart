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
    required this.peakWindowLaEqDb,
    required this.peakWindowStartMs,
    required this.peakWindowDurationMs,
    required this.eventDurationMs,
    required this.clipped,
    required this.calibrated,
    required this.calibrationOffsetDb,
    required this.sampleRate,
  });

  factory AcousticMetrics.fromJson(Map<String, Object?> json) =>
      AcousticMetrics(
        laEqDb: (json['laEqDb'] as num).toDouble(),
        laMaxDb: (json['laMaxDb'] as num).toDouble(),
        ambientLa90Db: (json['ambientLa90Db'] as num).toDouble(),
        peakWindowLaEqDb: (json['peakWindowLaEqDb'] as num).toDouble(),
        peakWindowStartMs: json['peakWindowStartMs'] as int,
        peakWindowDurationMs: json['peakWindowDurationMs'] as int,
        eventDurationMs: json['eventDurationMs'] as int,
        clipped: (json['clipped'] as int) == 1,
        calibrated: (json['calibrated'] as int) == 1,
        calibrationOffsetDb: (json['calibrationOffsetDb'] as num).toDouble(),
        sampleRate: (json['sampleRate'] as num).toDouble(),
      );

  /// Equivalent continuous level over the whole analysed event window.
  final double laEqDb;

  /// Maximum level with IEC "fast" (125 ms) time weighting. This is the number
  /// airports and environmental health teams actually respond to.
  final double laMaxDb;

  /// Background level from the pre-roll: the level exceeded 90% of the time.
  final double ambientLa90Db;

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

  /// How far the event rose above the local background. Valid even when
  /// uncalibrated, because the offset cancels.
  double get excessOverAmbientDb => laMaxDb - ambientLa90Db;

  Map<String, Object?> toJson() => <String, Object?>{
        'laEqDb': laEqDb,
        'laMaxDb': laMaxDb,
        'ambientLa90Db': ambientLa90Db,
        'peakWindowLaEqDb': peakWindowLaEqDb,
        'peakWindowStartMs': peakWindowStartMs,
        'peakWindowDurationMs': peakWindowDurationMs,
        'eventDurationMs': eventDurationMs,
        'clipped': clipped ? 1 : 0,
        'calibrated': calibrated ? 1 : 0,
        'calibrationOffsetDb': calibrationOffsetDb,
        'sampleRate': sampleRate,
      };
}
