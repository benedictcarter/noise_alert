import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Marker artwork for the map, drawn at run time rather than shipped as an
/// asset.
///
/// Two reasons. A PNG in `assets/` has to be declared, bundled and kept in sync
/// at three densities; and the same aeroplane has to appear both as a MapLibre
/// icon on screen and as a shape painted onto the picture attached to the
/// complaint, which are different renderers reading the same outline. A `Path`
/// serves both.
class PlaneIcon {
  /// Raw pixels of the bitmap handed to MapLibre. The plugin decodes it with
  /// density scaling switched off, so this is the number the style's
  /// `icon-size` multiplies; see [displayScale].
  static const int pixels = 64;

  /// Multiplier that turns [pixels] into something the size of a thumbnail
  /// rather than the size of a house.
  static const double displayScale = 0.5;

  /// An aeroplane in plan view, nose up, inside a [size] by [size] box.
  ///
  /// Nose *up* matters. MapLibre's `icon-rotate` and [Canvas.rotate] both
  /// measure clockwise from up, so an outline drawn pointing any other way is
  /// wrong by that angle at every heading, and the error is invisible until
  /// you notice every aircraft flying sideways.
  static Path path(double size) {
    final double s = size / 64.0;
    // Nose, out along the leading edge of the starboard wing, back to the
    // root, down the fuselage to the tailplane, and mirrored home.
    return Path()
      ..moveTo(32 * s, 4 * s)
      ..lineTo(36 * s, 22 * s)
      ..lineTo(60 * s, 38 * s)
      ..lineTo(60 * s, 44 * s)
      ..lineTo(36 * s, 38 * s)
      ..lineTo(36 * s, 50 * s)
      ..lineTo(44 * s, 57 * s)
      ..lineTo(44 * s, 61 * s)
      ..lineTo(32 * s, 57 * s)
      ..lineTo(20 * s, 61 * s)
      ..lineTo(20 * s, 57 * s)
      ..lineTo(28 * s, 50 * s)
      ..lineTo(28 * s, 38 * s)
      ..lineTo(4 * s, 44 * s)
      ..lineTo(4 * s, 38 * s)
      ..lineTo(28 * s, 22 * s)
      ..close();
  }

  /// Paints [path] onto [canvas]: outline first and underneath, so the shape
  /// reads against dark roofs and pale fields alike. A marker that vanishes
  /// over a river is no marker.
  static void paint(
    Canvas canvas,
    Path plane, {
    required Color fill,
    Color outline = const Color(0xFFFFFFFF),
    double outlineWidth = 5,
  }) {
    canvas.drawPath(
      plane,
      Paint()
        ..color = outline
        ..style = PaintingStyle.stroke
        ..strokeWidth = outlineWidth
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(plane, Paint()..color = fill);
  }

  /// The same outline as a PNG, for [MapLibreMapController.addImage].
  static Future<Uint8List> render({
    required Color fill,
    Color outline = const Color(0xFFFFFFFF),
  }) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    paint(
      canvas,
      path(pixels.toDouble()),
      fill: fill,
      outline: outline,
      outlineWidth: 5 * pixels / 64.0,
    );

    final ui.Image image =
        await recorder.endRecording().toImage(pixels, pixels);
    final ByteData? png =
        await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return png!.buffer.asUint8List();
  }
}
