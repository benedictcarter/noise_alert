import 'package:flutter_test/flutter_test.dart';
import 'package:noise_alert/data/mail/complaint_template.dart';
import 'package:noise_alert/data/mail/mail_sender.dart';
import 'package:noise_alert/domain/acoustic_metrics.dart';
import 'package:noise_alert/domain/aircraft.dart';
import 'package:noise_alert/domain/flight_match.dart';
import 'package:noise_alert/domain/profile.dart';
import 'package:noise_alert/domain/settings.dart';
import 'package:noise_alert/domain/snap.dart';

final DateTime _heardAt = DateTime(2026, 8, 19, 21, 14, 30);

const ComplainantProfile _profile = ComplainantProfile(
  fullName: 'A Resident',
  addressLine1: '1 Quiet Lane',
  town: 'Someton',
  postcode: 'AB1 2CD',
  email: 'resident@example.com',
);

AcousticMetrics _metrics({
  bool calibrated = false,
  bool clipped = false,
  double laMax = 78.4,
  double? ambient = 38.1,
  double preRoll = 30,
  bool trace = true,
}) =>
    AcousticMetrics(
      laEqDb: 68.2,
      laMaxDb: laMax,
      ambientLa90Db: ambient,
      preRollSeconds: preRoll,
      levelTrace:
          trace ? const <double>[40, 45, 62, 78, 71, 55, 42] : const <double>[],
      peakWindowLaEqDb: 71.9,
      peakWindowStartMs: 24000,
      peakWindowDurationMs: 10000,
      eventDurationMs: 50000,
      clipped: clipped,
      calibrated: calibrated,
      calibrationOffsetDb: 120,
      sampleRate: 48000,
    );

final AircraftSample _aircraft = AircraftSample(
  icao24: 'abc123',
  timestamp: _heardAt.subtract(const Duration(seconds: 5)),
  latitude: 51.5,
  longitude: -0.1,
  callsign: 'BAW123',
  registration: 'G-ABCD',
  aircraftType: 'A320',
  altitudeFt: 950,
  source: 'adsb.lol',
);

FlightMatch _match() => FlightMatch(
      candidates: <FlightCandidate>[
        FlightCandidate(
          aircraft: _aircraft,
          closestApproachTime: _heardAt.subtract(const Duration(seconds: 5)),
          slantRangeM: 340,
          horizontalRangeM: 90,
          heightAboveObserverM: 290,
          elevationDegrees: 72,
          score: 0.9,
          extrapolated: false,
        ),
      ],
      confidence: 0.9,
      searchedFrom: _heardAt.subtract(const Duration(seconds: 45)),
      searchedTo: _heardAt.add(const Duration(seconds: 10)),
    );

Snap _snap({
  bool confirmed = true,
  bool unidentified = false,
  bool withMatch = true,
  bool calibrated = false,
  bool clipped = false,
  String? clipPath,
  bool attachClip = false,
  bool located = true,
  double? ambient = 38.1,
  double preRoll = 30,
  bool trace = true,
}) =>
    Snap(
      id: 'snap-1',
      recordedAt: _heardAt,
      latitude: located ? 51.50012 : null,
      longitude: located ? -0.10034 : null,
      gpsAccuracyM: located ? 8 : null,
      metrics: _metrics(
        calibrated: calibrated,
        clipped: clipped,
        ambient: ambient,
        preRoll: preRoll,
        trace: trace,
      ),
      status: SnapStatus.confirmed,
      match: withMatch ? _match() : null,
      selectedIcao24: confirmed && withMatch ? 'abc123' : null,
      unidentifiedAircraft: unidentified,
      clipPath: clipPath,
      attachClip: attachClip,
      deviceModel: 'Google Pixel 8',
      osVersion: 'Android 15 (SDK 35)',
      appVersion: '0.1.0+1',
    );

