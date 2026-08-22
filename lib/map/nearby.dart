import 'package:noise_alert/flights/aircraft.dart';
import 'package:noise_alert/map/config.dart';
import 'package:noise_alert/where/geo.dart';
import 'package:noise_alert/where/location.dart';

/// The tracks worth drawing on the record screen: those whose aircraft is
/// within [MapConfig.liveRadiusM] of the user right now.
///
/// The query behind the cache reaches 25 nm because the matcher needs it to.
/// The map does not: forty aeroplanes strewn across three counties is not a
/// picture of what is overhead, it is a picture of a busy sky.
///
/// Judged on the latest position rather than on any point of the track, so an
/// aeroplane that passed overhead ten minutes ago and is now fifty miles away
/// drops off the map instead of leaving its tail lying across it.
///
/// No fix means no circle to be inside, and so nothing to draw. The screen
/// says as much; recording and complaining both carry on regardless.
List<AircraftTrack> nearbyTracks(
  List<AircraftTrack> tracks,
  SnapLocation? here,
) {
  if (here == null) return const <AircraftTrack>[];
  return <AircraftTrack>[
    for (final AircraftTrack t in tracks)
      if (haversineMetres(
            here.latitude,
            here.longitude,
            t.latest.latitude,
            t.latest.longitude,
          ) <=
          MapConfig.liveRadiusM)
        t,
  ];
}
