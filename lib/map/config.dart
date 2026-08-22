/// Tunable constants for drawing the map. The one URL the map needs lives in
/// `lib/net/endpoints.dart` with the rest of the outbound surface.
class MapConfig {
  /// Shown under every map, and burnt into the picture attached to the
  /// complaint, because that picture leaves the app and the obligation travels
  /// with it.
  ///
  /// OpenFreeMap's `liberty` style is real OpenStreetMap data with no API key,
  /// no registration, no cookies and no request limit, paid for by donation.
  /// The single obligation is that this line is shown.
  static const String attribution =
      '© OpenFreeMap © OpenMapTiles  Data from OpenStreetMap';

  /// How long to wait for the basemap before saying so.
  ///
  /// There is no "style failed" callback to listen for (a style that cannot be
  /// fetched simply never loads), so silence past this point is treated as
  /// offline. The map still knows where the house and the aeroplane were; it
  /// just cannot draw the streets under them, and it says which.
  static const int styleTimeoutMs = 8000;

  /// How far out the live map on the record screen draws aircraft.
  ///
  /// The query behind it reaches 25 nm because the matcher needs that much: an
  /// aircraft heard here can be a long way off. What is worth *looking* at is
  /// a much smaller circle, and drawing forty distant aeroplanes over one
  /// street turns the useful ones into clutter. Five kilometres is about the
  /// distance at which an airliner is still plainly the one you can hear.
  ///
  /// Display only. The evidence map drawn for the complaint shows whichever
  /// aircraft was matched, however far away it turned out to be.
  static const double liveRadiusM = 5000;

  /// Size of the PNG attached to the complaint, in pixels.
  ///
  /// Wide enough to read street names when printed on A4, small enough that
  /// nobody's council mailbox rejects the message.
  static const int emailImageWidth = 900;
  static const int emailImageHeight = 640;
}
