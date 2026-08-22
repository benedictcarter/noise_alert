/// Every address this app can reach, in one file.
///
/// Nothing outside `lib/net/` may hold a URL and nothing outside `lib/net/`
/// may import `package:http`; `test/no_outbound_calls_outside_net_test.dart`
/// fails the build if either happens. So this list is the whole outbound
/// surface, and a sixth entry is a decision rather than a detail.
///
/// What each one is sent, and when:
///
/// | Host | Sent | Trigger |
/// |---|---|---|
/// | api.adsb.lol | latitude, longitude, radius | every 3 s while recording |
/// | api.airplanes.live | latitude, longitude, radius | as above, second opinion |
/// | auth.opensky-network.org | the user's own OpenSky client id and secret | only if they entered them |
/// | opensky-network.org | a latitude/longitude box, plus that token | as above |
/// | tiles.openfreemap.org | the tile coordinates being looked at | while a map is on screen |
/// | api.postcodes.io | one postcode | only when the user presses the button |
///
/// No name, no email address, no phone number, no device id and no account
/// goes to any of them. There is no backend, no analytics and no crash
/// reporter. The complaint itself leaves through the user's own mail app, at
/// their hand, which is the only thing in the app that carries who they are.
class Endpoints {
  /// Community ADS-B feed, no key. Used first because it needs no account.
  static const String adsbLolBase = 'https://api.adsb.lol/v2';

  /// Second community feed, no key. Queried alongside adsb.lol so a gap in one
  /// receiver's coverage does not lose the aircraft.
  static const String airplanesLiveBase = 'https://api.airplanes.live/v2';

  /// OpenSky is the historical fallback, for a complaint written up to an hour
  /// after the event, and it is the one service that needs credentials. They
  /// are the user's own, typed into Settings, stored on the device, and sent
  /// nowhere but here.
  static const String openSkyTokenUrl =
      'https://auth.opensky-network.org/auth/realms/opensky-network/protocol/openid-connect/token';
  static const String openSkyApiBase = 'https://opensky-network.org/api';

  /// Basemap tiles. Fetched by native MapLibre rather than by Dart, so this is
  /// the one outbound call that does not go through `package:http` and cannot
  /// be seen in the code below it: what MapLibre asks for is a tile
  /// coordinate, and there is no key, no cookie and no account to attach.
  static const String mapStyleUrl =
      'https://tiles.openfreemap.org/styles/liberty';

  /// Free, key-less front end to the ONS Postcode Directory, so an older user
  /// types two fields instead of five.
  static const String postcodesHost = 'api.postcodes.io';
}
