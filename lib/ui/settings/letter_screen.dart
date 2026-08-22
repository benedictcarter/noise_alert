import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:noise_alert/letter/template.dart';
import 'package:noise_alert/me/profile.dart';
import 'package:noise_alert/me/settings.dart';
import 'package:noise_alert/providers.dart';
import 'package:noise_alert/ui/settings/settings_widgets.dart';

/// Who the complaint goes to, and what it says.
///
/// Deliberately the screen nobody has to open. It ships working: a recipient
/// list and a letter that reads properly on the day the app is installed. Most
/// users should never come here, and the wording assumes that whoever does has
/// a reason.
class LetterScreen extends ConsumerWidget {
  const LetterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppSettings settings = ref.watch(settingsProvider);
    final SettingsController config = ref.read(settingsProvider.notifier);
    final RecipientSet recipients = settings.activeRecipientSet;

    return Scaffold(
      appBar: AppBar(title: const Text('The complaint email')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: <Widget>[
          const Explainer(
            'This is already set up. You only need to change it if you want '
            'your complaints to go somewhere else, or to word them yourself.',
          ),
          const SectionHeader('Who it goes to'),
          SettingsField(
            label: 'To',
            value: recipients.to.join(', '),
            keyboardType: TextInputType.emailAddress,
            textCapitalization: TextCapitalization.none,
            hint: 'Separate several addresses with commas.',
            onChanged: (String v) => config.edit(
              (AppSettings s) => s.copyWith(
                recipientSets: _replace(s, recipients.copyWith(to: _split(v))),
              ),
            ),
          ),
          SettingsField(
            label: 'Cc',
            value: recipients.cc.join(', '),
            keyboardType: TextInputType.emailAddress,
            textCapitalization: TextCapitalization.none,
            onChanged: (String v) => config.edit(
              (AppSettings s) => s.copyWith(
                recipientSets: _replace(s, recipients.copyWith(cc: _split(v))),
              ),
            ),
          ),
          SettingsField(
            label: 'Bcc',
            value: recipients.bcc.join(', '),
            keyboardType: TextInputType.emailAddress,
            textCapitalization: TextCapitalization.none,
            onChanged: (String v) => config.edit(
              (AppSettings s) => s.copyWith(
                recipientSets: _replace(s, recipients.copyWith(bcc: _split(v))),
              ),
            ),
          ),
          const SectionHeader('What it says'),
          SettingsField(
            label: 'Subject',
            value: settings.templateSubject,
            onChanged: (String v) =>
                config.edit((AppSettings s) => s.copyWith(templateSubject: v)),
          ),
          SettingsField(
            label: 'Letter',
            value: settings.templateBody,
            maxLines: 16,
            onChanged: (String v) =>
                config.edit((AppSettings s) => s.copyWith(templateBody: v)),
          ),
          const Explainer(
            'The words in curly brackets are filled in for each complaint: '
            'the time, the aircraft, the sound levels.',
          ),
          TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (BuildContext context) => AlertDialog(
                title: const Text('What you can put in curly brackets'),
                content: const SingleChildScrollView(
                  child: Text(ComplaintTemplate.tokenHelp),
                ),
                actions: <Widget>[
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
            child: const Text('Show me the list'),
          ),
          TextButton(
            onPressed: () => config.edit(
              (AppSettings s) => s.copyWith(
                templateSubject: AppSettings.defaultSubject,
                templateBody: AppSettings.defaultBody,
              ),
            ),
            child: const Text('Put the wording back to how it was'),
          ),
        ],
      ),
    );
  }

  static List<String> _split(String value) => value
      .split(RegExp(r'[,;]'))
      .map((String s) => s.trim())
      .where((String s) => s.isNotEmpty)
      .toList();

  static List<RecipientSet> _replace(
          AppSettings settings, RecipientSet updated) =>
      settings.recipientSets
          .map((RecipientSet s) => s.id == updated.id ? updated : s)
          .toList();
}
