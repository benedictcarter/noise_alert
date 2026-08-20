import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants.dart';
import '../../data/mail/complaint_template.dart';
import '../../data/mail/mail_sender.dart';
import '../../data/snap_service.dart';
import '../../domain/acoustic_metrics.dart';
import '../../domain/flight_match.dart';
import '../../domain/snap.dart';
import '../../providers.dart';
import '../chart/live_level_chart.dart';
import 'clip_player.dart';

/// Review one snap, confirm the aircraft, and hand the complaint to the mail
/// app.
///
/// Confirming the aircraft is a deliberate, explicit step. The matcher is good
/// but it is inferring which of several aeroplanes made a sound, and a
/// complaint that names the wrong flight is worse than one that names none.
class ReviewScreen extends ConsumerStatefulWidget {
  const ReviewScreen({super.key, required this.snapId});

  final String snapId;

  @override
  ConsumerState<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends ConsumerState<ReviewScreen> {
  /// Radio value standing for "no flight named". A sentinel keeps the aircraft
  /// choice and the unidentified choice in one radio group, so picking either
  /// clears the other.
  static const String _kUnidentified = '__unidentified__';

  static final DateFormat _timeFormat = DateFormat('EEE d MMM, HH:mm:ss');
  static final DateFormat _clockFormat = DateFormat('HH:mm:ss');

  /// null means "unidentified"; unset means nothing chosen yet.
  String? _selected;
  bool _unidentified = false;
  bool _initialised = false;
  bool _busy = false;

  void _initFrom(Snap snap) {
    if (_initialised) return;
    _initialised = true;
    _selected = snap.selectedIcao24;
    _unidentified = snap.unidentifiedAircraft;

    // Pre-tick the leader only when the geometry leaves little doubt. Below
    // that threshold the user picks from an unticked list.
    final FlightMatch? match = snap.match;
    if (_selected == null &&
        !_unidentified &&
        match != null &&
        match.isConfidentEnoughToPreselect) {
      _selected = match.best?.aircraft.icao24;
    }
  }

  /// Moves (or clears) the marker for the worst moment of the flyover.
  ///
  /// Written straight through rather than held in screen state: the marker ends
  /// up in the letter, and a drag that survived only until the screen was
  /// popped would be a claim the user thought they had made.
  Future<void> _setMarkedPeak(Snap snap, int? millis) async {
    final Snap updated =
        await ref.read(snapServiceProvider).setMarkedPeak(snap, millis);
    ref.read(snapsProvider.notifier).put(updated);
  }

  Future<void> _retryLookup(Snap snap) async {
    setState(() => _busy = true);
    try {
      final Snap updated =
          await ref.read(snapServiceProvider).resolveMatch(snap);
      ref.read(snapsProvider.notifier).put(updated);
      if (updated.match?.candidates.isEmpty ?? true) {
        _toast(updated.match?.note ??
            'Still no aircraft found for this time and place.');
      }
    } on Object catch (e) {
      _toast('Lookup failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _compose(Snap snap) async {
    setState(() => _busy = true);
    try {
      final SnapService service = ref.read(snapServiceProvider);
      final Snap confirmed = await service.confirmAircraft(
        snap,
        icao24: _unidentified ? null : _selected,
        unidentified: _unidentified,
      );
      ref.read(snapsProvider.notifier).put(confirmed);

      final MailOutcome outcome = await service.compose(confirmed);
      if (!mounted) return;

      if (!outcome.opened) {
        _toast(outcome.detail ?? 'No mail app could be opened.');
        return;
      }
      ref.read(snapsProvider.notifier).put(
            confirmed.copyWith(status: SnapStatus.sent, sentAt: DateTime.now()),
          );
      _toast(outcome.detail ?? 'Opened in your mail app — press send there.');
      Navigator.of(context).maybePop();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _previewLetter(Snap snap) async {
    final Snap confirmed = snap.copyWith(
      selectedIcao24: _unidentified ? null : _selected,
      clearSelection: _unidentified || _selected == null,
      unidentifiedAircraft: _unidentified,
    );
    final ComplaintDraft draft =
        await ref.read(snapServiceProvider).preview(confirmed);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        builder: (BuildContext context, ScrollController controller) =>
            ListView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          children: <Widget>[
            Text(
              'To: ${draft.to.join(', ')}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            if (draft.bcc.isNotEmpty)
              Text(
                'Bcc: ${draft.bcc.join(', ')}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            const SizedBox(height: 8),
            Text(draft.subject, style: Theme.of(context).textTheme.titleMedium),
            const Divider(height: 24),
            SelectableText(draft.body),
          ],
        ),
      ),
    );
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final Snap? snap = ref.watch(snapByIdProvider(widget.snapId));
    if (snap == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    _initFrom(snap);

    final ThemeData theme = Theme.of(context);
    final bool canSend = _unidentified || _selected != null;

    return Scaffold(
      appBar: AppBar(title: Text(_timeFormat.format(snap.recordedAt))),
      body: RadioGroup<String>(
        groupValue: _unidentified ? _kUnidentified : _selected,
        onChanged: (String? value) => setState(() {
          _unidentified = value == _kUnidentified;
          _selected = _unidentified ? null : value;
        }),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
          children: <Widget>[
            _MeasurementCard(
              snap: snap,
              onMarkChanged: (int? millis) => _setMarkedPeak(snap, millis),
            ),
            const SizedBox(height: 20),
            Text('Which aircraft was it?', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ..._buildCandidates(snap, theme),
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: _kUnidentified,
              title: const Text('None of these / unidentified'),
              subtitle: Text(
                'The complaint is still sent, with the measurement and location '
                'but no flight named.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            if (snap.match?.note != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child:
                    Text(snap.match!.note!, style: theme.textTheme.bodySmall),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _busy ? null : () => _retryLookup(snap),
                icon: const Icon(Icons.refresh),
                label: const Text('Look up again'),
              ),
            ),
            if (snap.clipPath != null) ...<Widget>[
              const Divider(height: 32),
              Text('Recording', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              ClipPlayer(
                path: snap.clipPath!,
                attach: snap.attachClip,
                onAttachChanged: (bool v) async {
                  final Snap updated = await ref
                      .read(snapServiceProvider)
                      .setAttachClip(snap, v);
                  ref.read(snapsProvider.notifier).put(updated);
                },
              ),
            ],
            const Divider(height: 32),
            TextFormField(
              initialValue: snap.notes,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                hintText: 'e.g. woke the children; third one this hour',
                border: OutlineInputBorder(),
              ),
              onChanged: (String v) =>
                  ref.read(snapServiceProvider).setNotes(snap, v),
            ),
            const SizedBox(height: 16),
            Text(
              '${_locationSummary(snap)}\n'
              'Device: ${snap.deviceModel}, ${snap.osVersion}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: _busy ? null : () => _previewLetter(snap),
                  child: const Text('Preview'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: (!canSend || _busy) ? null : () => _compose(snap),
                  icon: const Icon(Icons.mail_outline),
                  label: Text(_busy ? 'Working…' : 'Compose complaint'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildCandidates(Snap snap, ThemeData theme) {
    final FlightMatch? match = snap.match;
    if (match == null || match.candidates.isEmpty) {
      return <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'No aircraft could be matched to this event yet.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ];
    }

    return <Widget>[
      if (!match.isConfidentEnoughToPreselect)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'More than one aircraft fits — nothing has been chosen for you. '
            'Pick the one you saw or heard, or mark it unidentified.',
            style: theme.textTheme.bodySmall,
          ),
        ),
      for (final FlightCandidate c in match.candidates)
        RadioListTile<String>(
          contentPadding: EdgeInsets.zero,
          value: c.aircraft.icao24,
          title: Text(c.aircraft.displayName),
          subtitle: Text(
            '${c.heightAboveObserverFt.round()} ft above you · '
            '${c.elevationDegrees.round()}° up · '
            '${(c.slantRangeM / 1000).toStringAsFixed(1)} km away\n'
            'Closest at ${_clockFormat.format(c.closestApproachTime.toLocal())}'
            '${c.extrapolated ? ' (position estimated)' : ''}',
            style: theme.textTheme.bodySmall,
          ),
          isThreeLine: true,
        ),
    ];
  }
}

class _MeasurementCard extends StatelessWidget {
  const _MeasurementCard({required this.snap, required this.onMarkChanged});

  final Snap snap;

  /// Milliseconds into the trace, or null to go back to the measured maximum.
  final ValueChanged<int?> onMarkChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final AcousticMetrics metrics = snap.metrics;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: <Widget>[
                Text(
                  metrics.laMaxDb.toStringAsFixed(1),
                  style: theme.textTheme.displaySmall,
                ),
                const SizedBox(width: 8),
                Text('dB(A) max', style: theme.textTheme.titleMedium),
              ],
            ),
            if (metrics.hasTrace) ...<Widget>[
              const SizedBox(height: 12),
              // The same drawing that goes in the letter, so nothing about the
              // complaint is a surprise to the person sending it.
              EventLevelChart(
                levels: metrics.levelTrace,
                intervalMs: metrics.traceIntervalMs,
                pressAtSeconds: metrics.preRollSeconds,
                ambientDb: metrics.ambientLa90Db,
                markedAtSeconds: snap.markedPeakMs == null
                    ? null
                    : snap.markedPeakMs! / 1000,
                onMarkChanged: (double seconds) =>
                    onMarkChanged((seconds * 1000).round()),
              ),
              const SizedBox(height: 4),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      snap.markedPeakMs == null
                          ? 'Attached to the complaint as a picture. Tap or '
                              'drag on it to mark the worst moment — closest '
                              'approach, or whatever actually made the noise '
                              'unbearable.'
                          : 'Attached as a picture, with your marker on it. '
                              'The letter says the moment is yours, not the '
                              'meter\'s.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                  if (snap.markedPeakMs != null)
                    TextButton(
                      onPressed: () => onMarkChanged(null),
                      child: const Text('Clear'),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            _row(
              theme,
              'LAeq over the event',
              '${metrics.laEqDb.toStringAsFixed(1)} dB(A)',
            ),
            _row(
              theme,
              'Loudest 10 s (LAeq)',
              '${metrics.peakWindowLaEqDb.toStringAsFixed(1)} dB(A)',
            ),
            _row(
              theme,
              'Background (LA90)',
              metrics.ambientLa90Db == null
                  ? 'not measured'
                  : '${metrics.ambientLa90Db!.toStringAsFixed(1)} dB(A)',
            ),
            _row(
              theme,
              'Rise above background',
              metrics.excessOverAmbientDb == null
                  ? 'not measured'
                  : '${metrics.excessOverAmbientDb!.toStringAsFixed(1)} dB',
            ),
            if (snap.markedPeakMs != null)
              _row(
                theme,
                'Marked worst moment',
                '${(snap.markedPeakMs! / 1000).toStringAsFixed(0)} s in',
              ),
            if (!metrics.hasAmbient)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'The microphone had only been listening for '
                  '${metrics.ambientSeconds.toStringAsFixed(0)} s when you '
                  'pressed, which is too little to establish a background '
                  'level. Leave the app open for '
                  '${AudioConfig.preRollSeconds.round()} s before recording and '
                  'the complaint can quote the rise above background too.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (!metrics.calibrated)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Uncalibrated handset: treat the absolute figures as '
                  'indicative. The rise above background does not depend on '
                  'calibration.',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (metrics.clipped)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'The microphone hit its limit — it was at least this loud.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(ThemeData theme, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(label, style: theme.textTheme.bodyMedium),
            Text(value, style: theme.textTheme.bodyMedium),
          ],
        ),
      );
}

/// Never renders a coordinate the app did not actually have. A snap with no fix
/// says so plainly; 0, 0 would read as a position rather than as an absence.
String _locationSummary(Snap snap) {
  if (!snap.hasLocation) {
    return 'Location: not recorded — no satellite fix at the time.';
  }
  final StringBuffer buffer = StringBuffer('Location: ')
    ..write(snap.latitude!.toStringAsFixed(5))
    ..write(', ')
    ..write(snap.longitude!.toStringAsFixed(5));
  final double? accuracy = snap.gpsAccuracyM;
  if (accuracy != null) buffer.write(' (±${accuracy.round()} m)');
  if (snap.staleFix) buffer.write(' — last known position, not a live fix');
  return buffer.toString();
}
