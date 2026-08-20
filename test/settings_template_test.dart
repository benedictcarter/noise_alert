import 'package:flutter_test/flutter_test.dart';
import 'package:noise_alert/domain/settings.dart';

/// The exact default letter as it shipped before `{measurementBlock}` existed.
///
/// Hard-coded rather than derived, because that is the whole point of the
/// upgrade: it matches on text a released build wrote into a real database.
const String _b8Default = '''
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

void main() {
  group('the stored letter', () {
    test('an untouched older default is upgraded', () {
      // Otherwise a handset that saved its settings under b8 would go on
      // mailing a hard-coded table of zeroes for every unmeasured recording,
      // no matter what the app was rewritten to generate.
      final AppSettings settings = AppSettings.fromJson(<String, Object?>{
        'templateBody': _b8Default,
      });

      expect(settings.templateBody, AppSettings.defaultBody);
      expect(settings.templateBody, contains('{measurementBlock}'));
    });

    test('a letter the user edited is left exactly as they wrote it', () {
      final String mine = '$_b8Default\n\nPS: this is the fourth this week.';

      final AppSettings settings = AppSettings.fromJson(<String, Object?>{
        'templateBody': mine,
      });

      expect(settings.templateBody, mine);
    });

    test('no stored letter means the current default', () {
      final AppSettings settings = AppSettings.fromJson(<String, Object?>{});

      expect(settings.templateBody, AppSettings.defaultBody);
    });
  });
}
