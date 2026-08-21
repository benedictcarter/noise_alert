import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../core/quick_snap.dart';
import '../../data/audio/recorder_service.dart';
import '../../data/location/location_service.dart';
import '../../data/mail/mail_sender.dart';
import '../../data/snap_service.dart';
import '../../domain/snap.dart';
import '../../providers.dart';
import '../chart/live_level_chart.dart';
import '../review/review_screen.dart';
import 'level_meter.dart';

/// The screen that is already recording when you get to it.
///
/// Opening the app *is* the press. Someone reaching for their phone under a
/// flight path has already decided to complain, and the seconds spent finding
/// a button are seconds of the aircraft they do not get back. So the recording
/// starts on arrival and only the user ends it: nothing else knows when the
/// aircraft has gone.
///
/// The background comes out of the recording itself — the quietest stretches
/// of it, which on a recording that runs from before the aircraft until after
/// it has gone are the street with no jet over it. That is why recording from
/// launch costs nothing: the comparison the letter leads on is peak against
/// quiet, and both halves of it are inside the same recording.
///
/// A recording nobody asked for must also be easy to walk away from, so an
/// auto-started one is discarded the moment the user leaves this tab or
/// backgrounds the app. Only a recording the user pressed for survives that.
class SnapScreen extends ConsumerStatefulWidget {
  const SnapScreen({super.key});

  @override
  ConsumerState<SnapScreen> createState() => _SnapScreenState();
}

