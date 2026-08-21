import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../domain/snap.dart';
import '../../features/chart/level_chart.dart';

/// Turns a snap's stored level trace into a PNG for the complaint email.
///
/// Written to the application *support* directory, not documents: that is the
/// only path `flutter_email_sender`'s FileProvider declares on Android, and an
/// attachment from anywhere else makes the whole send fail (see
/// LESSONS_LEARNT).
class ChartImageService {
  const ChartImageService();

  static const Size chartSize = Size(720, 300);

  /// Path to a PNG of [snap]'s level trace, or null if there is nothing to draw
  /// or the render failed.
  ///
  /// Never throws: a missing chart must cost the user a picture, not their
  /// complaint.
  Future<String?> renderForEmail(Snap snap) async {
    if (!snap.metrics.hasTrace) return null;

    try {
      final ui.Image image = await renderLevelChart(
        painter: LevelChartPainter(
          levels: snap.metrics.levelTrace,
          intervalMs: snap.metrics.traceIntervalMs,
          palette: LevelChartPalette.forEmail(),
          pressAtSeconds: snap.metrics.preRollSeconds,
          ambientDb: snap.metrics.ambientLa90Db,
          markedAtSeconds: snap.markedPeakMs == null
              ? null
              : snap.markedPeakMs! / 1000,
        ),
        size: chartSize,
      );

      final ByteData? png =
          await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (png == null) return null;

      final Directory dir = Directory(
        p.join((await getApplicationSupportDirectory()).path, 'charts'),
      );
      await dir.create(recursive: true);
      final File file = File(p.join(dir.path, '${snap.id}-level.png'));
      await file.writeAsBytes(png.buffer.asUint8List(), flush: true);
      return file.path;
    } on Object {
      return null;
    }
  }
}
