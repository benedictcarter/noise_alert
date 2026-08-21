import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/profile.dart';
import '../../providers.dart';
import '../settings/my_details_form.dart';

/// The first thing a new user sees.
///
/// Shown instead of the app, not on top of it, until there is a name and a
/// postcode. That is not a nag: without them there is no complaint to send,
/// and finding that out at the end (after standing in the garden recording an
/// aeroplane) is the worst possible moment to be sent to a settings screen.
///
/// It is also why the microphone is not touched yet. The record screen asks
/// for permission the instant it is built, and a permission dialog landing on
/// top of a form the user has not read is how people end up tapping Deny to
/// make something go away.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final ComplainantProfile profile = ref.watch(profileProvider);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          children: <Widget>[
            Text(
              'Flightpath Watch Report',
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Text(
              'When an aircraft is too loud, press one button. This app '
              'measures the noise, works out which aeroplane it was, and '
              'writes the complaint for you.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 12),
            Text(
              'First, two things it needs to know about you. They stay on '
              'this phone.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            const MyDetailsForm(),
            const SizedBox(height: 28),
            FilledButton(
              onPressed: profile.isComplete
                  ? () => ref.read(onboardedProvider.notifier).state = true
                  : null,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
                textStyle: theme.textTheme.titleMedium,
              ),
              child: const Text('Start'),
            ),
            const SizedBox(height: 12),
            Text(
              profile.isComplete
                  ? 'You can change any of this later under Settings.'
                  : 'Fill in your name and postcode to carry on.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
