import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:noise_alert/map/config.dart';
import 'package:noise_alert/flights/aircraft.dart';
import 'package:noise_alert/map/live_map.dart';
import 'package:noise_alert/map/layers.dart';
import 'package:noise_alert/map/projection.dart';
import 'package:noise_alert/map/plane_icon.dart';

/// Draws the evidence onto a basemap image: the paths flown, the aeroplane,
/// the house, a scale bar and the attribution.
///
/// Separate from the widget because the picture that goes to a council is not
/// a screenshot of a phone. It has its own size, its own legend and its own
/// caption, and it has to be reproducible from a stored snap months later, so
/// it is painted from the same data, with a projection this code owns, rather
/// than captured from whatever happened to be on screen.
class MapOverlay {
  const MapOverlay({
    required this.view,
    required this.aircraft,
    this.observerLat,
    this.observerLon,
    this.caption = '',
    this.scale = 1,
  });

  /// The projection of the basemap underneath, already adjusted to the actual
  /// pixel size of the image.
  final MercatorView view;

  final List<MapAircraft> aircraft;
  final double? observerLat;
  final double? observerLon;

  /// One line under the picture saying what it is a picture of.
  final String caption;

  /// Pixels per logical unit, so a 900-wide image and a 2700-wide one get
  /// strokes and type of the same apparent weight.
  final double scale;

  static const Color _ink = Color(0xFF1A1D21);
  static const Color _muted = Color(0xFF5A6570);
  static const Color _panel = Color(0xF2FFFFFF);

