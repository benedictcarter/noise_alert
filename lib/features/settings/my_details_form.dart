import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/postcode/postcode_service.dart';
import '../../domain/profile.dart';
import '../../providers.dart';
import 'settings_widgets.dart';

/// Name, postcode, and nothing that is not needed.
///
/// Used twice: as the first thing a new user sees, and as the My details
/// screen afterwards. One widget rather than two so the wording cannot drift
/// apart, and so a field added here appears in both places.
///
/// Only the name and the postcode are asked for as required. Everything else
/// is marked optional in the label itself, because "optional" in small grey
/// text under a box is not read by someone who is already unsure whether they
/// are allowed to be doing this.
class MyDetailsForm extends ConsumerStatefulWidget {
  const MyDetailsForm({super.key});

  @override
  ConsumerState<MyDetailsForm> createState() => _MyDetailsFormState();
}

enum _Lookup { idle, checking, found, failed }

class _MyDetailsFormState extends ConsumerState<MyDetailsForm> {
  _Lookup _lookup = _Lookup.idle;
  String? _foundTown;

  /// Set only when the lookup tidies the postcode, so the text field adopts
  /// the corrected spelling without fighting the user for the cursor.
  String? _postcodeOverride;
  String? _townOverride;

  Future<void> _checkPostcode() async {
    final ComplainantProfile profile = ref.read(profileProvider);
    setState(() {
      _lookup = _Lookup.checking;
      _foundTown = null;
    });

    final PostcodeResult? result =
        await ref.read(postcodeServiceProvider).lookup(profile.postcode);
    if (!mounted) return;

    if (result == null) {
      setState(() => _lookup = _Lookup.failed);
      return;
    }

    ref.read(profileProvider.notifier).update(
          profile.copyWith(postcode: result.postcode, town: result.town),
        );
    setState(() {
      _lookup = _Lookup.found;
      _foundTown = result.town;
      _postcodeOverride = result.postcode;
      _townOverride = result.town;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ComplainantProfile profile = ref.watch(profileProvider);
    final ProfileController profiles = ref.read(profileProvider.notifier);
    final bool canCheck = PostcodeService.looksLikeAPostcode(profile.postcode);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SettingsField(
          label: 'Your name',
          value: profile.fullName,
          textCapitalization: TextCapitalization.words,
          hint: 'This goes at the bottom of your complaint.',
          onChanged: (String v) =>
              profiles.update(profile.copyWith(fullName: v)),
        ),
        SettingsField(
          label: 'Your postcode',
          value: profile.postcode,
          external: _postcodeOverride,
          textCapitalization: TextCapitalization.characters,
          hint: 'This is how the airport knows which homes are affected.',
          onChanged: (String v) {
            if (_lookup != _Lookup.idle) {
              setState(() {
                _lookup = _Lookup.idle;
                _foundTown = null;
              });
            }
            profiles.update(profile.copyWith(postcode: v));
          },
        ),
        const SizedBox(height: 4),
        _PostcodeCheck(
          state: _lookup,
          town: _foundTown,
          onPressed:
              canCheck && _lookup != _Lookup.checking ? _checkPostcode : null,
        ),
        SettingsField(
          label: 'Town',
          value: profile.town,
          external: _townOverride,
          textCapitalization: TextCapitalization.words,
          onChanged: (String v) => profiles.update(profile.copyWith(town: v)),
        ),
        SettingsField(
          label: 'House number and street (optional)',
          value: profile.addressLine1,
          textCapitalization: TextCapitalization.words,
          hint: 'Only if you want to. Your postcode is enough.',
          onChanged: (String v) =>
              profiles.update(profile.copyWith(addressLine1: v)),
        ),
        SettingsField(
          label: 'Phone number (optional)',
          value: profile.phone,
          keyboardType: TextInputType.phone,
          onChanged: (String v) => profiles.update(profile.copyWith(phone: v)),
        ),
      ],
    );
  }
}

/// The lookup button and whatever it last had to say.
///
/// A failure is reported as a shrug, not an error. The postcode is not being
/// validated (the user is being saved some typing) so a service that is down
/// must not read as the user having got something wrong.
class _PostcodeCheck extends StatelessWidget {
  const _PostcodeCheck({
    required this.state,
    required this.town,
    required this.onPressed,
  });

  final _Lookup state;
  final String? town;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    final Widget? message;
    switch (state) {
      case _Lookup.found:
        message = Row(
          children: <Widget>[
            const Icon(Icons.check_circle, size: 20, color: Colors.green),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Found it: $town. We have filled in the town for you.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        );
      case _Lookup.failed:
        message = Text(
          'We could not check that just now. It does not matter. Type your '
          'town below and carry on.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        );
      case _Lookup.idle:
      case _Lookup.checking:
        message = null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: onPressed,
            icon: state == _Lookup.checking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search),
            label: Text(
              state == _Lookup.checking ? 'Checking…' : 'Look up my town',
            ),
          ),
        ),
        if (message != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: message,
          ),
        const SizedBox(height: 4),
      ],
    );
  }
}
