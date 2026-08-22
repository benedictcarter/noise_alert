import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:noise_alert/mic/config.dart';
import 'package:noise_alert/me/settings.dart';
import 'package:noise_alert/providers.dart';
import 'package:noise_alert/ui/settings/settings_widgets.dart';

/// Sound recordings, and the optional account for looking up older flights.
///
/// The two things on this page have nothing to do with each other beyond both
/// being things almost nobody needs to touch. Keeping them together keeps them
/// out of the way of the two screens that matter.
class RecordingsScreen extends ConsumerWidget {
  const RecordingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppSettings settings = ref.watch(settingsProvider);
    final SettingsController config = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Recordings and flights')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: <Widget>[
          const SectionHeader('The sound recording'),
          const Explainer(
            'Every time you record, the loudest '
            '${AudioConfig.clipSeconds} seconds are kept on this phone. '
            'Nothing is uploaded. The clip goes with your complaint unless you '
            'say otherwise. You can listen to it first, and take it off any '
            'single complaint on its review screen.',
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.attachClipByDefault,
            onChanged: (bool v) => config
                .edit((AppSettings s) => s.copyWith(attachClipByDefault: v)),
            title: const Text('Attach the sound to my complaints'),
            subtitle: const Text(
              'On, because the sound is the evidence. You can still change '
              'your mind on each one.',
            ),
          ),
          const SectionHeader('Looking up older flights'),
          const Explainer(
            'Normally the app finds the aircraft by itself and you need do '
            'nothing here. This is only for looking up a recording made when '
            'the phone had no signal. It needs a free OpenSky Network '
            'account, and it can reach about an hour back.',
          ),
          SettingsField(
            label: 'OpenSky client ID (optional)',
            value: settings.openSkyClientId,
            textCapitalization: TextCapitalization.none,
            onChanged: (String v) => config
                .edit((AppSettings s) => s.copyWith(openSkyClientId: v.trim())),
          ),
          SettingsField(
            label: 'OpenSky client secret (optional)',
            value: settings.openSkyClientSecret,
            obscure: true,
            textCapitalization: TextCapitalization.none,
            onChanged: (String v) => config.edit(
                (AppSettings s) => s.copyWith(openSkyClientSecret: v.trim())),
          ),
        ],
      ),
    );
  }
}
