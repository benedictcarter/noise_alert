import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/profile.dart';
import '../../providers.dart';
import 'letter_screen.dart';
import 'my_details_screen.dart';
import 'recordings_screen.dart';

/// A menu, not a form.
///
/// This used to be one page carrying the user's name and address, the
/// council's email addresses, the full text of the form letter and a pair of
/// API credentials, in that order, in one scroll. For the audience this app is
/// for (largely pensioners, opening it because a jet has just gone over)
/// that reads as a list of things they are expected to understand.
///
/// Three rows instead. The first is the only one most people ever need, and it
/// says so if it is not filled in yet.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ComplainantProfile profile = ref.watch(profileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: <Widget>[
          _Row(
            icon: Icons.person_outline,
            title: 'My details',
            subtitle: profile.isComplete
                ? _describe(profile)
                : 'Your name and postcode are still needed',
            highlight: !profile.isComplete,
            builder: (_) => const MyDetailsScreen(),
          ),
          _Row(
            icon: Icons.mail_outline,
            title: 'The complaint email',
            subtitle: 'Who it goes to, and what it says',
            builder: (_) => const LetterScreen(),
          ),
          _Row(
            icon: Icons.tune,
            title: 'Recordings and flights',
            subtitle: 'Whether to attach the sound, and older flight lookups',
            builder: (_) => const RecordingsScreen(),
          ),
        ],
      ),
    );
  }

  static String _describe(ComplainantProfile profile) {
    final String where = profile.town.trim().isEmpty
        ? profile.postcode.trim()
        : '${profile.town.trim()}, ${profile.postcode.trim()}';
    return '${profile.fullName.trim()}, $where';
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.builder,
    this.highlight = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final WidgetBuilder builder;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Icon(
        icon,
        size: 30,
        color: highlight ? theme.colorScheme.error : theme.colorScheme.primary,
      ),
      title: Text(title, style: theme.textTheme.titleMedium),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text(
          subtitle,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: highlight
                ? theme.colorScheme.error
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: builder),
      ),
    );
  }
}
