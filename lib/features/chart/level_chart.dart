import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Draws A-weighted level against time.
///
/// One painter serves two masters: the live meter on the snap screen and the
/// PNG attached to the complaint. They must agree — a recipient who is told the
/// chart shows what the complainant saw should be looking at the same drawing,
/// not a second implementation of it that has drifted.
///
/// The painter takes no opinion on whether the levels are calibrated. That
/// caveat belongs in the caption and in the letter, and is added by
/// [LevelChartLabels.caption] so it cannot be forgotten in one place and not
/// the other.
class LevelChartPainter extends CustomPainter {
  const LevelChartPainter({
    required this.levels,
    required this.intervalMs,
    required this.palette,
    this.pressAtSeconds,
    this.ambientDb,
    this.markedAtSeconds,
    this.markMaximum = true,
    this.showAxes = true,
  });

  /// Left gutter, where the decibel scale is written.
  static const double axisGutter = 34;

  /// Seconds into a trace [dx] pixels across a chart [width] wide.
  ///
  /// Public so the review screen can turn a drag into a time without
  /// re-deriving the plot geometry: two implementations of the same mapping is
  /// how a marker ends up half a gutter away from the finger that placed it.
  static double secondsAt(
    double dx,
    double width,
    double totalSeconds, {
    bool showAxes = true,
  }) {
    final double left = showAxes ? axisGutter : 0;
    final double span = width - left;
    if (span <= 0 || totalSeconds <= 0) return 0;
    return (((dx - left) / span) * totalSeconds).clamp(0, totalSeconds);
  }

  /// dB(A), oldest first, one value every [intervalMs].
  final List<double> levels;
  final int intervalMs;

  final LevelChartPalette palette;

  /// Where in the trace the button was pressed, if this is a captured event.
  /// Null for the live meter, which has no press.
  final double? pressAtSeconds;

  /// Background level, drawn as a reference line. Null when none was measured —
  /// in which case no line is drawn rather than one at an invented level.
  final double? ambientDb;

  /// A moment the *user* marked, in seconds from the start of the trace.
  ///
  /// The measured maximum is where the microphone was loudest; this is where
  /// the person standing under it says the aircraft was worst — closest
  /// approach, or the part that actually made the room unusable. They are
  /// often not the same instant, and only one of them is evidence of what was
  /// experienced. Null until the user places it.
  final double? markedAtSeconds;

  final bool markMaximum;
  final bool showAxes;

  /// Fixed vertical range rather than one fitted to the data.
  ///
  /// An auto-scaled axis makes a quiet event and a loud one look identical,
  /// which is exactly the misreading a chart attached to a complaint must not
  /// invite. 30 dB(A) is a very quiet bedroom and 110 is where a handset is
  /// almost certainly clipping.
  static const double minDb = 30;
  static const double maxDb = 110;

  @override
  void paint(Canvas canvas, Size size) {
    final double leftGutter = showAxes ? axisGutter : 0;
    final double bottomGutter = showAxes ? 18 : 0;
    final Rect plot = Rect.fromLTRB(
      leftGutter,
      2,
      size.width,
      math.max(4, size.height - bottomGutter),
    );

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = palette.background,
    );

    double yFor(double db) =>
        plot.bottom -
        ((db.clamp(minDb, maxDb) - minDb) / (maxDb - minDb)) * plot.height;

    if (showAxes) _paintGrid(canvas, plot, yFor);

    if (levels.length < 2) {
      if (showAxes) _paintPlaceholder(canvas, plot);
      return;
    }

    final double totalSeconds = levels.length * intervalMs / 1000;
    double xFor(double seconds) =>
        plot.left + (seconds / totalSeconds) * plot.width;

    // The background line first, so the trace is drawn over it.
    final double? ambient = ambientDb;
    if (ambient != null) {
      final double y = yFor(ambient);
      _dashedLine(canvas, Offset(plot.left, y), Offset(plot.right, y),
          Paint()
            ..color = palette.ambient
            ..strokeWidth = 1.2);
      _label(canvas, 'background ${ambient.toStringAsFixed(0)}',
          Offset(plot.left + 4, y - 13), palette.ambient, 10);
    }

