import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:noise_alert/map/geometry.dart';

/// Web Mercator, at a known camera, for a known image size.
///
/// This exists because `takeSnapshot` does not photograph the map on screen.
/// Both platforms hand the job to MapLibre's own `MapSnapshotter`, which is an
/// independent renderer given nothing but the style URL and the camera: every
/// GeoJSON source, layer and image added at run time is absent from the result.
/// So the basemap comes from the snapshotter and everything drawn on it comes
/// from Dart, and the two only line up if Dart reproduces the same projection.
class MercatorView {
  const MercatorView({
    required this.centreLat,
    required this.centreLon,
    required this.zoom,
    required this.width,
    required this.height,
    this.tilePixels = tileSize,
  });

  /// MapLibre's world tile size, from the native core (`util::tileSize`). The
  /// world is `tileSize * 2^zoom` pixels across at a scale of 1.
  static const double tileSize = 512;

  final double centreLat;
  final double centreLon;
  final double zoom;

  /// Size of the image being drawn into, in the same pixels as [tilePixels].
  final double width;
  final double height;

  /// [tileSize] multiplied by the renderer's scale.
  ///
  /// Android's snapshotter defaults to a scale of 1, so its PNG comes back at
  /// exactly the requested size; iOS defaults to the screen scale, so the same
  /// request comes back two or three times larger. Rather than guess, the
  /// caller measures the PNG it was actually given and scales this to match;
  /// see [forImage].
  final double tilePixels;

  double get worldSize => tilePixels * math.pow(2, zoom);

  /// The same camera, re-expressed for an image of [imageWidth] pixels that was
  /// requested at [requestedWidth].
  MercatorView forImage({
    required double imageWidth,
    required double imageHeight,
    required double requestedWidth,
  }) {
    final double scale = imageWidth / requestedWidth;
    return MercatorView(
      centreLat: centreLat,
      centreLon: centreLon,
      zoom: zoom,
      width: imageWidth,
      height: imageHeight,
      tilePixels: tileSize * scale,
    );
  }

  /// Normalised Mercator y, 0 at the north edge and 1 at the south.
  static double mercatorY(double latitude) {
    final double lat = latitude.clamp(-85.05112878, 85.05112878);
    final double s = math.sin(lat * math.pi / 180.0);
    return 0.5 - math.log((1 + s) / (1 - s)) / (4 * math.pi);
  }

  static double mercatorX(double longitude) => (longitude + 180.0) / 360.0;

  /// Pixel position of a coordinate within the image, origin top left.
  Offset project(double latitude, double longitude) {
    final double w = worldSize;
    return Offset(
      width / 2 + (mercatorX(longitude) - mercatorX(centreLon)) * w,
      height / 2 + (mercatorY(latitude) - mercatorY(centreLat)) * w,
    );
  }

  /// Metres covered by one pixel, for the scale bar.
  ///
  /// Mercator stretches with latitude, so this is only true along the parallel
  /// through the centre of the image, which, the image being a few hundred
  /// metres of one street, is true enough everywhere in it.
  double get metresPerPixel =>
      (2 * math.pi * 6378137.0 * math.cos(centreLat * math.pi / 180.0)) /
      worldSize;

  /// The camera that fits [frame] into an image of [width] by [height].
  ///
  /// Zoom is a property of the camera, not of the image, so this is computed
  /// once against the requested logical size and stays right however many
  /// actual pixels the platform hands back.
  static MercatorView fit(
    MapFrame frame, {
    required double width,
    required double height,
    double paddingPx = 28,
    double minZoom = 3,
    double maxZoom = 18,
  }) {
    final double usableW = math.max(width - paddingPx * 2, 16);
    final double usableH = math.max(height - paddingPx * 2, 16);

    final double spanX = (mercatorX(frame.east) - mercatorX(frame.west)).abs();
    final double spanY =
        (mercatorY(frame.south) - mercatorY(frame.north)).abs();

    double zoomFor(double usable, double span) =>
        span <= 0 ? maxZoom : _log2(usable / (tileSize * span));

    final double zoom = math
        .min(zoomFor(usableW, spanX), zoomFor(usableH, spanY))
        .clamp(minZoom, maxZoom);

    return MercatorView(
      centreLat: frame.latitude,
      centreLon: frame.longitude,
      zoom: zoom,
      width: width,
      height: height,
    );
  }

  static double _log2(double x) => math.log(x) / math.ln2;
}
