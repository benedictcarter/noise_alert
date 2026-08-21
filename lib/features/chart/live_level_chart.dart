import 'dart:collection';

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import 'level_chart.dart';

/// A plot of the level the microphone is hearing right now.
///
/// Two modes, and the switch between them is the point. Idle, it scrolls the
/// last [AudioConfig.ringBufferSeconds] of street, exactly the span the ring
/// buffer holds, because a plot showing more history than the recorder keeps
/// would promise audio that no longer exists. From RECORD it starts again from
/// empty and keeps everything, so the graph on screen is the event itself and
/// matches the one the letter will carry.
class LiveLevelChart extends StatefulWidget {
  const LiveLevelChart({
    super.key,
    required this.levelDb,
    required this.running,
    this.recording = false,
    this.height = 120,
  });

  /// Latest reading, or null when there is nothing yet.
  final double? levelDb;
  final bool running;

  /// True from the press of RECORD until the recording is saved.
  final bool recording;

  final double height;

  @override
  State<LiveLevelChart> createState() => _LiveLevelChartState();
}

class _LiveLevelChartState extends State<LiveLevelChart> {
  /// One point per [_intervalMs]. A queue rather than a list so dropping the
  /// oldest point is O(1): this runs ten times a second for as long as the
  /// screen is open.
  final Queue<double> _points = Queue<double>();

  static const int _intervalMs = 250;

  /// Peak level seen since the last point was committed.
  ///
  /// Peak, not mean: the meter updates every 100 ms and the chart every 250 ms,
  /// so something has to be discarded, and a plot of aircraft noise that misses
  /// the loudest moment is the wrong one to keep.
  double? _pending;
  DateTime _lastPoint = DateTime.fromMillisecondsSinceEpoch(0);

  /// While idle the chart holds what the ring holds; while recording it holds
  /// the whole event, bounded by the same cap the recorder enforces.
  int get _capacity => ((widget.recording
              ? AudioConfig.maxEventSeconds
              : AudioConfig.ringBufferSeconds) *
          1000 /
          _intervalMs)
      .round();

  @override
  void didUpdateWidget(LiveLevelChart old) {
    super.didUpdateWidget(old);

    if (!widget.running) {
      if (_points.isNotEmpty) {
        setState(_points.clear);
      }
      return;
    }

    // The press starts a new graph. The background before it is still being
    // measured, but it is not part of this event and drawing it here would put
    // half a minute of empty street in front of every flyover.
    if (widget.recording != old.recording) {
      _points.clear();
      _pending = null;
    }

    final double? level = widget.levelDb;
    if (level == null) return;
    _pending =
        _pending == null ? level : (level > _pending! ? level : _pending);

    final DateTime now = DateTime.now();
    if (now.difference(_lastPoint).inMilliseconds < _intervalMs) return;
    _lastPoint = now;
    _points.add(_pending!);
    _pending = null;
    while (_points.length > _capacity) {
      _points.removeFirst();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CustomPaint(
          painter: LevelChartPainter(
            levels: _points.toList(growable: false),
            intervalMs: _intervalMs,
            palette: LevelChartPalette.of(theme),
            markMaximum: false,
          ),
        ),
      ),
    );
  }
}

/// The stored trace of a captured event, as it will appear in the letter.
///
/// Pass [onMarkChanged] to let the user drag the "worst moment" marker along
/// the trace. The measured maximum stays where the microphone put it; the
/// marker is a separate claim, and the one the complainant is actually making.
class EventLevelChart extends StatelessWidget {
  const EventLevelChart({
    super.key,
    required this.levels,
    required this.intervalMs,
    required this.pressAtSeconds,
    required this.ambientDb,
    this.markedAtSeconds,
    this.onMarkChanged,
    this.height = 160,
  });

  final List<double> levels;
  final int intervalMs;
  final double pressAtSeconds;
  final double? ambientDb;
  final double? markedAtSeconds;

  /// Called with the seconds the user dragged to. Null makes the chart
  /// read-only, which is what the history screen and the PNG both want.
  final ValueChanged<double>? onMarkChanged;

  final double height;

  double get _totalSeconds => levels.length * intervalMs / 1000;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Widget chart = SizedBox(
      height: height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CustomPaint(
          painter: LevelChartPainter(
            levels: levels,
            intervalMs: intervalMs,
            palette: LevelChartPalette.of(theme),
            pressAtSeconds: pressAtSeconds,
            ambientDb: ambientDb,
            markedAtSeconds: markedAtSeconds,
          ),
        ),
      ),
    );

    final ValueChanged<double>? onChanged = onMarkChanged;
    if (onChanged == null) return chart;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        void report(Offset local) => onChanged(
              LevelChartPainter.secondsAt(
                local.dx,
                constraints.maxWidth,
                _totalSeconds,
              ),
            );
        return GestureDetector(
          // Tap to place, drag to refine. Both go through the same mapping as
          // the painter, so the marker lands under the finger.
          onTapDown: (TapDownDetails d) => report(d.localPosition),
          onHorizontalDragStart: (DragStartDetails d) =>
              report(d.localPosition),
          onHorizontalDragUpdate: (DragUpdateDetails d) =>
              report(d.localPosition),
          child: chart,
        );
      },
    );
  }
}