    final Path line = Path();
    final Path fill = Path()..moveTo(plot.left, plot.bottom);
    for (int i = 0; i < levels.length; i++) {
      final double x = xFor((i + 0.5) * intervalMs / 1000);
      final double y = yFor(levels[i]);
      if (i == 0) {
        line.moveTo(x, y);
      } else {
        line.lineTo(x, y);
      }
      fill.lineTo(x, y);
    }
    fill
      ..lineTo(plot.right, plot.bottom)
      ..close();

    canvas.drawPath(fill, Paint()..color = palette.fill);
    canvas.drawPath(
      line,
      Paint()
        ..color = palette.trace
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round,
    );

    final double? press = pressAtSeconds;
    if (press != null && press > 0 && press < totalSeconds) {
      final double x = xFor(press);
      _dashedLine(canvas, Offset(x, plot.top), Offset(x, plot.bottom),
          Paint()
            ..color = palette.press
            ..strokeWidth = 1.2);
      _label(canvas, 'pressed', Offset(x + 3, plot.top + 2), palette.press, 10);
    }

    final double? marked = markedAtSeconds;
    if (marked != null && levels.isNotEmpty) {
      final int index = (marked * 1000 / intervalMs)
          .floor()
          .clamp(0, levels.length - 1);
      final double x = xFor((index + 0.5) * intervalMs / 1000);
      final double y = yFor(levels[index]);
      final Paint stroke = Paint()
        ..color = palette.marked
        ..strokeWidth = 1.6;
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), stroke);
      canvas.drawCircle(Offset(x, y), 6, Paint()..color = palette.marked);
      canvas.drawCircle(
        Offset(x, y),
        6,
        Paint()
          ..color = palette.background
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
      _label(
        canvas,
        'worst: ${levels[index].toStringAsFixed(0)} dB(A) at '
        '${marked.toStringAsFixed(0)} s',
        Offset(
          (x + 9).clamp(plot.left, math.max(plot.left, plot.right - 150)),
          plot.bottom - 14,
        ),
        palette.marked,
        10,
        bold: true,
      );
    }

    if (markMaximum) {
      int peak = 0;
      for (int i = 1; i < levels.length; i++) {
        if (levels[i] > levels[peak]) peak = i;
      }
      final Offset at = Offset(
        xFor((peak + 0.5) * intervalMs / 1000),
        yFor(levels[peak]),
      );
      canvas.drawCircle(at, 3.5, Paint()..color = palette.trace);
      _label(
        canvas,
        '${levels[peak].toStringAsFixed(0)} dB(A)',
        Offset(math.min(at.dx + 6, plot.right - 60), at.dy - 14),
        palette.trace,
        11,
        bold: true,
      );
    }
  }

  void _paintGrid(Canvas canvas, Rect plot, double Function(double) yFor) {
    final Paint grid = Paint()
      ..color = palette.grid
      ..strokeWidth = 1;
    for (double db = minDb; db <= maxDb; db += 20) {
      final double y = yFor(db);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
      _label(canvas, db.toStringAsFixed(0), Offset(2, y - 7), palette.axis, 10);
    }
    canvas.drawLine(
      Offset(plot.left, plot.bottom),
      Offset(plot.right, plot.bottom),
      Paint()
        ..color = palette.axis
        ..strokeWidth = 1,
    );

    if (levels.length >= 2) {
      final double totalSeconds = levels.length * intervalMs / 1000;
      _label(canvas, '0 s', Offset(plot.left, plot.bottom + 3), palette.axis,
          10);
      _label(
        canvas,
        '${totalSeconds.toStringAsFixed(0)} s',
        Offset(plot.right - 26, plot.bottom + 3),
        palette.axis,
        10,
      );
    }
  }

  void _paintPlaceholder(Canvas canvas, Rect plot) => _label(
        canvas,
        'listening…',
        Offset(plot.left + 8, plot.center.dy - 7),
        palette.axis,
        11,
      );

  void _dashedLine(Canvas canvas, Offset from, Offset to, Paint paint) {
    const double dash = 4;
    const double gap = 3;
    final double total = (to - from).distance;
    if (total <= 0) return;
    final Offset step = (to - from) / total;
    for (double at = 0; at < total; at += dash + gap) {
      canvas.drawLine(
        from + step * at,
        from + step * math.min(at + dash, total),
        paint,
      );
    }
  }

  void _label(Canvas canvas, String text, Offset at, Color color, double size,
      {bool bold = false}) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(LevelChartPainter old) =>
      old.levels != levels ||
      old.ambientDb != ambientDb ||
      old.pressAtSeconds != pressAtSeconds ||
      old.markedAtSeconds != markedAtSeconds ||
      old.palette != palette;
}

