import 'package:intl/intl.dart';

import '../../core/constants.dart';
import '../../domain/acoustic_metrics.dart';
import '../../domain/aircraft.dart';
import '../../domain/flight_match.dart';
import '../../domain/profile.dart';
import '../../domain/settings.dart';
import '../../domain/snap.dart';
import '../../features/chart/level_chart.dart';

/// A rendered complaint, ready to hand to the mail composer.
class ComplaintDraft {
  const ComplaintDraft({
    required this.subject,
    required this.body,
    required this.to,
    required this.cc,
    required this.bcc,
    required this.attachmentPaths,
  });

  final String subject;
  final String body;
  final List<String> to;
  final List<String> cc;
  final List<String> bcc;
  final List<String> attachmentPaths;
}

/// Fills the form letter in.
///
/// Two rules are enforced here rather than left to the template, because
/// getting either wrong discredits every complaint the user has ever sent:
///
///  * a flight is only ever named if the user confirmed it;
///  * an uncalibrated sound level is always labelled as such.
class ComplaintTemplate {
  const ComplaintTemplate();

  static final DateFormat _longFormat =
      DateFormat('EEEE d MMMM yyyy, HH:mm:ss');
  static final DateFormat _shortTimeFormat = DateFormat('HH:mm');

  ComplaintDraft render({
    required Snap snap,
    required ComplainantProfile profile,
    required AppSettings settings,
    String? chartPath,
  }) {
    final Map<String, String> tokens = buildTokens(
      snap: snap,
      profile: profile,
      settings: settings,
    );

    final List<String> bcc = <String>{
      ...settings.activeRecipientSet.bcc,
      if (settings.bccSelf && profile.email.trim().isNotEmpty)
        profile.email.trim(),
    }.toList();

    return ComplaintDraft(
      subject: _substitute(settings.templateSubject, tokens),
      body: _substitute(settings.templateBody, tokens),
      to: settings.activeRecipientSet.to,
      cc: settings.activeRecipientSet.cc,
      bcc: bcc,
      attachmentPaths: <String>[
        // The chart goes on every letter. Unlike the audio it carries nothing
        // the body does not already state - it is the same numbers, drawn -
        // so there is no privacy trade-off to put to the user, and a picture of
        // the event is the part a noise team actually reads.
        if (chartPath != null) chartPath,
        if (snap.attachClip && snap.clipPath != null) snap.clipPath!,
      ],
    );
  }

  Map<String, String> buildTokens({
    required Snap snap,
    required ComplainantProfile profile,
    required AppSettings settings,
  }) {
    final AcousticMetrics m = snap.metrics;
    final FlightCandidate? candidate = snap.confirmedCandidate;
    final AircraftSample? aircraft = candidate?.aircraft;

    return <String, String>{
      'name': profile.fullName,
      'address': profile.addressBlock,
      'addressOneLine': profile.addressOneLine,
      'postcode': profile.postcode,
      'email': profile.email,
      'phone': profile.phone,
      'phoneLine':
          profile.phone.trim().isEmpty ? '' : '\n${profile.phone.trim()}',
      'datetimeLong': _longFormat.format(snap.recordedAt),
      'date': DateFormat('d MMMM yyyy').format(snap.recordedAt),
      'time': _shortTimeFormat.format(snap.recordedAt),
      'latitude': snap.latitude?.toStringAsFixed(5) ?? 'not recorded',
      'longitude': snap.longitude?.toStringAsFixed(5) ?? 'not recorded',
      'locationLine': _locationLine(snap, profile),
      'flight': _flightLabel(aircraft),
      'callsign': aircraft?.callsign?.trim() ?? '',
      'registration': aircraft?.registration?.trim() ?? '',
      'aircraftType': aircraft?.aircraftType?.trim() ?? '',
      'icao24': aircraft?.icao24.toUpperCase() ?? '',
      'aircraftDescription': _aircraftDescription(aircraft),
      'aircraftBlock': _aircraftBlock(snap, candidate),
      'heightFt': candidate == null
          ? 'not determined'
          : candidate.heightAboveObserverFt.round().toString(),
      'slantRangeM': candidate == null
          ? 'not determined'
          : candidate.slantRangeM.round().toString(),
      'elevationDeg': candidate == null
          ? 'not determined'
          : candidate.elevationDegrees.round().toString(),
      'laMax': m.laMaxDb.toStringAsFixed(1),
      'laEq': m.laEqDb.toStringAsFixed(1),
      'peakWindowLaEq': m.peakWindowLaEqDb.toStringAsFixed(1),
      'ambient': m.ambientLa90Db?.toStringAsFixed(1) ?? 'not measured',
      'excess': m.excessOverAmbientDb?.toStringAsFixed(1) ?? 'not measured',
      'eventSeconds': (m.eventDurationMs / 1000).round().toString(),
      'device': snap.deviceModel,
      'osVersion': snap.osVersion,
      'appVersion': snap.appVersion,
      'measurementNote': _measurementNote(snap),
      'clipNote': _clipNote(snap),
      'chartNote': _chartNote(snap),
      'notes': snap.notes,
    };
  }