void main() {
  const ComplaintTemplate template = ComplaintTemplate();
  const AppSettings settings = AppSettings();

  test('a confirmed flight is named, with the geometry that identified it', () {
    final ComplaintDraft draft = template.render(
      snap: _snap(),
      profile: _profile,
      settings: settings,
    );

    expect(draft.subject, contains('BAW123'));
    expect(draft.subject, contains('AB1 2CD'));
    expect(draft.body, contains('callsign BAW123'));
    expect(draft.body, contains('registration G-ABCD'));
    expect(draft.body, contains('type A320'));
    expect(draft.body, contains('951 ft')); // 290 m above the observer
    expect(draft.body, contains('adsb.lol'));
    expect(draft.body, contains('A Resident'));
    expect(draft.body, contains('1 Quiet Lane'));
  });

  test('an unconfirmed match never puts a flight number in the letter', () {
    // The candidate exists but the user has not confirmed it. Naming it here
    // would be the app inventing an accusation.
    final ComplaintDraft draft = template.render(
      snap: _snap(confirmed: false, unidentified: true),
      profile: _profile,
      settings: settings,
    );

    expect(draft.body, isNot(contains('BAW123')));
    expect(draft.body, isNot(contains('G-ABCD')));
    expect(draft.subject, contains('an unidentified aircraft'));
    expect(draft.body, contains('not identified'));
    // No leftover placeholder text where the geometry would have been.
    expect(draft.body, isNot(contains('not determined ft')));
    expect(draft.body, isNot(contains('{')));
  });

  test('an uncalibrated handset is declared, with its make and OS', () {
    final ComplaintDraft draft = template.render(
      snap: _snap(),
      profile: _profile,
      settings: settings,
    );

    expect(draft.body, contains('Google Pixel 8'));
    expect(draft.body, contains('Android 15 (SDK 35)'));
    expect(draft.body, contains('NOT been calibrated'));
    expect(draft.body, contains('40.3 dB')); // 78.4 − 38.1, offset-independent
  });

  test('a calibrated handset says so instead', () {
    final ComplaintDraft draft = template.render(
      snap: _snap(calibrated: true),
      profile: _profile,
      settings: settings,
    );

    expect(draft.body, contains('was calibrated against a reference'));
    expect(draft.body, isNot(contains('NOT been calibrated')));
  });

  test('clipping is disclosed as a lower bound', () {
    final ComplaintDraft draft = template.render(
      snap: _snap(clipped: true),
      profile: _profile,
      settings: settings,
    );

    expect(draft.body, contains('at least this loud'));
  });

  test('the clip is attached only when the user asked for it', () {
    final ComplaintDraft without = template.render(
      snap: _snap(clipPath: '/tmp/clip.wav'),
      profile: _profile,
      settings: settings,
    );
    expect(without.attachmentPaths, isEmpty);
    expect(without.body, isNot(contains('Attached is a')));

    final ComplaintDraft with_ = template.render(
      snap: _snap(clipPath: '/tmp/clip.wav', attachClip: true),
      profile: _profile,
      settings: settings,
    );
    expect(with_.attachmentPaths, <String>['/tmp/clip.wav']);
    expect(with_.body, contains('Attached is a 10 second'));
  });

  test('bccSelf adds the complainant once, without duplicating', () {
    final ComplaintDraft draft = template.render(
      snap: _snap(),
      profile: _profile,
      settings: const AppSettings(
        recipientSets: <RecipientSet>[
          RecipientSet(
            id: 'default',
            label: 'Default',
            to: <String>['airport@example.com'],
            bcc: <String>['resident@example.com', 'group@example.com'],
          ),
        ],
      ),
    );

    expect(draft.to, <String>['airport@example.com']);
    expect(
      draft.bcc.where((String a) => a == 'resident@example.com').length,
      1,
    );
    expect(draft.bcc, contains('group@example.com'));
  });

  test('an unknown token is left visible rather than silently dropped', () {
    final ComplaintDraft draft = template.render(
      snap: _snap(),
      profile: _profile,
      settings: const AppSettings(
        templateSubject: 'x',
        templateBody: 'Level was {laMax} and {notARealToken}.',
      ),
    );

    expect(draft.body, 'Level was 78.4 and {notARealToken}.');
  });

  test('the mailto fallback encodes the whole letter', () {
    final ComplaintDraft draft = template.render(
      snap: _snap(),
      profile: _profile,
      settings: settings,
    );
    final Uri uri = MailSender.buildMailtoUri(draft);

    expect(uri.scheme, 'mailto');
    expect(uri.path, 'benedict.carter@gmail.com');
    expect(uri.queryParameters['subject'], draft.subject);
    expect(uri.queryParameters['body'], draft.body);
  });

  test('a snap with no fix says so instead of quoting a coordinate', () {
    // The old code stored a missing fix as 0, 0 and the letter printed
    // "Location: 0.00000, 0.00000" — a real position off the coast of Ghana,
    // and one the recipient has no way of recognising as a failure.
    final ComplaintDraft draft = template.render(
      snap: _snap(located: false),
      profile: _profile,
      settings: settings,
    );

    expect(draft.body, isNot(contains('0.00000')));
    expect(draft.body, contains('No satellite fix was recorded'));
    // The home address still anchors the complaint.
    expect(draft.body, contains('AB1 2CD'));
  });

  test('a located snap still prints coordinates and their accuracy', () {
    final ComplaintDraft draft = template.render(
      snap: _snap(),
      profile: _profile,
      settings: settings,
    );

    expect(draft.body, contains('51.50012, -0.10034'));
    expect(draft.body, contains('±8 m'));
  });

  test('with no background measured, no rise above background is claimed', () {
    // A widget-triggered snap has no pre-roll. Quoting a rise over a
    // background derived from un-recorded silence would overstate the event by
    // tens of dB — precisely the direction that would discredit a complaint.
    final ComplaintDraft draft = template.render(
      snap: _snap(ambient: null, preRoll: 0),
      profile: _profile,
      settings: settings,
    );

    expect(draft.body, contains('not measured'));
    expect(draft.body, contains('background level before the event was not '
        'captured'));
    expect(draft.body, isNot(contains('Rise above background: 40.3 dB')));
    // The uncalibrated warning must survive: it is the other honesty clause.
    expect(draft.body, contains('has NOT been calibrated'));
  });

  test('the chart is described in the letter and attached to it', () {
    // The plot goes on every complaint: it is the part a noise team reads
    // first, and it contains nothing the body does not already state.
    final ComplaintDraft draft = template.render(
      snap: _snap(),
      profile: _profile,
      settings: settings,
      chartPath: '/tmp/snap-1-level.png',
    );

    expect(draft.attachmentPaths, contains('/tmp/snap-1-level.png'));
    expect(draft.body, contains('Attached: a chart'));
    // The calibration caveat must travel with the picture, not only with the
    // numbers - a chart reads as far more authoritative than a line of text.
    expect(draft.body, contains('UNCALIBRATED'));
  });

  test('no trace means no chart sentence at all', () {
    // Silence, not an apology: explaining an absent attachment draws attention
    // to a gap the recipient would never otherwise have noticed.
    final ComplaintDraft draft = template.render(
      snap: _snap(trace: false),
      profile: _profile,
      settings: settings,
    );

    expect(draft.body, isNot(contains('Attached: a chart')));
    expect(draft.attachmentPaths, isEmpty);
  });

  test('the chart is attached ahead of the audio clip', () {
    // Order matters to mail clients that preview only the first attachment,
    // and the chart is the one worth previewing.
    final ComplaintDraft draft = template.render(
      snap: _snap(clipPath: '/tmp/snap-1.wav', attachClip: true),
      profile: _profile,
      settings: settings,
      chartPath: '/tmp/snap-1-level.png',
    );

    expect(draft.attachmentPaths,
        <String>['/tmp/snap-1-level.png', '/tmp/snap-1.wav']);
  });
}