/// Colours for one rendering of the chart.
///
/// The emailed PNG is always drawn on white: it is going into a mail client
/// whose background we do not control, and a dark chart on a white page looks
/// like a rendering fault.
@immutable
class LevelChartPalette {
  const LevelChartPalette({
    required this.background,
    required this.grid,
    required this.axis,
    required this.trace,
    required this.fill,
    required this.ambient,
    required this.press,
    required this.marked,
  });

  factory LevelChartPalette.forEmail() => const LevelChartPalette(
        background: Color(0xFFFFFFFF),
        grid: Color(0xFFE0E0E0),
        axis: Color(0xFF616161),
        trace: Color(0xFFB3261E),
        fill: Color(0x1AB3261E),
        ambient: Color(0xFF1B5E20),
        press: Color(0xFF1565C0),
        marked: Color(0xFF6A1B9A),
      );

  factory LevelChartPalette.of(ThemeData theme) {
    final ColorScheme c = theme.colorScheme;
    return LevelChartPalette(
      background: c.surfaceContainerHighest.withValues(alpha: 0.4),
      grid: c.outlineVariant,
      axis: c.onSurfaceVariant,
      trace: c.primary,
      fill: c.primary.withValues(alpha: 0.12),
      ambient: c.tertiary,
      press: c.secondary,
      marked: c.tertiary,
    );
  }

  final Color background;
  final Color grid;
  final Color axis;
  final Color trace;
  final Color fill;
  final Color ambient;
  final Color press;
  final Color marked;

  @override
  bool operator ==(Object other) =>
      other is LevelChartPalette &&
      other.background == background &&
      other.grid == grid &&
      other.axis == axis &&
      other.trace == trace &&
      other.fill == fill &&
      other.ambient == ambient &&
      other.press == press &&
      other.marked == marked;

  @override
  int get hashCode =>
      Object.hash(background, grid, axis, trace, fill, ambient, press, marked);
}

/// The one place the chart's caption is written.
class LevelChartLabels {
  const LevelChartLabels._();

  /// Sentence describing the chart, for the letter and for the screen.
  ///
  /// Carries the calibration caveat: the chart is the most persuasive-looking
  /// thing in the email and therefore the most important not to over-claim.
  static String caption({required bool calibrated}) => calibrated
      ? 'A-weighted sound level against time, measured with a calibrated '
          'offset for this handset.'
      : 'A-weighted sound level against time. The vertical scale is '
          'UNCALIBRATED and the absolute values may be several decibels out; '
          'the shape of the event and its rise above the background are not '
          'affected by that offset.';
}

/// Renders the chart to a PNG off-screen.
///
/// No widget tree and no BuildContext: this runs from the send path, which has
/// no frame of its own and must work whether or not the review screen is still
/// mounted.
Future<ui.Image> renderLevelChart({
  required LevelChartPainter painter,
  required Size size,
  double pixelRatio = 2,
}) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  canvas.scale(pixelRatio);
  painter.paint(canvas, size);
  return recorder.endRecording().toImage(
        (size.width * pixelRatio).round(),
        (size.height * pixelRatio).round(),
      );
}
