import 'profile.dart';

class AppSettings {
  const AppSettings({
    this.attachClipByDefault = true,
    this.openSkyClientId = '',
    this.openSkyClientSecret = '',
    this.recipientSets = const <RecipientSet>[RecipientSet.defaultSet],
    this.activeRecipientSetId = 'default',
    this.recipientSeed = currentRecipientSeed,
    this.templateSubject = defaultSubject,
    this.templateBody = defaultBody,
  });

  /// Whether the saved clip is attached to the complaint unless the user says
  /// otherwise. On, because the recording is the evidence.
  ///
  /// A clip is always saved — it is the one part of a recording that cannot be
  /// recovered later, and it never leaves the phone on its own. Attaching it is
  /// still the user's decision, but it is now the decision they have to
  /// *unmake* rather than remember to make: a letter that says an aircraft was
  /// 30 dB over the background reads very differently with the thirty seconds
  /// of it playable underneath, and a complaint sent without the sound cannot
  /// have the sound added afterwards.
  ///
  /// The counter-argument — a microphone in a residential street picks up the
  /// neighbours as readily as the aeroplane — is answered on the review screen,
  /// where the clip is playable and one tap off, not by leaving it off for
  /// everyone by default.
  ///
  /// Deliberately not migrated onto installs that already stored `false`:
  /// nothing here can tell a saved refusal from an untouched default, and
  /// switching someone's audio on without asking is the one mistake this app
  /// must not make.
  final bool attachClipByDefault;

  /// BCC the complainant's own address, so their sent record survives even if
  /// their mail client does not keep one.

  final String openSkyClientId;
  final String openSkyClientSecret;

  final List<RecipientSet> recipientSets;
  final String activeRecipientSetId;

  /// Which round of built-in recipient defaults this settings record has been
  /// through. Bumped whenever a new default address is added, so that existing
  /// installs pick it up exactly once and never again.
  final int recipientSeed;

  static const int currentRecipientSeed = 1;

  final String templateSubject;
  final String templateBody;

  RecipientSet get activeRecipientSet => recipientSets.firstWhere(
        (RecipientSet s) => s.id == activeRecipientSetId,
        orElse: () => recipientSets.isEmpty
            ? RecipientSet.defaultSet
            : recipientSets.first,
      );

  AppSettings copyWith({
    bool? attachClipByDefault,
    String? openSkyClientId,
    String? openSkyClientSecret,
    List<RecipientSet>? recipientSets,
    String? activeRecipientSetId,
    int? recipientSeed,
    String? templateSubject,
    String? templateBody,
  }) =>
      AppSettings(
        attachClipByDefault: attachClipByDefault ?? this.attachClipByDefault,
        openSkyClientId: openSkyClientId ?? this.openSkyClientId,
        openSkyClientSecret: openSkyClientSecret ?? this.openSkyClientSecret,
        recipientSets: recipientSets ?? this.recipientSets,
        activeRecipientSetId: activeRecipientSetId ?? this.activeRecipientSetId,
        recipientSeed: recipientSeed ?? this.recipientSeed,
        templateSubject: templateSubject ?? this.templateSubject,
        templateBody: templateBody ?? this.templateBody,
      );

  /// See the note on [ComplainantProfile.==]: without value equality the
  /// settings screen rebuilds every consumer on every keystroke.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          other.attachClipByDefault == attachClipByDefault &&
          other.openSkyClientId == openSkyClientId &&
          other.openSkyClientSecret == openSkyClientSecret &&
          listEquals(other.recipientSets, recipientSets) &&
          other.activeRecipientSetId == activeRecipientSetId &&
          other.recipientSeed == recipientSeed &&
          other.templateSubject == templateSubject &&
          other.templateBody == templateBody;

  @override
  int get hashCode => Object.hash(
        attachClipByDefault,
        openSkyClientId,
        openSkyClientSecret,
        Object.hashAll(recipientSets),
        activeRecipientSetId,
        recipientSeed,
        templateSubject,
        templateBody,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'attachClipByDefault': attachClipByDefault,
        'openSkyClientId': openSkyClientId,
        'openSkyClientSecret': openSkyClientSecret,
        'recipientSets':
            recipientSets.map((RecipientSet s) => s.toJson()).toList(),
        'activeRecipientSetId': activeRecipientSetId,
        'recipientSeed': recipientSeed,
        'templateSubject': templateSubject,
        'templateBody': templateBody,
      };