  void paint(Canvas canvas) {
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, 0, view.width, view.height));

    for (final MapAircraft a in aircraft) {
      if (!a.highlighted) _paintTrack(canvas, a);
    }
    // The matched aircraft last, so a busy sky cannot draw over the one line
    // the letter is about.
    for (final MapAircraft a in aircraft) {
      if (a.highlighted) _paintTrack(canvas, a);
    }

    _paintObserver(canvas);
    for (final MapAircraft a in aircraft) {
      _paintPlane(canvas, a);
    }

    canvas.restore();

    _paintScaleBar(canvas);
    _paintFooter(canvas);
  }

  // === map furniture ===

  void _paintTrack(Canvas canvas, MapAircraft a) {
    if (a.points.length < 2) return;

    final Path path = Path();
    for (int i = 0; i < a.points.length; i++) {
      final TrackPoint p = a.points[i];
      final Offset o = view.project(p.latitude, p.longitude);
      if (i == 0) {
        path.moveTo(o.dx, o.dy);
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }

    if (a.highlighted) {
      // A white casing under the line. Printed in grey on a council's laser
      // printer, an orange line over a grey road is the same tone as the road;
      // the casing is what keeps it a line.
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 7 * scale
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = a.highlighted
            ? MapPalette.highlight
            : MapPalette.other.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = (a.highlighted ? 3.5 : 2.0) * scale
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _paintPlane(Canvas canvas, MapAircraft a) {
    final TrackPoint? head = a.head;
    if (head == null) return;
    final Offset at = view.project(head.latitude, head.longitude);
    final double size = (a.highlighted ? 34 : 26) * scale;

    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate((a.headingDeg ?? 0) * math.pi / 180.0);
    canvas.translate(-size / 2, -size / 2);
    PlaneIcon.paint(
      canvas,
      PlaneIcon.path(size),
      fill: a.highlighted ? MapPalette.highlight : MapPalette.other,
      outlineWidth: 3.5 * scale,
    );
    canvas.restore();

    if (a.highlighted && a.label.trim().isNotEmpty) {
      _paintLabel(
        canvas,
        a.label,
        Offset(at.dx, at.dy + size * 0.7),
        size: 15 * scale,
        color: _ink,
        weight: FontWeight.w700,
      );
    }
  }

  void _paintObserver(Canvas canvas) {
    final double? lat = observerLat;
    final double? lon = observerLon;
    if (lat == null || lon == null) return;
    final Offset at = view.project(lat, lon);

    canvas.drawCircle(
      at,
      11 * scale,
      Paint()..color = Colors.white.withValues(alpha: 0.9),
    );
    canvas.drawCircle(at, 6.5 * scale, Paint()..color = MapPalette.observer);
    _paintLabel(
      canvas,
      'Recording location',
      Offset(at.dx, at.dy + 15 * scale),
      size: 13 * scale,
      color: MapPalette.observer,
      weight: FontWeight.w600,
    );
  }

  /// Centred text with a white halo, because there is no telling what is
  /// underneath it.
  void _paintLabel(
    Canvas canvas,
    String text,
    Offset topCentre, {
    required double size,
    required Color color,
    FontWeight weight = FontWeight.w500,
  }) {
    for (final Paint? stroke in <Paint?>[
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * scale
        ..color = Colors.white,
      null,
    ]) {
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontSize: size,
            fontWeight: weight,
            color: stroke == null ? color : null,
            foreground: stroke,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(topCentre.dx - tp.width / 2, topCentre.dy));
      tp.dispose();
    }
  }

  /// A bar of a round number of metres, so distances can be read off the
  /// picture without trusting a caption.
  void _paintScaleBar(Canvas canvas) {
    final double mPerPx = view.metresPerPixel;
    if (!mPerPx.isFinite || mPerPx <= 0) return;

    const List<double> steps = <double>[
      50,
      100,
      200,
      250,
      500,
      1000,
      2000,
      5000,
    ];
    final double target = view.width * 0.22 * mPerPx;
    final double metres =
        steps.firstWhere((double s) => s >= target, orElse: () => steps.last);
    final double barPx = metres / mPerPx;

    final double right = view.width - 16 * scale;
    final double bottom = view.height - _footerHeight - 14 * scale;
    final double left = right - barPx;

    final Paint casing = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5 * scale;
    final Paint line = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2 * scale;

    final Path bar = Path()
      ..moveTo(left, bottom - 6 * scale)
      ..lineTo(left, bottom)
      ..lineTo(right, bottom)
      ..lineTo(right, bottom - 6 * scale);
    canvas.drawPath(bar, casing);
    canvas.drawPath(bar, line);

    _paintLabel(
      canvas,
      metres >= 1000
          ? '${(metres / 1000).toStringAsFixed(metres % 1000 == 0 ? 0 : 1)} km'
          : '${metres.round()} m',
      Offset((left + right) / 2, bottom - 24 * scale),
      size: 13 * scale,
      color: _ink,
      weight: FontWeight.w600,
    );
  }

  double get _footerHeight => 46 * scale;

  /// The caption and the attribution, on an opaque strip so they are readable
  /// whatever the map is doing underneath.
  ///
  /// The attribution is in the image rather than beside it because the image is
  /// the part that leaves the app. A line under a widget does not travel with a
  /// PNG into somebody's inbox.
  void _paintFooter(Canvas canvas) {
    final Rect strip = Rect.fromLTWH(
      0,
      view.height - _footerHeight,
      view.width,
      _footerHeight,
    );
    canvas.drawRect(strip, Paint()..color = _panel);
    canvas.drawLine(
      strip.topLeft,
      strip.topRight,
      Paint()
        ..color = _muted.withValues(alpha: 0.3)
        ..strokeWidth = 1 * scale,
    );

    void line(
        String text, double dy, double size, Color color, FontWeight weight) {
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(fontSize: size, color: color, fontWeight: weight),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: view.width - 24 * scale);
      tp.paint(canvas, Offset(12 * scale, strip.top + dy));
      tp.dispose();
    }

    line(caption, 8 * scale, 14 * scale, _ink, FontWeight.w600);
    line(
        MapConfig.attribution, 27 * scale, 11 * scale, _muted, FontWeight.w400);
  }
}
