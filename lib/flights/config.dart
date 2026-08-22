/// Tunable constants for finding the aircraft that was overhead, and for
/// deciding whether it is close enough to name without asking.
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