  /// Describes the attached chart, or says nothing at all if there is none.
  ///
  /// An empty string rather than an apology: a letter that explains what is
  /// missing draws attention to a gap the recipient would not otherwise notice.
  String _chartNote(Snap snap) {
    if (!snap.metrics.hasTrace) return '';
    final AcousticMetrics m = snap.metrics;
    final String window = (m.eventDurationMs / 1000).round().toString();
    return 'Attached: a chart of the A-weighted sound level over the $window s '
        'either side of the event, marked with the moment I logged it'
        '${m.hasAmbient ? ' and with the background level before it' : ''}. '
        '${LevelChartLabels.caption(calibrated: m.calibrated)}';
  }

  String _flightLabel(AircraftSample? aircraft) {
    if (aircraft == null) return 'an unidentified aircraft';
    return aircraft.displayName;
  }

  String _aircraftDescription(AircraftSample? aircraft) {
    if (aircraft == null) {
      return 'not identified — no ADS-B match could be confirmed';
    }
    final List<String> parts = <String>[];
    final String? cs = aircraft.callsign?.trim();
    if (cs != null && cs.isNotEmpty) parts.add('callsign $cs');
    final String? reg = aircraft.registration?.trim();
    if (reg != null && reg.isNotEmpty) parts.add('registration $reg');
    final String? type = aircraft.aircraftType?.trim();
    if (type != null && type.isNotEmpty) parts.add('type $type');
    parts.add('ICAO ${aircraft.icao24.toUpperCase()}');
    return parts.join(', ');
  }

  /// The aircraft paragraph, written so it stays truthful when nothing was
  /// identified rather than emitting "not determined ft".
  String _aircraftBlock(Snap snap, FlightCandidate? candidate) {
    if (candidate == null) {
      return 'Aircraft: not identified. No ADS-B position report could be '
          'matched to this event, so no flight is named in this complaint. The '
          'measurement and location below stand on their own.';
    }

    final StringBuffer buffer = StringBuffer()
      ..writeln('Aircraft: ${_aircraftDescription(candidate.aircraft)}')
      ..writeln(
          'Height above my position: ${candidate.heightAboveObserverFt.round()} ft')
      ..writeln(
        'Closest approach: ${candidate.slantRangeM.round()} m away, '
        '${candidate.elevationDegrees.round()}° above the horizon, at '
        '${_longFormat.format(candidate.closestApproachTime.toLocal())}',
      )
      ..write(
        'Identified from public ADS-B position reports (${candidate.aircraft.source}), '
        'allowing for the ${(candidate.slantRangeM / MatchConfig.speedOfSoundMs).toStringAsFixed(1)} s '
        'the sound took to travel that distance.',
      );
    return buffer.toString();
  }