class _SnapScreenState extends ConsumerState<SnapScreen>
    with WidgetsBindingObserver {
  String? _armError;

  /// True when the last attempt to open the microphone was refused rather than
  /// broken. Kept apart from [_armError] because a refusal is not an error the
  /// user has to read: it is a button they have to press.
  bool _micDenied = false;
  bool _capturing = false;
  String? _statusLine;
  LocationStatus _location =
      const LocationStatus(LocationAvailability.denied);
  StreamSubscription<void>? _widgetTaps;

  /// True when the running recording began by itself rather than by a press.
  /// Only these are thrown away when the user's attention goes elsewhere.
  bool _autoStarted = false;

  /// Which of the two stop buttons was pressed.
  ///
  /// Read after the capture finishes, not before it starts: both buttons end
  /// the same recording, and until one of them is pressed there is no way to
  /// know whether this will end up a save or a send.
  bool _sendOnStop = false;

  /// Seconds recorded so far, or null when not recording.
  ///
  /// Counts up, not down: the recording ends when the user says so, and a
  /// countdown would be promising a finish that is not coming. Driven by this
  /// screen's own timer so a stalled microphone still shows an honest clock.
  int? _elapsed;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    // Leaving the tab abandons a recording the user never asked for. Watched
    // rather than polled because an IndexedStack keeps this screen built and
    // running no matter which tab is on top.
    ref.listenManual<int>(homeTabProvider, (int? _, int tab) {
      if (tab != 0) _abandonIfAuto();
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
    _widgetTaps ??= quick.requests.listen((_) => _snap());

    if (await quick.consumePending() && mounted) {
      await _snap();
      return;
    }

    // Nobody pressed anything, so start anyway.
    if (!mounted || _capturing) return;
    if (ref.read(homeTabProvider) != 0) return;
    // Not while the review screen is on top: the user is reading the last
    // recording, not making the next one.
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
    await _snap(auto: true);
  }

  /// Drops a recording the user never asked for, if one is running.
  void _abandonIfAuto() {
    if (_capturing && _autoStarted) {
      ref.read(snapServiceProvider).abandonCapture();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
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
      _abandonIfAuto();
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
          _micDenied = false;
          _location = service.locationStatus;
        });
      }
    } on Object catch (e) {
      final bool denied = _looksLikeRefusal(e);
      if (mounted) {
        setState(() {
          _micDenied = denied;
          _armError = denied ? null : 'Could not start the microphone: $e';
        });
      }
    }
  }

  static bool _looksLikeRefusal(Object error) =>
      error.toString().toLowerCase().contains('permission');

  /// Asks for the microphone again, for the however-manyth time.
  ///
  /// There is no limit on this by design. Someone who tapped Deny to make a
  /// box go away, and now wants to record an aeroplane, must be able to get
  /// back to Allow by pressing the obvious button -- not by being told the app
  /// is broken and left there.
  ///
  /// Two refusals in, Android stops showing its own dialog and simply answers
  /// no. Nothing tells us that has happened, so the flow is: explain, ask, and
  /// if it is still refused afterwards offer the settings page. That costs one
  /// extra tap on the first refusal and rescues every refusal after it.
  Future<void> _askForMic() async {
    final bool? go = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        icon: const Icon(Icons.mic, size: 36),
        title: const Text('Turn on the microphone'),
        content: const Text(
          'To measure how loud the aircraft is, the app needs to use the '
          'microphone.\n\n'
          'The sound stays on this phone. Nothing is uploaded, and nothing is '
          'sent with a complaint unless you choose to attach it.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;

    await _arm();
    if (!mounted || !_micDenied) return;

    final bool? toSettings = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        icon: const Icon(Icons.settings, size: 36),
        title: const Text('One more step'),
        content: const Text(
          'The phone is still not letting the app use the microphone.\n\n'
          'Tap Open settings, choose Permissions, and switch Microphone on. '
          'Then come back here.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Open settings'),
          ),
        ],
      ),
    );
    if (toSettings == true) {
      await ref.read(snapServiceProvider).openAppSettings();
      // didChangeAppLifecycleState re-arms on the way back in.
    }
  }

  Future<void> _fixLocation() async {
    await ref.read(snapServiceProvider).openLocationSettings();
    // The status is re-read by didChangeAppLifecycleState on the way back.
  }

  Future<void> _snap({bool auto = false}) async {
    if (_capturing) return;
    setState(() {
      _capturing = true;
      _autoStarted = auto;
      _sendOnStop = false;
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
      Snap snap = await service.capture(
        settings: ref.read(settingsProvider),
      );
      ref.read(snapsProvider.notifier).put(snap);
      if (!mounted) return;

      if (_sendOnStop) {
        setState(() => _statusLine = 'Drafting the complaint…');
        final CaptureSendResult result = await service.sendCaptured(snap);
        ref.read(snapsProvider.notifier).put(result.snap);
        snap = result.snap;
        if (!mounted) return;

        final MailOutcome? outcome = result.outcome;
        if (outcome != null && outcome.opened) {
          // Done: the letter is in front of them in their own mail app, which
          // is as far as this app is ever allowed to take it.
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Complaint handed to your mail app.'),
            ),
          );
          return;
        }
        // Either the aircraft was too ambiguous to name without asking, or the
        // draft could not be built. Both end on the review screen; only the
        // second needs explaining.
        if (outcome != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(outcome.detail ?? 'Could not open your mail app.'),
            ),
          );
        }
      }

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext _) => ReviewScreen(snapId: snap.id),
        ),
      );
    } on CaptureAbandoned {
      // Two ways to get here. Walking away from a recording nobody asked for
      // is silent -- there is nothing to tell someone who has already left.
      // Pressing DISCARD is a deliberate act and gets an acknowledgement, or
      // the user is left wondering whether the button did anything.
      if (_discarding && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recording discarded.')),
        );
      }
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
          _autoStarted = false;
          _sendOnStop = false;
          _discarding = false;
          _statusLine = null;
        });
      }
    }
  }

  /// True from the press of DISCARD until the capture unwinds, so the
  /// abandon path can tell a deliberate throw-away from a walk-away.
  bool _discarding = false;

  /// Stops without keeping anything.
  ///
  /// No confirmation dialog, deliberately. The button says DISCARD, it is a
  /// different colour from the two beside it, and a modal on a three-button
  /// control that is being used while an aeroplane is overhead costs more than
  /// the mistake it prevents. Nothing has been written to disk at this point,
  /// so there is nothing to undo and nothing left behind.
  void _discard() {
    setState(() {
      _discarding = true;
      _autoStarted = false;
    });
    ref.read(snapServiceProvider).abandonCapture();
  }

  void _stop({required bool send}) {
    setState(() {
      _sendOnStop = send;
      // A recording the user has chosen to keep is no longer disposable.
      _autoStarted = false;
    });
    ref.read(snapServiceProvider).finishCaptureEarly();
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
        return 'Recording — press a button below when it has passed.';
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
              if (!_location.isReady && _armError == null && !_micDenied)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _Banner(
                    icon: Icons.location_off,
                    text: '${_location.message} The noise is still measured '
                        'and the complaint can still be sent — but without a '
                        'location no aircraft can be named.',
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
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        // Half-lit when nothing is being recorded. The meter
                        // and the chart are live either way -- the microphone
                        // is always listening while this screen is up -- but
                        // only what is drawn during a recording ends up in a
                        // complaint, and the difference has to be visible at a
                        // glance from arm's length.
                        AnimatedOpacity(
                          opacity: _capturing ? 1 : 0.5,
                          duration: const Duration(milliseconds: 250),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              LevelMeter(
                                reading: meter.value,
                                running:
                                    ref.watch(snapServiceProvider).isArmed,
                              ),
                              const SizedBox(height: 16),
                              // Before the press this is the street; from the
                              // press it restarts and plots the event itself,
                              // so what the user watches while recording is
                              // the trace the letter will carry.
                              LiveLevelChart(
                                levelDb: meter.value?.levelDb,
                                running:
                                    ref.watch(snapServiceProvider).isArmed,
                                recording: _capturing,
                              ),
                            ],
                          ),
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
                _StopButtons(
                  onDiscard: _discard,
                  onSave: () => _stop(send: false),
                  onSend: () => _stop(send: true),
                  seconds: _elapsed,
                )
              else if (_micDenied)
                _MicButton(onPressed: _askForMic)
              else
                _RecordButton(onPressed: _snap, busy: false),
              const SizedBox(height: 12),
              Text(
                _capturing
                    ? ''
                    : _micDenied
                        ? 'The app cannot hear anything yet. Press the button '
                            'above to let it use the microphone. You can say '
                            'no and try again as often as you like.'
                        : 'Not recording. Press RECORD to log an aircraft — a '
                            'complaint is still worth sending with no sound, '
                            'no location and no flight named.',
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

/// Go, not danger.
///
/// The button was the theme's error red, which is the colour every other app
/// uses for "this will delete something". Pressing RECORD is the one thing
/// this app wants the user to do without hesitating.
const Color _recordGreen = Color(0xFF1E7B34);

/// The send half of the stop control. Darker than the app's own blue so the
/// three stop buttons cannot be confused with each other at a glance.
const Color _sendBlue = Color(0xFF0D3B66);

/// Throwing the recording away. Orange rather than the theme's error red:
/// discarding a recording of your own kitchen is a normal thing to want, not a
/// destructive act to be warned about, and red beside two other buttons reads
/// as "do not press this".
const Color _discardOrange = Color(0xFFC2521A);

class _RecordButton extends StatelessWidget {
  const _RecordButton({required this.onPressed, required this.busy});

  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 96,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: _recordGreen,
          foregroundColor: Colors.white,
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

/// What stands where RECORD stands, when there is no microphone yet.
///
/// The same size and shape as the record button rather than a small link in a
/// banner: it is the one thing to press, so it is the one thing that is big.
/// Amber, not red -- nothing has gone wrong, something is simply not switched
/// on yet.
class _MicButton extends StatelessWidget {
  const _MicButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 96,
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF8A5300),
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
        icon: const Icon(Icons.mic_off, size: 32),
        label: const Text(
          'TURN ON THE MIC',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
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
/// Two buttons, because there are two things a user might want and only one of
/// them is worth a detour through a review screen. REVIEW keeps the
/// recording and opens it; SEND drafts the complaint and hands it to the
/// mail app, which makes the whole job three taps: open, stop-and-send, send.
///
/// Nothing else ends a recording. An earlier build stopped itself after a
/// fixed 20 s, which is both the most irritating thing a one-button app can do
/// and, more importantly, wrong: the person holding the phone is the only one
/// who knows when the aircraft has gone.
class _StopButtons extends StatelessWidget {
  const _StopButtons({
    required this.onDiscard,
    required this.onSave,
    required this.onSend,
    this.seconds,
  });

  final VoidCallback onDiscard;
  final VoidCallback onSave;
  final VoidCallback onSend;

  /// Seconds recorded so far.
  final int? seconds;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colors = theme.colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // One clock above the row rather than the same number repeated inside
        // three labels. With two buttons the suffix fitted; with three it left
        // no room for the words that say what the buttons do.
        if (seconds != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Recording — $seconds s',
              style: theme.textTheme.titleMedium,
            ),
          ),
        SizedBox(
          height: 96,
          child: Row(
            children: <Widget>[
              Expanded(
                child: _StopButton(
                  onPressed: onDiscard,
                  label: 'DISCARD',
                  background: _discardOrange,
                  foreground: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StopButton(
                  onPressed: onSave,
                  label: 'REVIEW',
                  background: colors.secondaryContainer,
                  foreground: colors.onSecondaryContainer,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StopButton(
                  onPressed: onSend,
                  label: 'SEND',
                  background: _sendBlue,
                  foreground: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StopButton extends StatelessWidget {
  const _StopButton({
    required this.onPressed,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final VoidCallback onPressed;
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
