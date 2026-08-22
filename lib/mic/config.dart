/// Tunable constants for recording and measuring sound. Gathered here so the
/// acoustics can be adjusted without hunting through the code.
class AudioConfig {
  /// 48 kHz, not 16 kHz. A-weighting has a pole pair at 12.2 kHz; at a 16 kHz
  /// sample rate the bilinear transform squashes it against Nyquist and the
  /// filter stops meeting IEC class 2 tolerance.
  static const int sampleRate = 48000;

  /// Seconds of audio held live while the snap screen is open.
  static const double ringBufferSeconds = 60;

  /// Recorded before the button press, and now only a fallback.
  ///
  /// The background is taken from the recording itself (its quietest tenth)
  /// because a recording that runs from before the aircraft until after it has
  /// gone contains its own quiet street. The look-back survives for the one
  /// case that does not: a recording stopped within
  /// [NoiseAnalyzer.minAmbientSeconds], which is all aircraft and no street.
  static const double preRollSeconds = 30;

  /// Leading slice of the pre-roll used as that fallback background.
  static const double ambientWindowSeconds = 10;

  /// Hard stop on a single recording.
  ///
  /// The user ends the recording, not a timer, but an app left recording in a
  /// pocket must not grow without limit. Five minutes is far longer than any
  /// overflight and costs about 29 MB of PCM16 at 48 kHz, which the analyser
  /// then reads in place rather than converting.
  static const double maxEventSeconds = 300;

  /// Length of the attachable clip, taken from the loudest part of the event.
  static const double clipSeconds = 10;

  /// Sample rate the saved clip is decimated to.
  static const int clipSampleRate = 16000;

  /// Live meter update interval.
  static const int meterIntervalMs = 100;
}

class LevelReference {
  /// dB SPL corresponding to a full-scale (rms = 1.0) signal.
  ///
  /// Phone MEMS microphones have an acoustic overload point around 120-125 dB
  /// SPL and digital full scale is set near it, so 120 is the least wrong
  /// figure to hang the scale on. It is fixed, and there is no user-facing
  /// calibration: asking someone to borrow a reference sound level meter
  /// before they may complain about a jet is a way of ensuring nobody
  /// complains.
  ///
  /// It also does not much matter. The number the complaint turns on is the
  /// gap between the loudest moment and the quietest, and this offset appears
  /// in both, so it cancels in the subtraction. A handset several decibels out
  /// still reports the right *rise*.
  static const double fullScaleDbSpl = 120.0;
}
