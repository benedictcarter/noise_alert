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
/// Three rules are enforced here rather than left to the template, because
/// getting any of them wrong discredits every complaint the user has ever
/// sent:
///
///  * a named flight is described as the closest ADS-B match and as not
///    independently verified, because the app now names one without asking;
///  * the letter leads on the gap between the loudest moment and the quietest,
///    not on an absolute figure. Two readings from the same microphone minutes
///    apart can be compared with each other whatever the handset's own error
///    is; a lone dB(A) figure invites an argument about the handset;
///  * a level that was never measured is never printed as a number. A missing
///    reading is stored as zero, and "0.0 dB(A)" is a claim, not a gap.
class ComplaintTemplate {
  const ComplaintTemplate();

  static final DateFormat _longFormat =
      DateFormat('EEEE d MMMM yyyy, HH:mm:ss');
  static final DateFormat _shortTimeFormat = DateFormat('HH:mm');
  static final NumberFormat _grouped = NumberFormat('#,##0');

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

    return ComplaintDraft(
      subject: _substitute(settings.templateSubject, tokens),
      body: _substitute(settings.templateBody, tokens),
      to: settings.activeRecipientSet.to,
      cc: settings.activeRecipientSet.cc,
      bcc: settings.activeRecipientSet.bcc,
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
      // No email address is collected any more -- the letter goes from the
      // user's own account, so the reply-to header already carries it. The
      // token stays, resolving to nothing, because a letter edited before the
      // field was dropped still contains it and an unknown token is left
      // standing in the text as a literal "{email}".
      'email': '',
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
      'laMax': _db(m, m.laMaxDb),
      'laEq': _db(m, m.laEqDb),
      'peakWindowLaEq': _db(m, m.peakWindowLaEqDb),
      'ambient': m.ambientLa90Db?.toStringAsFixed(1) ?? 'not measured',
      'excess': m.excessOverAmbientDb?.toStringAsFixed(1) ?? 'not measured',
      'eventSeconds': m.hasMeasurement
          ? (m.eventDurationMs / 1000).round().toString()
          : 'not measured',
      'measurementBlock': _measurementBlock(snap),
      'atAGlance': _atAGlance(snap),
      'device': snap.deviceModel,
      'osVersion': snap.osVersion,
      'appVersion': snap.appVersion,
      'measurementNote': _measurementNote(snap),
      'clipNote': _clipNote(snap),
      'chartNote': _chartNote(snap),
      'markedPeakNote': _markedPeakNote(snap),
      'notes': snap.notes,
    };
  }

  /// One reading, or an honest blank.
  ///
  /// A missing measurement is stored as zero, and "0.0 dB(A)" in a complaint is
  /// not a gap in the evidence, it is a claim about the world -- and a false
  /// one. Everything that prints a level goes through here.
  String _db(AcousticMetrics m, double value) =>
      m.hasMeasurement ? value.toStringAsFixed(1) : 'not measured';

  /// The three figures a human checks before believing the rest of the letter.
  ///
  /// The letter is sent as plain text -- the composer is handed
  /// `isHTML: false`, and the mailto: fallback could not carry markup even if
  /// it were not -- so there is no bold to reach for. An upper-case heading and
  /// three labelled lines do the same job in every client that has ever
  /// existed, including the council mail gateway that strips everything.
  ///
  /// Lines are never dropped when a figure is missing. "Loudest: not measured"
  /// is information; a line that quietly vanishes leaves a reader who does not
  /// know the format assuming the app measured something and they missed it.
  ///
  /// Deliberately no column alignment: most clients render plain text in a
  /// proportional font, so padded columns arrive ragged and look like a
  /// formatting failure rather than a table.
  String _atAGlance(Snap snap) {
    final AcousticMetrics m = snap.metrics;
    final FlightCandidate? candidate = snap.confirmedCandidate;

    final StringBuffer buffer = StringBuffer('AT A GLANCE')
      ..writeln()
      ..writeln('When: ${_longFormat.format(snap.recordedAt)}');

    if (!m.hasMeasurement) {
      buffer.writeln('Loudest: not measured');
    } else {
      final double? ambient = m.ambientLa90Db;
      final double? excess = m.excessOverAmbientDb;
      if (ambient != null && excess != null) {
        // The rise first. It is the figure that survives every objection a
        // recipient can make about a phone being used as a sound level meter,
        // so it is the one a skimming eye should land on.
        buffer.writeln('Loudest: ${excess.toStringAsFixed(1)} dB above the '
            'background -- ${_db(m, m.laMaxDb)} dB(A) at its peak, against '
            '${ambient.toStringAsFixed(1)} dB(A) when it was quiet');
      } else {
        buffer.writeln('Loudest: ${_db(m, m.laMaxDb)} dB(A) at its peak');
      }
    }

    if (candidate == null) {
      buffer.write('Aircraft: not identified');
    } else {
      buffer.write('Aircraft: ${candidate.aircraft.displayName}, '
          '${_grouped.format(candidate.heightAboveObserverFt.round())} ft '
          'above me, ${_grouped.format(candidate.slantRangeM.round())} m away '
          '(closest match, not verified)');
    }

    return buffer.toString();
  }

  /// The sound-level section, or what stands in for it.
  ///
  /// The complaint does not depend on this. A letter saying an aircraft was
  /// audible and disruptive at a given address at a given time is a complaint
  /// in its own right; the numbers are evidence that strengthens it. So when
  /// the microphone gave us nothing the letter says so in one plain sentence
  /// and carries on, rather than printing a table of zeroes or leaving a hole
  /// where the recipient expects data.
  String _measurementBlock(Snap snap) {
    final AcousticMetrics m = snap.metrics;
    if (!m.hasMeasurement) {
      final String why = m.note.isEmpty
          ? 'No sound level was recorded for this event.'
          : m.note;
      return 'Sound level: not measured. $why This complaint is my record that '
          'the aircraft was clearly audible and disruptive at the address and '
          'time above.';
    }

    final StringBuffer buffer = StringBuffer('Measured sound level')
      ..writeln();
    // The rise leads, because it is the figure that does not depend on the
    // handset: the peak and the background were read by the same microphone
    // minutes apart, so whatever its error is, it is in both and cancels.
    final double? excess = m.excessOverAmbientDb;
    if (excess != null) {
      buffer.writeln('  Rise above the background: '
          '${excess.toStringAsFixed(1)} dB');
    }
    buffer
      ..writeln('  Loudest moment (LAmax, fast): ${_db(m, m.laMaxDb)} dB(A)')
      // Always stated, even when absent: a recipient comparing complaints
      // needs to see that the background is missing rather than have the line
      // silently vanish.
      ..writeln('  Background, quietest 10% of the recording (LA90): '
          '${m.ambientLa90Db?.toStringAsFixed(1) ?? 'not measured'} dB(A)')
      ..writeln('  Average over the whole recording '
          '(LAeq, ${(m.eventDurationMs / 1000).round()} s): '
          '${_db(m, m.laEqDb)} dB(A)');
    return buffer.toString().trimRight();
  }

  /// Describes the attached chart, or says nothing at all if there is none.
  ///
  /// An empty string rather than an apology: a letter that explains what is
  /// missing draws attention to a gap the recipient would not otherwise notice.
  String _chartNote(Snap snap) {
    if (!snap.metrics.hasTrace) return '';
    final AcousticMetrics m = snap.metrics;
    final String window = (m.eventDurationMs / 1000).round().toString();
    return 'Attached: a chart of the A-weighted sound level across the '
        '$window s of the recording, marked with the moment I logged it'
        '${m.hasAmbient ? ' and with the background level' : ''}. '
        '${LevelChartLabels.caption()}';
  }

  /// The moment the complainant marked as the worst of the flyover.
  ///
  /// Deliberately written in the first person and kept apart from every
  /// measured figure. The mark is a claim about experience -- closest approach,
  /// or whatever actually made the noise unbearable -- and a recipient who
  /// reads it as a second measurement, then finds it disagrees with LAmax, has
  /// been handed a reason to dismiss the whole letter.
  String _markedPeakNote(Snap snap) {
    final int? marked = snap.markedPeakMs;
    if (marked == null) return '';
    final AcousticMetrics m = snap.metrics;
    final String at = (marked / 1000).round().toString();

    final StringBuffer buffer = StringBuffer()
      ..write('The worst of it, as I experienced it, was about $at s into the '
          'recording');
    final int index = m.traceIntervalMs <= 0
        ? -1
        : (marked / m.traceIntervalMs).round();
    if (index >= 0 && index < m.levelTrace.length) {
      buffer.write(' (${m.levelTrace[index].toStringAsFixed(1)} dB(A) at that '
          'moment)');
    }
    buffer.write('. That is my own account of when the aircraft was at its '
        'most intrusive, not a separate measurement -- the figures above are '
        'the measured ones, and the maximum they quote may fall elsewhere in '
        'the recording.');
    return buffer.toString();
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
        'Identified from public ADS-B position reports '
        '(${candidate.aircraft.source}) as the aircraft closest to my position '
        'at that time, allowing for the '
        '${(candidate.slantRangeM / MatchConfig.speedOfSoundMs).toStringAsFixed(1)} s '
        'the sound took to travel that distance. I have not independently '
        'verified the identification, and would ask you to check it against '
        'your own records before acting on it.',
      );
    return buffer.toString();
  }

  String _measurementNote(Snap snap) {
    final AcousticMetrics m = snap.metrics;
    if (!m.hasMeasurement) {
      return 'Logged with the Flightpath Watch Alert app on a '
          '${snap.deviceModel} running ${snap.osVersion}. No sound measurement '
          'is attached to this event, so nothing here should be read as one.';
    }
    final StringBuffer buffer = StringBuffer()
      ..write(
        'Measured with the Flightpath Watch Alert app on a ${snap.deviceModel} running '
        '${snap.osVersion}, sampling at ${(m.sampleRate / 1000).toStringAsFixed(0)} kHz '
        'with IEC 61672 A-weighting and fast (125 ms) time weighting.',
      );

    // What the figures are, stated once and without apology. The comparison
    // is between two readings taken by one microphone within a few minutes of
    // each other, which is what makes the rise worth quoting.
    final double? excess = m.excessOverAmbientDb;
    if (excess != null) {
      buffer.write(
        ' The peak and the background were both read by that microphone during '
        'this one recording, so the ${excess.toStringAsFixed(1)} dB between '
        'them is a like-for-like comparison.',
      );
    } else {
      buffer.write(
        ' The recording was too short to contain a quiet moment to compare the '
        'peak against, so no rise above the background is quoted.',
      );
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
  {name} {address} {addressOneLine} {postcode} {phone} {phoneLine}
  {datetimeLong} {date} {time} {latitude} {longitude} {locationLine}
  {flight} {callsign} {registration} {aircraftType} {icao24}
  {aircraftDescription} {aircraftBlock}
  {heightFt} {slantRangeM} {elevationDeg}
  {laMax} {laEq} {peakWindowLaEq} {ambient} {excess} {eventSeconds}
  {measurementBlock} {atAGlance}
  {device} {osVersion} {appVersion} {measurementNote} {clipNote}
  {chartNote} {markedPeakNote} {notes}
''';
}
