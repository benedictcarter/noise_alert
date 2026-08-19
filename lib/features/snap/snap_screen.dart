import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../data/audio/recorder_service.dart';
import '../../data/snap_service.dart';
import '../../domain/settings.dart';
import '../../domain/snap.dart';
import '../../providers.dart';
import '../review/review_screen.dart';
import 'level_meter.dart';

/// The single button.
///
/// The microphone runs the whole time this screen is visible so that the
/// pre-roll buffer already holds the approach by the time the user reacts —
/// pressing the button captures the [AudioConfig.preRollSeconds] seconds
/// *before* the press as well as the tail afterwards.
class SnapScreen extends ConsumerStatefulWidget {
  const SnapScreen({super.key});

  @override
  ConsumerState<SnapScreen> createState() => _SnapScreenState();
}

class _SnapScreenState extends ConsumerState<SnapScreen>
    with WidgetsBindingObserver {
  String? _armError;
  bool _capturing = false;
  String? _statusLine;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _arm());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Phase 1 does not listen in the background: holding the microphone while
    // backgrounded needs a foreground service on Android and an audio
    // background mode on iOS, both of which are Phase 2 work.
    if (state == AppLifecycleState.resumed) {
      _arm();
    } else if (state == AppLifecycleState.paused) {
      if (!_capturing) {
        ref.read(snapServiceProvider).disarm();
      }
    }
  }

  Future<void> _arm() async {
    final SnapService service = ref.read(snapServiceProvider);
    if (service.isArmed) return;
    try {
      await service.arm(settings: ref.read(settingsProvider));
      if (mounted) setState(() => _armError = null);
    } on Object catch (e) {
      if (mounted) setState(() => _armError = _friendlyArmError(e));
    }
  }

  String _friendlyArmError(Object error) {
    final String text = error.toString();
    if (text.contains('permission')) {
      return 'Microphone permission is needed to measure sound levels. '
          'Grant it in system settings, then reopen this screen.';
    }
    return 'Could not start the microphone: $text';
  }

  Future<void> _snap() async {
    if (_capturing) return;
    setState(() {
      _capturing = true;
      _statusLine = 'Getting a location fix…';
    });

    final SnapService service = ref.read(snapServiceProvider);
    final ProviderSubscription<AsyncValue<CaptureProgress>> sub =
        ref.listenManual<AsyncValue<CaptureProgress>>(
      captureProgressProvider,
      (AsyncValue<CaptureProgress>? _, AsyncValue<CaptureProgress> next) {
        final CaptureProgress? p = next.value;
        if (p != null && mounted) {
          setState(() => _statusLine = p.message ?? _labelFor(p.stage));
        }
      },
    );

    try {
      final Snap snap = await service.capture(
        settings: ref.read(settingsProvider),
      );
      ref.read(snapsProvider.notifier).put(snap);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext _) => ReviewScreen(snapId: snap.id),
        ),
      );
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: $e')),
        );
      }
    } finally {
      sub.close();
      if (mounted) {
        setState(() {
          _capturing = false;
          _statusLine = null;
        });
      }
    }
  }

  static String _labelFor(CaptureStage stage) {
    switch (stage) {
      case CaptureStage.locating:
        return 'Getting a location fix…';
      case CaptureStage.recording:
        return 'Recording the tail of the event…';
      case CaptureStage.analysing:
        return 'Measuring the sound level…';
      case CaptureStage.matching:
        return 'Looking for the aircraft…';
      case CaptureStage.idle:
      case CaptureStage.done:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<MeterReading> meter = ref.watch(meterProvider);
    final AppSettings settings = ref.watch(settingsProvider);
    final ThemeData theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Noise Alert')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: <Widget>[
              if (_armError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _Banner(
                    icon: Icons.mic_off,
                    text: _armError!,
                    action: TextButton(
                      onPressed: _arm,
                      child: const Text('Retry'),
                    ),
                  ),
                ),
              if (!settings.calibrated && _armError == null)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: _Banner(
                    icon: Icons.info_outline,
                    text: 'Uncalibrated handset — levels are indicative. Every '
                        'complaint says so, and quotes the rise above '
                        'background, which does not depend on calibration.',
                  ),
                ),
              Expanded(
                child: Center(
                  child: LevelMeter(
                    reading: meter.value,
                    running: ref.watch(snapServiceProvider).isArmed,
                  ),
                ),
              ),
              if (_statusLine != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Text(
                          _statusLine!,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              _SnapButton(
                  onPressed: _capturing ? null : _snap, busy: _capturing),
              const SizedBox(height: 16),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: settings.keepClip,
                onChanged: (bool v) => ref
                    .read(settingsProvider.notifier)
                    .edit((AppSettings s) => s.copyWith(keepClip: v)),
                title: const Text('Save an audio clip'),
                subtitle: Text(
                  settings.keepClip
                      ? 'The loudest ${AudioConfig.clipSeconds} s is saved. You '
                          'can play it back and decide whether to attach it.'
                      : 'Off. Measurements only — no audio is written to disk.',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Captures the ${AudioConfig.preRollSeconds} s before you press '
                'and ${AudioConfig.postRollSeconds} s after.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _SnapButton extends StatelessWidget {
  const _SnapButton({required this.onPressed, required this.busy});

  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      height: 96,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: colors.error,
          foregroundColor: colors.onError,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
        child: Text(
          busy ? 'CAPTURING…' : 'SNAP',
          style: const TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            letterSpacing: 4,
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
          if (action != null) action!,
        ],
      ),
    );
  }
}
