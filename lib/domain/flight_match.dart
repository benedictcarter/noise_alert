import 'aircraft.dart';

/// One aircraft considered as the source of a noise event, with the geometry
/// that got it there.
class FlightCandidate {
  const FlightCandidate({
    required this.aircraft,
    required this.closestApproachTime,
    required this.slantRangeM,
    required this.horizontalRangeM,
    required this.heightAboveObserverM,
    required this.elevationDegrees,
    required this.score,
    required this.extrapolated,
    this.track = const <TrackPoint>[],
  });

  /// The aircraft, at the sample nearest its closest approach.
  final AircraftSample aircraft;

  /// When it was closest, *not* when the sound was heard. The two differ by
  /// the propagation delay, which the matcher has already accounted for.
  final DateTime closestApproachTime;

  final double slantRangeM;
  final double horizontalRangeM;
  final double heightAboveObserverM;

  /// Angle above the horizon at closest approach. 90 is directly overhead.
  final double elevationDegrees;

  /// Higher is better. Only meaningful relative to other candidates for the
  /// same snap.
  final double score;

  /// True when the position was dead-reckoned from a single report rather than
  /// observed. Reduces confidence in the answer.
  final bool extrapolated;

  /// The path this aircraft was actually seen to fly across the search window,
  /// oldest first. Empty for a match resolved from a single report, and empty
  /// for every match stored before the map existed.
  ///
  /// This is the evidence the map draws. One position says an aeroplane was
  /// somewhere; a track says it came over the house, which is the thing the
  /// complaint is about.
  final List<TrackPoint> track;

  double get heightAboveObserverFt => heightAboveObserverM * 3.28084;
}

/// The outcome of matching one snap against the sky.
class FlightMatch {
  const FlightMatch({
    required this.candidates,
    required this.confidence,
    required this.searchedFrom,
    required this.searchedTo,
    this.selectedIcao24,
    this.note,
  });

  const FlightMatch.none({
    required this.searchedFrom,
    required this.searchedTo,
    this.note,
  })  : candidates = const <FlightCandidate>[],
        confidence = 0,
        selectedIcao24 = null;

  /// Best first.
  final List<FlightCandidate> candidates;

  /// 0..1. Derived from how far clear the leader is of the runner-up and how
  /// good its geometry is in absolute terms. Deliberately conservative: this
  /// number decides whether the UI dares pre-tick a flight number.
  final double confidence;

  final DateTime searchedFrom;
  final DateTime searchedTo;

  /// Set once the user has confirmed which aircraft it was. Until then the app
  /// must not put a flight number in a complaint.
  final String? selectedIcao24;

  final String? note;

  FlightCandidate? get best => candidates.isEmpty ? null : candidates.first;

  bool get hasCandidates => candidates.isNotEmpty;

  /// Above this the UI may pre-select the leading candidate; below it the user
  /// picks from the list with nothing chosen for them.
  bool get isConfidentEnoughToPreselect => confidence >= 0.7;
}
