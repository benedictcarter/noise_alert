import 'dart:io';

import 'package:flutter_email_sender/flutter_email_sender.dart';
import 'package:url_launcher/url_launcher.dart';

import 'complaint_template.dart';

enum MailResult {
  /// The composer opened. Whether the user actually pressed send is not
  /// something either platform tells us.
  composerOpened,

  /// Fell back to a mailto: link, so any clip could not be attached.
  composerOpenedWithoutAttachment,

  /// No mail app could be opened at all.
  failed,
}

class MailOutcome {
  const MailOutcome(this.result, {this.detail});

  final MailResult result;
  final String? detail;

  bool get opened => result != MailResult.failed;
}

/// Hands a complaint to the device's own mail app.
///
/// This is the whole GDPR story: the message is sent from the user's own
/// account by the user's own mail client. Nothing this app runs ever holds
/// somebody else's personal data, so there is no controller and no database to
/// answer for.
class MailSender {
  const MailSender();

  Future<MailOutcome> send(ComplaintDraft draft) async {
    final List<String> attachments = draft.attachmentPaths
        .where((String path) => File(path).existsSync())
        .toList();

    try {
      await FlutterEmailSender.send(
        Email(
          subject: draft.subject,
          body: draft.body,
          recipients: draft.to,
          cc: draft.cc,
          bcc: draft.bcc,
          attachmentPaths: attachments,
          isHTML: false,
        ),
      );
      return const MailOutcome(MailResult.composerOpened);
    } catch (error) {
      // Typically "no email client configured" on Android, or a device with no
      // Mail account on iOS. mailto: often still resolves to a webmail handler.
      final MailOutcome fallback = await _sendViaMailto(draft);
      if (fallback.opened) return fallback;
      return MailOutcome(MailResult.failed, detail: '$error');
    }
  }

  Future<MailOutcome> _sendViaMailto(ComplaintDraft draft) async {
    final Uri uri = buildMailtoUri(draft);
    try {
      final bool launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) return const MailOutcome(MailResult.failed);
      return MailOutcome(
        draft.attachmentPaths.isEmpty
            ? MailResult.composerOpened
            : MailResult.composerOpenedWithoutAttachment,
        detail: draft.attachmentPaths.isEmpty
            ? null
            : 'The audio clip could not be attached automatically — share it '
                'separately from the history screen.',
      );
    } catch (error) {
      return MailOutcome(MailResult.failed, detail: '$error');
    }
  }

  /// Built by hand rather than with [Uri.https]-style helpers: `mailto` needs
  /// the query percent-encoded but the recipient list left as a bare path, and
  /// `Uri`'s own encoding of a comma-separated address list is not portable
  /// across mail clients.
  static Uri buildMailtoUri(ComplaintDraft draft) {
    final Map<String, String> params = <String, String>{
      if (draft.cc.isNotEmpty) 'cc': draft.cc.join(','),
      if (draft.bcc.isNotEmpty) 'bcc': draft.bcc.join(','),
      'subject': draft.subject,
      'body': draft.body,
    };
    final String query = params.entries
        .map((MapEntry<String, String> e) =>
            '${e.key}=${Uri.encodeComponent(e.value)}')
        .join('&');
    return Uri.parse('mailto:${draft.to.join(',')}?$query');
  }
}
