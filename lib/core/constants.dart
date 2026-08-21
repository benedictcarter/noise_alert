/// Tunable constants, gathered so the acoustics and matching can be adjusted
/// without hunting through the code.
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

class MatchConfig {
  /// How far back from the timestamp to search.
  ///
  /// Sound travels ~343 m/s: an aircraft at 300 m slant range was overhead
  /// ~0.9 s before you heard it, at 3 km ~9 s. Add human reaction time and the
  /// true overhead moment is routinely 20-40 s before the button press.
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

  /// How close overhead the best candidate has to be before SEND will
  /// name it without asking.
  ///
  /// One kilometre horizontally. Inside that the aircraft was effectively over
  /// the house and there is nothing for the user to adjudicate; outside it the
  /// geometry stops being obvious (a jet 3 km away on the ground track can
  /// easily be the wrong one), so the review screen is shown instead and the
  /// user picks. This is the whole of the difference between saving a click and
  /// putting a stranger's callsign in a complaint for no reason.
  static const double autoConfirmMaxHorizontalM = 1000;

  /// Poll interval for the rolling aircraft track cache while armed. The free
  /// community feeds ask for no more than one request per second.
  static const int trackPollIntervalMs = 3000;

  /// Most positions kept per candidate when the match is written to the
  /// database.
  ///
  /// A five-minute recording polled every three seconds is a hundred reports
  /// per aircraft, and at the scale a map of one street is drawn at, forty of
  /// them and a hundred are the same picture. The cost of the other sixty is
  /// paid on every history load, because the whole match is one JSON column.
  static const int maxTrackPoints = 60;
}

class MapConfig {
  /// OpenFreeMap's hosted `liberty` style: real OpenStreetMap data, no API key,
  /// no registration, no cookies and no request limit, paid for by donation.
  /// The single obligation is that [attribution] is shown, which is why it is
  /// next to the URL rather than somewhere in the widget tree.
  ///
  /// This is the app's third and last outbound call. It carries the coordinates
  /// of the tiles being looked at and nothing else: no account, no identifier
  /// and no name. See the note in CLAUDE.md.
  static const String styleUrl = 'https://tiles.openfreemap.org/styles/liberty';

  /// Shown under every map, and burnt into the picture attached to the
  /// complaint, because that picture leaves the app and the obligation travels
  /// with it.
  static const String attribution =
      '© OpenFreeMap © OpenMapTiles  Data from OpenStreetMap';

  /// How long to wait for the basemap before saying so.
  ///
  /// There is no "style failed" callback to listen for (a style that cannot be
  /// fetched simply never loads), so silence past this point is treated as
  /// offline. The map still knows where the house and the aeroplane were; it
  /// just cannot draw the streets under them, and it says which.
  static const int styleTimeoutMs = 8000;

  /// Size of the PNG attached to the complaint, in pixels.
  ///
  /// Wide enough to read street names when printed on A4, small enough that
  /// nobody's council mailbox rejects the message.
  static const int emailImageWidth = 900;
  static const int emailImageHeight = 640;
}

class AppLinks {
  static const String adsbLolBase = 'https://api.adsb.lol/v2';
  static const String airplanesLiveBase = 'https://api.airplanes.live/v2';
  static const String openSkyTokenUrl =
      'https://auth.opensky-network.org/auth/realms/opensky-network/protocol/openid-connect/token';
  static const String openSkyApiBase = 'https://opensky-network.org/api';
}
