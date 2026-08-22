import 'package:flutter/material.dart';

/// Shared furniture for the settings screens.
///
/// Split out when Settings became a menu of four screens rather than one long
/// scroll. Most of the people using this app are pensioners, and a single page
/// carrying their name, the council's address, a form letter and a pair of API
/// credentials reads as a wall of things that might be wrong. Four short pages
/// with plain titles read as four small jobs, three of which they never have
/// to open.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 6),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
      );
}

class Explainer extends StatelessWidget {
  const Explainer(this.text, {this.warning = false, super.key});

  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: warning
              ? theme.colorScheme.error
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// A text field that keeps its own controller so the cursor does not jump when
/// the provider writes the value back.
///
/// [external] is for a value the screen itself may change underneath the user:
/// the postcode lookup tidying "tw61ap" into "TW6 1AP", say. Passing it makes
/// the field adopt the new text; leaving it null means the field is the only
/// author of its own contents, which is the normal case.
class SettingsField extends StatefulWidget {
  const SettingsField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.sentences,
    this.maxLines = 1,
    this.obscure = false,
    this.external,
    super.key,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final int maxLines;
  final bool obscure;
  final String? external;

  @override
  State<SettingsField> createState() => _SettingsFieldState();
}

class _SettingsFieldState extends State<SettingsField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(SettingsField old) {
    super.didUpdateWidget(old);
    final String? incoming = widget.external;
    if (incoming != null && incoming != _controller.text) {
      _controller.value = TextEditingValue(
        text: incoming,
        selection: TextSelection.collapsed(offset: incoming.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: TextField(
          controller: _controller,
          onChanged: widget.onChanged,
          keyboardType: widget.keyboardType,
          textCapitalization: widget.textCapitalization,
          maxLines: widget.obscure ? 1 : widget.maxLines,
          obscureText: widget.obscure,
          style: Theme.of(context).textTheme.bodyLarge,
          decoration: InputDecoration(
            labelText: widget.label,
            helperText: widget.hint,
            helperMaxLines: 3,
            border: const OutlineInputBorder(),
          ),
        ),
      );
}
