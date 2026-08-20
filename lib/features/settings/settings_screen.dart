import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/mail/complaint_template.dart';
import '../../domain/profile.dart';
import '../../domain/settings.dart';
import '../../providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ComplainantProfile profile = ref.watch(profileProvider);
    final AppSettings settings = ref.watch(settingsProvider);
    final ProfileController profiles = ref.read(profileProvider.notifier);
    final SettingsController config = ref.read(settingsProvider.notifier);
    final RecipientSet recipients = settings.activeRecipientSet;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: <Widget>[
          const _SectionHeader('Your details'),
          const _Explainer(
            'Written into the letter and stored only on this phone. Nothing is '
            'uploaded anywhere: the email is sent by your own mail app, from '
            'your own account.',
          ),
          _Field(
            label: 'Full name',
            value: profile.fullName,
            onChanged: (String v) =>
                profiles.update(profile.copyWith(fullName: v)),
          ),
          _Field(
            label: 'Address line 1',
            value: profile.addressLine1,
            onChanged: (String v) =>
                profiles.update(profile.copyWith(addressLine1: v)),
          ),
          _Field(
            label: 'Address line 2',
            value: profile.addressLine2,
            onChanged: (String v) =>
                profiles.update(profile.copyWith(addressLine2: v)),
          ),
          _Field(
            label: 'Town',
            value: profile.town,
            onChanged: (String v) => profiles.update(profile.copyWith(town: v)),
          ),
          _Field(
            label: 'Postcode',
            value: profile.postcode,
            textCapitalization: TextCapitalization.characters,
            onChanged: (String v) =>
                profiles.update(profile.copyWith(postcode: v)),
          ),
          _Field(
            label: 'Your email address',
            value: profile.email,
            keyboardType: TextInputType.emailAddress,
            onChanged: (String v) =>
                profiles.update(profile.copyWith(email: v)),
          ),
          _Field(
            label: 'Phone (optional)',
            value: profile.phone,
            keyboardType: TextInputType.phone,
            onChanged: (String v) =>
                profiles.update(profile.copyWith(phone: v)),
          ),
          if (!profile.isComplete)
            const _Explainer(
              'Name, postcode and email are required before a complaint can be '
              'composed.',
              warning: true,
            ),
          const _SectionHeader('Who complaints go to'),
          _Field(
            label: 'To (comma separated)',
            value: recipients.to.join(', '),
            onChanged: (String v) => config.edit(
              (AppSettings s) => s.copyWith(
                recipientSets: _replace(s, recipients.copyWith(to: _split(v))),
              ),
            ),
          ),
          _Field(
            label: 'Cc',
            value: recipients.cc.join(', '),
            onChanged: (String v) => config.edit(
              (AppSettings s) => s.copyWith(
                recipientSets: _replace(s, recipients.copyWith(cc: _split(v))),
              ),
            ),
          ),
          _Field(
            label: 'Bcc',
            value: recipients.bcc.join(', '),
            onChanged: (String v) => config.edit(
              (AppSettings s) => s.copyWith(
                recipientSets: _replace(s, recipients.copyWith(bcc: _split(v))),
              ),
            ),
          ),
          const _Explainer(
            'A Bcc to your flight-watch group is how the group builds a durable '
            'record without anyone having to run a database of members\' '
            'personal details.',
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.bccSelf,
            onChanged: (bool v) =>
                config.edit((AppSettings s) => s.copyWith(bccSelf: v)),
            title: const Text('Bcc myself'),
            subtitle: const Text(
                'Keeps your own copy even if your mail app does not.'),
          ),
          const _SectionHeader('Recordings'),
          const _Explainer(
            'Every recording keeps its loudest '
            '${AudioConfig.clipSeconds} s as an audio clip on this phone. '
            'Nothing is uploaded, and nothing is sent unless you attach it.',
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: settings.attachClipByDefault,
            onChanged: (bool v) => config
                .edit((AppSettings s) => s.copyWith(attachClipByDefault: v)),
            title: const Text('Attach the clip by default'),
            subtitle: const Text(
              'You can still play it back and change your mind on each '
              'recording.',
            ),
          ),
          const _SectionHeader('Flight data'),
          const _Explainer(
            'Live matching uses adsb.lol and airplanes.live, which need no '
            'account. OpenSky credentials are optional and only used to look up '
            'a snap taken while offline — their free history reaches one hour '
            'back.',
          ),
          _Field(
            label: 'OpenSky client ID',
            value: settings.openSkyClientId,
            onChanged: (String v) => config
                .edit((AppSettings s) => s.copyWith(openSkyClientId: v.trim())),
          ),
          _Field(
            label: 'OpenSky client secret',
            value: settings.openSkyClientSecret,
            obscure: true,
            onChanged: (String v) => config.edit(
                (AppSettings s) => s.copyWith(openSkyClientSecret: v.trim())),
          ),
          const _SectionHeader('Letter'),
          _Field(
            label: 'Subject',
            value: settings.templateSubject,
            onChanged: (String v) =>
                config.edit((AppSettings s) => s.copyWith(templateSubject: v)),
          ),
          _Field(
            label: 'Body',
            value: settings.templateBody,
            maxLines: 16,
            onChanged: (String v) =>
                config.edit((AppSettings s) => s.copyWith(templateBody: v)),
          ),
          TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (BuildContext context) => AlertDialog(
                title: const Text('Template tokens'),
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
            child: const Text('Which tokens can I use?'),
          ),
          TextButton(
            onPressed: () => config.edit(
              (AppSettings s) => s.copyWith(
                templateSubject: AppSettings.defaultSubject,
                templateBody: AppSettings.defaultBody,
              ),
            ),
            child: const Text('Reset the letter to the default wording'),
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 28, bottom: 4),
        child: Text(
          title.toUpperCase(),
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                letterSpacing: 1.2,
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
      );
}

class _Explainer extends StatelessWidget {
  const _Explainer(this.text, {this.warning = false});

  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: warning ? theme.colorScheme.error : null,
        ),
      ),
    );
  }
}

/// A text field that keeps its own controller so the cursor does not jump when
/// the provider writes the value back.
class _Field extends StatefulWidget {
  const _Field({
    required this.label,
    required this.value,
    required this.onChanged,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.sentences,
    this.maxLines = 1,
    this.obscure = false,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final int maxLines;
  final bool obscure;

  @override
  State<_Field> createState() => _FieldState();
}

class _FieldState extends State<_Field> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: TextField(
          controller: _controller,
          onChanged: widget.onChanged,
          keyboardType: widget.keyboardType,
          textCapitalization: widget.textCapitalization,
          maxLines: widget.obscure ? 1 : widget.maxLines,
          obscureText: widget.obscure,
          decoration: InputDecoration(
            labelText: widget.label,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      );
}
