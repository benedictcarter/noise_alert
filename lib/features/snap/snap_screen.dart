import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/quick_snap.dart';
import '../../data/audio/recorder_service.dart';
import '../../data/location/location_service.dart';
import '../../data/snap_service.dart';
import '../../domain/settings.dart';
import '../../domain/snap.dart';
import '../../providers.dart';
import '../chart/live_level_chart.dart';
import '../review/review_screen.dart';
import 'level_meter.dart';

/// The single button.
///
/// RECORD starts an event and STOP ends it: nothing else decides how long a
/// recording runs, because nothing else knows when the aircraft has gone.
///
/// The microphone runs the whole time this screen is visible even so. Not for
/// the event — that begins at the press — but for the background: the rise
/// above background is the one figure in the letter an uncalibrated handset
/// cannot distort, and it needs [AudioConfig.preRollSeconds] of street to
/// measure against.
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
  LocationStatus _location =
      const LocationStatus(LocationAvailability.denied);
  StreamSubscription<void>? _widgetTaps;

  /// Set while a widget-triggered capture is starting, so the screen explains
  /// why it is recording without anybody having pressed anything.
  bool _fromWidget = false;

  /// Seconds recorded so far, or null when not recording.
  ///
  /// Counts up, not down: the recording ends when the user says so, and a
  /// countdown would be promising a finish that is not coming. Driven by this
  /// screen's own timer so a stalled microphone still shows an honest clock.
  int? _elapsed;
  Timer? _clock;

  /// Set only when the delivered sample rate differs enough from the requested
  /// one to matter. Silent in the normal case; the point is to make a
  /// misbehaving microphone visible rather than to decorate the screen.
  String? _rateNote;
  Timer? _rateWatch;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    // One check a few seconds in, once enough stream has arrived to divide by.
    _rateWatch = Timer.periodic(const Duration(seconds: 3), (Timer _) {
      if (!mounted) return;
      final RecorderService rec = ref.read(recorderProvider);
      final String? note = !rec.isRunning || !rec.sampleRateSuspect
          ? null
          : 'Microphone is running at '
              '${(rec.effectiveSampleRate / 1000).toStringAsFixed(1)} kHz, not '
              '${AudioConfig.sampleRate ~/ 1000} kHz. Levels are approximate.';
      if (note != _rateNote) setState(() => _rateNote = note);
    });
  }

  /// Arms the microphone, then honours a widget tap if one brought us here.
  ///
  /// Order matters: the recorder has to be running before a capture can wait
  /// on it, and the permission prompt (if any) has to be answered first.
  Future<void> _start() async {
    await _arm();
    if (!mounted) return;

    final QuickSnapChannel quick = ref.read(quickSnapProvider);
    _widgetTaps ??= quick.requests.listen((_) => _snap(fromWidget: true));

    if (await quick.consumePending() && mounted) {
      await _snap(fromWidget: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    _rateWatch?.cancel();
    _widgetTaps?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Phase 1 does not listen in the background: holding the microphone while
    // backgrounded needs a foreground service on Android and an audio
    // background mode on iOS, both of which are Phase 2 work.
    if (state == AppLifecycleState.resumed) {
      _start();
    } else if (state == AppLifecycleState.paused) {
      if (!_capturing) {
        ref.read(snapServiceProvider).disarm();
      }
    }
  }

  Future<void> _arm() async {
    final SnapService service = ref.read(snapServiceProvider);
    if (service.isArmed) {
      // Already recording, but the user may have just come back from system
      // settings with location switched on.
      final LocationStatus status = await service.refreshLocationStatus();
      if (mounted) setState(() => _location = status);
      return;
    }
    try {
      await service.arm(settings: ref.read(settingsProvider));
      if (mounted) {
        setState(() {
          _armError = null;
          _location = service.locationStatus;
        });
      }
    } on Object catch (e) {
      if (mounted) setState(() => _armError = _friendlyArmError(e));
    }
  }

  Future<void> _fixLocation() async {
    await ref.read(snapServiceProvider).openLocationSettings();
    // The status is re-read by didChangeAppLifecycleState on the way back.
  }

  String _friendlyArmError(Object error) {
    final String text = error.toString();
    if (text.contains('permission')) {
      return 'Microphone permission is needed to measure sound levels. '
          'Grant it in system settings, then reopen this screen.';
    }
    return 'Could not start the microphone: $text';
  }

  Future<void> _snap({bool fromWidget = false}) async {
    if (_capturing) return;
    setState(() {
      _capturing = true;
      _fromWidget = fromWidget;
      _statusLine = 'Getting a location fix…';
    });

    final SnapService service = ref.read(snapServiceProvider);
    final ProviderSubscription<AsyncValue<CaptureProgress>> sub =
        ref.listenManual<AsyncValue<CaptureProgress>>(
      captureProgressProvider,
      (AsyncValue<CaptureProgress>? _, AsyncValue<CaptureProgress> next) {
        final CaptureProgress? p = next.value;
        if (p != null && mounted) {
          if (p.stage == CaptureStage.recording) {
            _startClock();
          } else {
            _stopClock();
          }
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
      _stopClock();
      if (mounted) {
        setState(() {
          _capturing = false;
          _fromWidget = false;
          _statusLine = null;
        });
      }
    }
  }

  void _startClock() {
    if (_clock != null) return;
    int seconds = 0;
    setState(() => _elapsed = seconds);
    _clock = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      seconds += 1;
      if (!mounted) return;
      setState(() => _elapsed = seconds);
    });
  }

  void _stopClock() {
    _clock?.cancel();
    _clock = null;
    if (mounted && _elapsed != null) {
      setState(() => _elapsed = null);
    }
  }

  static String _labelFor(CaptureStage stage) {
    switch (stage) {
      case CaptureStage.locating:
        return 'Getting a location fix…';
      case CaptureStage.recording:
        return 'Recording — press STOP when it has passed.';
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
      appBar: AppBar(title: const Text('Flightpath Watch Alert')),
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
              if (!_location.isReady && _armError == null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _Banner(
                    icon: Icons.location_off,
                    text: '${_location.message} Without one the snap is still '
                        'measured and saved, but no aircraft can be '
                        'identified.',
                    action: TextButton(
                      onPressed: _fixLocation,
                      child: Text(
                        _location.availability ==
                                LocationAvailability.serviceDisabled
                            ? 'Turn on'
                            : 'Settings',
                      ),
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
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        LevelMeter(
                          reading: meter.value,
                          running: ref.watch(snapServiceProvider).isArmed,
                        ),
                        const SizedBox(height: 16),
                        // Before RECORD this is the street; from the press
                        // it restarts and plots the event itself, so what the
                        // user watches while recording is the trace the letter
                        // will carry.
                        LiveLevelChart(
                          levelDb: meter.value?.levelDb,
                          running: ref.watch(snapServiceProvider).isArmed,
                          recording: _capturing,
                        ),
                      ],
                    ),
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
              if (_capturing)
                _StopButton(
                  onPressed: () =>
                      ref.read(snapServiceProvider).finishCaptureEarly(),
                  fromWidget: _fromWidget,
                  seconds: _elapsed,
                )
              else
                _RecordButton(onPressed: _snap, busy: false),
              const SizedBox(height: 12),
              Text(
                _capturing
                    ? 'Recording until you press STOP. The loudest '
                        '${AudioConfig.clipSeconds.round()} s is saved as a '
                        'clip; you choose afterwards whether to send it.'
                    : 'Records from the moment you press. Leave the app open '
                        'for ${AudioConfig.preRollSeconds.round()} s first and '
                        'the letter can also quote the rise above background.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
              // The rate the microphone is really delivering. Asking for
              // 48 kHz does not guarantee getting it, and a stream running slow
              // puts every level and every timestamp in the letter out by the
              // ratio.
              if (_rateNote != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _rateNote!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({required this.onPressed, required this.busy});

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
          busy ? 'RECORDING…' : 'RECORD',
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

/// Shown in place of RECORD while a recording is running.
///
/// The only thing that ends a recording. An earlier build stopped itself after
/// a fixed 20 s, which is both the most irritating thing a one-button app can
/// do and, more importantly, wrong: the person holding the phone is the only
/// one who knows when the aircraft has gone.
class _StopButton extends StatelessWidget {
  const _StopButton({
    required this.onPressed,
    required this.fromWidget,
    this.seconds,
  });

  final VoidCallback onPressed;
  final bool fromWidget;

  /// Seconds recorded so far.
  final int? seconds;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(
          width: double.infinity,
          height: 96,
          child: FilledButton.tonal(
            onPressed: onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: colors.secondaryContainer,
              foregroundColor: colors.onSecondaryContainer,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            child: Text(
              seconds == null ? 'STOP & SAVE' : 'STOP & SAVE  ($seconds s)',
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        if (fromWidget)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Started from the home-screen widget, so the microphone had not '
              'been listening beforehand — this event has no background level '
              'to compare against.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
