import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:noise_alert/snap/snap.dart';
import 'package:noise_alert/providers.dart';
import 'package:noise_alert/ui/review/review_screen.dart';

class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  static final DateFormat _dayFormat = DateFormat('EEE d MMM');
  static final DateFormat _timeFormat = DateFormat('HH:mm');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Snap>> snaps = ref.watch(snapsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('History')),
      body: snaps.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace _) =>
            Center(child: Text('Could not open your recordings: $e')),
        data: (List<Snap> list) {
          if (list.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Nothing recorded yet. Press the big green button when '
                  'an aircraft goes over.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.read(snapsProvider.notifier).refresh(),
            child: ListView.separated(
              itemCount: list.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (BuildContext context, int index) =>
                  _SnapTile(snap: list[index]),
            ),
          );
        },
      ),
    );
  }
}

class _SnapTile extends ConsumerWidget {
  const _SnapTile({required this.snap});

  final Snap snap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ThemeData theme = Theme.of(context);
    final String flight = snap.confirmedAircraft?.displayName ??
        (snap.unidentifiedAircraft
            ? 'Aircraft not identified'
            : snap.match?.best?.aircraft.displayName ?? 'No aircraft found');

    return Dismissible(
      key: ValueKey<String>(snap.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        color: theme.colorScheme.errorContainer,
        padding: const EdgeInsets.only(right: 20),
        child: Icon(Icons.delete_outline,
            color: theme.colorScheme.onErrorContainer),
      ),
      confirmDismiss: (_) async =>
          await showDialog<bool>(
            context: context,
            builder: (BuildContext context) => AlertDialog(
              title: const Text('Delete this recording?'),
              content: const Text(
                  'The measurement and the saved sound are removed from this '
                  'phone. This cannot be undone.'),
              actions: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Delete'),
                ),
              ],
            ),
          ) ??
          false,
      onDismissed: (_) async {
        await ref.read(snapServiceProvider).deleteSnap(snap);
        ref.read(snapsProvider.notifier).remove(snap.id);
      },
      child: ListTile(
        leading: CircleAvatar(
          child: Text(
            snap.metrics.laMaxDb.round().toString(),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ),
        title: Text(flight),
        subtitle: Text(
          '${HistoryScreen._dayFormat.format(snap.recordedAt)} at '
          '${HistoryScreen._timeFormat.format(snap.recordedAt)} · '
          '${_statusLabel(snap)}',
          style: theme.textTheme.bodySmall,
        ),
        trailing: snap.status == SnapStatus.sent
            ? const Icon(Icons.mark_email_read_outlined)
            : const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (BuildContext _) => ReviewScreen(snapId: snap.id),
          ),
        ),
      ),
    );
  }

  static String _statusLabel(Snap snap) {
    switch (snap.status) {
      case SnapStatus.unmatched:
        return 'no aircraft found';
      case SnapStatus.awaitingReview:
        return 'needs a look';
      case SnapStatus.confirmed:
        return 'ready to send';
      case SnapStatus.sent:
        // Neither platform reports whether the user actually pressed send, so
        // the wording stops at what we know.
        return 'handed to your mail app';
    }
  }
}
