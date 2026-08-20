/// Tunable constants, gathered so the acoustics and matching can be adjusted
/// without hunting through the code.
class AudioConfig {
  /// 48 kHz, not 16 kHz. A-weighting has a pole pair at 12.2 kHz; at a 16 kHz
  /// sample rate the bilinear transform squashes it against Nyquist and the
  /// filter stops meeting IEC class 2 tolerance.
  static const int sampleRate = 48000;

  /// Seconds of audio held live while the snap screen is open.
  static const double ringBufferSeconds = 60;

  /// Recorded before the button press, and used *only* to establish what the
  /// street sounded like beforehand.
  ///
  /// The event itself starts at the press: the graph, the LAeq and the clip all
  /// begin when the user says the aircraft is here. The look-back survives
  /// because the rise above background is the one figure in the letter that an
  /// uncalibrated microphone cannot distort, and it needs a background.
  static const double preRollSeconds = 30;

  /// Leading slice of the pre-roll used to establish the background level.
  static const double ambientWindowSeconds = 10;

  /// Hard stop on a single recording.
  ///
  /// The user ends the recording, not a timer — but an app left recording in a
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

class CalibrationDefaults {
  /// dB SPL corresponding to a full-scale (rms = 1.0) signal.
  ///
  /// Phone MEMS microphones typically have an acoustic overload point around
  /// 120–125 dB SPL and digital full scale is set near it, so 120 is the least
  /// wrong default. It is still a guess: every snap taken on this default is
  /// flagged `calibrated: false` and the email says so explicitly. The one
  /// figure that survives a bad offset is the excess over the local background,
  /// because the offset cancels in the subtraction.
  static const double fullScaleDbSpl = 120.0;
}

class MatchConfig {
  /// How far back from the timestamp to search.
  ///
  /// Sound travels ~343 m/s: an aircraft at 300 m slant range was overhead
  /// ~0.9 s before you heard it, at 3 km ~9 s. Add human reaction time and the
  /// true overhead moment is routinely 20–40 s before the button press.
  static const double searchBackSeconds = 45;
  static const double searchForwardSeconds = 10;

  static const double speedOfSoundMs = 343.0;

  /// Radius of the ADS-B query.
  static const double queryRadiusNm = 25;

  /// Candidates further than this at closest approach are discarded.
  static const double maxSlantRangeM = 12000;

  /// Candidates lower than this elevation angle above the horizon are unlikely
  /// to be the aircraft that dominated the recording.
  static const double minElevationDegrees = 10;

  /// Poll interval for the rolling aircraft track cache while armed. The free
  /// community feeds ask for no more than one request per second.
  static const int trackPollIntervalMs = 3000;
}

class AppLinks {
  static const String adsbLolBase = 'https://api.adsb.lol/v2';
  static const String airplanesLiveBase = 'https://api.airplanes.live/v2';
  static const String openSkyTokenUrl =
      'https://auth.opensky-network.org/auth/realms/opensky-network/protocol/openid-connect/token';
  static const String openSkyApiBase = 'https://opensky-network.org/api';
}