  String _measurementNote(Snap snap) {
    final AcousticMetrics m = snap.metrics;
    final StringBuffer buffer = StringBuffer()
      ..write(
        'Measured with the Flightpath Watch Alert app on a ${snap.deviceModel} running '
        '${snap.osVersion}, sampling at ${(m.sampleRate / 1000).toStringAsFixed(0)} kHz '
        'with IEC 61672 A-weighting and fast (125 ms) time weighting.',
      );

    if (m.calibrated) {
      buffer.write(
        ' The handset was calibrated against a reference sound level meter '
        '(offset ${m.calibrationOffsetDb.toStringAsFixed(1)} dB).',
      );
    } else {
      buffer.write(
        ' This handset has NOT been calibrated against a reference sound level '
        'meter, so the absolute values should be treated as indicative rather '
        'than as a formal measurement.',
      );
      final double? excess = m.excessOverAmbientDb;
      if (excess != null) {
        buffer.write(
          ' The rise above the background level '
          '(${excess.toStringAsFixed(1)} dB) does not depend on calibration '
          'and is reliable.',
        );
      } else {
        buffer.write(
          ' The background level before the event was not captured for this '
          'measurement, so no rise above background is quoted.',
        );
      }
    }

    if (m.clipped) {
      buffer.write(
        ' The microphone reached its maximum input level during this event, so '
        'the peak figure is a lower bound: the aircraft was at least this loud.',
      );
    }

    return buffer.toString();
  }

  /// The "where I was" line, written so a missing fix reads as a plain fact
  /// rather than as a pair of zeroes the recipient would reasonably read as
  /// coordinates. The home address is always there as the fallback, and is in
  /// any case the address the complaint is about.
  String _locationLine(Snap snap, ComplainantProfile profile) {
    final String postcode = profile.postcode.trim();
    final String suffix = postcode.isEmpty ? '' : ' ($postcode)';

    if (!snap.hasLocation) {
      return 'Location: my home address above$suffix. '
          'No satellite fix was recorded for this measurement.';
    }

    final StringBuffer buffer = StringBuffer('Location: ')
      ..write(snap.latitude!.toStringAsFixed(5))
      ..write(', ')
      ..write(snap.longitude!.toStringAsFixed(5));
    final double? accuracy = snap.gpsAccuracyM;
    if (accuracy != null) buffer.write(' (±${accuracy.round()} m)');
    buffer.write(suffix);
    if (snap.staleFix) {
      buffer.write(' — taken from the last known position of the handset '
          'rather than a live fix at the time of the event.');
    }
    return buffer.toString();
  }

  String _clipNote(Snap snap) {
    if (!snap.attachClip || snap.clipPath == null) return '';
    return 'Attached is a ${(snap.metrics.peakWindowDurationMs / 1000).round()} second '
        'recording of the loudest part of the event, starting '
        '${(snap.metrics.peakWindowStartMs / 1000).round()} s into the recording.';
  }

  static String _substitute(String template, Map<String, String> tokens) {
    final String out = template.replaceAllMapped(
      RegExp(r'\{(\w+)\}'),
      (Match match) => tokens[match.group(1)] ?? match.group(0)!,
    );
    // Collapse the blank lines left behind by tokens that resolved to nothing.
    return out.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  static const String tokenHelp = '''
Available tokens:
  {name} {address} {addressOneLine} {postcode} {email} {phone} {phoneLine}
  {datetimeLong} {date} {time} {latitude} {longitude} {locationLine}
  {flight} {callsign} {registration} {aircraftType} {icao24}
  {aircraftDescription} {aircraftBlock}
  {heightFt} {slantRangeM} {elevationDeg}
  {laMax} {laEq} {peakWindowLaEq} {ambient} {excess} {eventSeconds}
  {device} {osVersion} {appVersion} {measurementNote} {clipNote}
  {chartNote} {notes}
''';
}
