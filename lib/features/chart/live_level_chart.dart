import 'dart:collection';

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import 'level_chart.dart';

/// A scrolling plot of the level the microphone is hearing right now.
///
/// Holds exactly the span the ring buffer holds, so what the user sees on the
/// chart is what pressing the button would capture — a plot that showed more
/// history than the recorder keeps would promise audio that no longer exists.
class LiveLevelChart extends StatefulWidget {
  const LiveLevelChart({
    super.key,
    required this.levelDb,
    required this.running,
    this.height = 120,
  });

  /// Latest reading, or null when there is nothing yet.
  final double? levelDb;
  final bool running;
  final double height;

  @override
  State<LiveLevelChart> createState() => _LiveLevelChartState();
}

class _LiveLevelChartState extends State<LiveLevelChart> {
  /// One point per [_intervalMs]. A queue rather than a list so dropping the
  /// oldest point is O(1) — this runs ten times a second for as long as the
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

  int get _capacity =>
      (AudioConfig.ringBufferSeconds * 1000 / _intervalMs).round();

  @override
  void didUpdateWidget(LiveLevelChart old) {
    super.didUpdateWidget(old);

    if (!widget.running) {
      if (_points.isNotEmpty) {
        setState(_points.clear);
      }
      return;
    }

    final double? level = widget.levelDb;
    if (level == null) return;
    _pending = _pending == null ? level : (level > _pending! ? level : _pending);

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
class EventLevelChart extends StatelessWidget {
  const EventLevelChart({
    super.key,
    required this.levels,
    required this.intervalMs,
    required this.pressAtSeconds,
    required this.ambientDb,
    this.height = 160,
  });

  final List<double> levels;
  final int intervalMs;
  final double pressAtSeconds;
  final double? ambientDb;
  final double height;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return SizedBox(
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
          ),
        ),
      ),
    );
  }
}