  static AppSettings fromJson(Map<String, Object?> json) {
    final int seed = (json['recipientSeed'] as num?)?.toInt() ?? 0;
    List<RecipientSet> sets =
        ((json['recipientSets'] as List<Object?>?) ?? const <Object?>[])
            .cast<Map<String, Object?>>()
            .map(RecipientSet.fromJson)
            .toList();
    if (seed < 1) {
      sets = sets.map(RecipientSet.seedGroupCc).toList();
    }
    return AppSettings(
      attachClipByDefault: json['attachClipByDefault'] as bool? ?? true,
      openSkyClientId: json['openSkyClientId'] as String? ?? '',
      openSkyClientSecret: json['openSkyClientSecret'] as String? ?? '',
      recipientSets:
          sets.isEmpty ? const <RecipientSet>[RecipientSet.defaultSet] : sets,
      activeRecipientSetId:
          json['activeRecipientSetId'] as String? ?? 'default',
      recipientSeed: currentRecipientSeed,
      templateSubject: json['templateSubject'] as String? ?? defaultSubject,
      templateBody: _currentBody(json['templateBody'] as String?),
    );
  }

  /// Earlier default letters, kept only so that a user who never edited theirs
  /// is moved onto the current one.
  ///
  /// The template is written to storage the first time settings are saved, so
  /// by the time a token is added or a section rewritten, every existing
  /// install is holding a frozen copy of whatever the default was that day --
  /// which is how a handset ends up mailing a table of zeroes long after the
  /// app stopped generating one. Matching the exact text is the only safe
  /// upgrade: an edited letter matches none of these and is left alone, which
  /// is the point. The letter is the user's, and a default that silently
  /// reapplies itself is not a default.
  static const List<String> _legacyDefaultBodies = <String>[
    '''
Dear Sir or Madam,

I am writing to complain about aircraft noise affecting my home.

{atAGlance}

{locationLine}

{aircraftBlock}

{measurementBlock}

{measurementNote}

{chartNote}

{markedPeakNote}

{clipNote}

This aircraft was clearly audible inside my home and disrupted my use of it.
I would be grateful if you would log this complaint and confirm receipt.

Yours faithfully,

{name}
{address}
{email}{phoneLine}
''',
    '''
Dear Sir or Madam,

I am writing to complain about aircraft noise affecting my home.

Date and time: {datetimeLong}
{locationLine}

{aircraftBlock}

{measurementBlock}

{measurementNote}

{chartNote}

{markedPeakNote}

{clipNote}

This aircraft was clearly audible inside my home and disrupted my use of it.
I would be grateful if you would log this complaint and confirm receipt.

Yours faithfully,

{name}
{address}
{email}{phoneLine}
''',
    '''
Dear Sir or Madam,

I am writing to complain about aircraft noise affecting my home.

Date and time: {datetimeLong}
{locationLine}

{aircraftBlock}

Measured sound level
  Maximum (LAmax, fast): {laMax} dB(A)
  Equivalent level over the event (LAeq, {eventSeconds} s): {laEq} dB(A)
  Background before the event (LA90): {ambient} dB(A)
  Rise above background: {excess} dB

{measurementNote}

{chartNote}

{markedPeakNote}

{clipNote}

This aircraft was clearly audible inside my home and disrupted my use of it.
I would be grateful if you would log this complaint and confirm receipt.

Yours faithfully,

{name}
{address}
{email}{phoneLine}
''',
    '''
Dear Sir or Madam,

I am writing to complain about aircraft noise affecting my home.

Date and time: {datetimeLong}
{locationLine}

{aircraftBlock}

Measured sound level
  Maximum (LAmax, fast): {laMax} dB(A)
  Equivalent level over the event (LAeq, {eventSeconds} s): {laEq} dB(A)
  Background before the event (LA90): {ambient} dB(A)
  Rise above background: {excess} dB

{measurementNote}

{chartNote}

{clipNote}

This aircraft was clearly audible inside my home and disrupted my use of it.
I would be grateful if you would log this complaint and confirm receipt.

Yours faithfully,

{name}
{address}
{email}{phoneLine}
''',
    '''
Dear Sir or Madam,

I am writing to complain about aircraft noise affecting my home.

{atAGlance}

{locationLine}

{aircraftBlock}

{measurementBlock}

{measurementNote}

{chartNote}

{markedPeakNote}

{clipNote}

This aircraft was clearly audible inside my home and disrupted my use of it.
I would be grateful if you would log this complaint and confirm receipt.

Yours faithfully,

{name}
{address}{phoneLine}
''',
  ];

  /// The stored letter, upgraded if it is an untouched older default.
  static String _currentBody(String? stored) {
    if (stored == null) return defaultBody;
    return _legacyDefaultBodies.contains(stored) ? defaultBody : stored;
  }

  static const String defaultSubject =
      'Aircraft noise complaint — {flight} over {postcode} at {time}';

  /// Tokens are documented in `ComplaintTemplate.tokenHelp`.
  static const String defaultBody = '''
Dear Sir or Madam,

I am writing to complain about aircraft noise affecting my home.

{atAGlance}

{locationLine}

{aircraftBlock}

{measurementBlock}

{measurementNote}

{chartNote}

{mapNote}

{markedPeakNote}

{clipNote}

This aircraft was clearly audible inside my home and disrupted my use of it.
I would be grateful if you would log this complaint and confirm receipt.

Yours faithfully,

{name}
{address}{phoneLine}
''';
}
