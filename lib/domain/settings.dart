import '../core/constants.dart';
import 'profile.dart';

class AppSettings {
  const AppSettings({
    this.calibrationOffsetDb = CalibrationDefaults.fullScaleDbSpl,
    this.calibrated = false,
    this.attachClipByDefault = false,
    this.bccSelf = true,
    this.openSkyClientId = '',
    this.openSkyClientSecret = '',
    this.recipientSets = const <RecipientSet>[RecipientSet.defaultSet],
    this.activeRecipientSetId = 'default',
    this.recipientSeed = currentRecipientSeed,
    this.templateSubject = defaultSubject,
    this.templateBody = defaultBody,
  });

  /// dB SPL that a full-scale signal corresponds to on this handset.
  final double calibrationOffsetDb;

  /// True once the user has entered a reference reading. Until then every
  /// complaint says the figure is uncalibrated.
  final bool calibrated;

  /// Whether the saved clip is attached to the complaint unless the user says
  /// otherwise.
  ///
  /// A clip is always saved — it is the one part of a recording that cannot be
  /// recovered later, and it never leaves the phone on its own. Sending it is a
  /// separate decision, made on the review screen with the clip in front of
  /// you, because a microphone in a residential street picks up the neighbours
  /// as readily as the aeroplane.
  final bool attachClipByDefault;

  /// BCC the complainant's own address, so their sent record survives even if
  /// their mail client does not keep one.
  final bool bccSelf;

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
    double? calibrationOffsetDb,
    bool? calibrated,
    bool? attachClipByDefault,
    bool? bccSelf,
    String? openSkyClientId,
    String? openSkyClientSecret,
    List<RecipientSet>? recipientSets,
    String? activeRecipientSetId,
    int? recipientSeed,
    String? templateSubject,
    String? templateBody,
  }) =>
      AppSettings(
        calibrationOffsetDb: calibrationOffsetDb ?? this.calibrationOffsetDb,
        calibrated: calibrated ?? this.calibrated,
        attachClipByDefault: attachClipByDefault ?? this.attachClipByDefault,
        bccSelf: bccSelf ?? this.bccSelf,
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
          other.calibrationOffsetDb == calibrationOffsetDb &&
          other.calibrated == calibrated &&
          other.attachClipByDefault == attachClipByDefault &&
          other.bccSelf == bccSelf &&
          other.openSkyClientId == openSkyClientId &&
          other.openSkyClientSecret == openSkyClientSecret &&
          listEquals(other.recipientSets, recipientSets) &&
          other.activeRecipientSetId == activeRecipientSetId &&
          other.recipientSeed == recipientSeed &&
          other.templateSubject == templateSubject &&
          other.templateBody == templateBody;

  @override
  int get hashCode => Object.hash(
        calibrationOffsetDb,
        calibrated,
        attachClipByDefault,
        bccSelf,
        openSkyClientId,
        openSkyClientSecret,
        Object.hashAll(recipientSets),
        activeRecipientSetId,
        recipientSeed,
        templateSubject,
        templateBody,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'calibrationOffsetDb': calibrationOffsetDb,
        'calibrated': calibrated,
        'attachClipByDefault': attachClipByDefault,
        'bccSelf': bccSelf,
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
      calibrationOffsetDb: (json['calibrationOffsetDb'] as num?)?.toDouble() ??
          CalibrationDefaults.fullScaleDbSpl,
      calibrated: json['calibrated'] as bool? ?? false,
      attachClipByDefault: json['attachClipByDefault'] as bool? ?? false,
      bccSelf: json['bccSelf'] as bool? ?? true,
      openSkyClientId: json['openSkyClientId'] as String? ?? '',
      openSkyClientSecret: json['openSkyClientSecret'] as String? ?? '',
      recipientSets:
          sets.isEmpty ? const <RecipientSet>[RecipientSet.defaultSet] : sets,
      activeRecipientSetId:
          json['activeRecipientSetId'] as String? ?? 'default',
      recipientSeed: currentRecipientSeed,
      templateSubject: json['templateSubject'] as String? ?? defaultSubject,
      templateBody: json['templateBody'] as String? ?? defaultBody,
    );
  }

  static const String defaultSubject =
      'Aircraft noise complaint — {flight} over {postcode} at {time}';

  /// Tokens are documented in `ComplaintTemplate.tokenHelp`.
  static const String defaultBody = '''
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
''';
}
