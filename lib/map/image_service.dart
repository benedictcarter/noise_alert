import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:noise_alert/map/config.dart';
import 'package:noise_alert/flights/aircraft.dart';
import 'package:noise_alert/flights/match.dart';
import 'package:noise_alert/snap/snap.dart';
import 'package:noise_alert/map/geometry.dart';
import 'package:noise_alert/map/layers.dart';
import 'package:noise_alert/map/overlay.dart';
import 'package:noise_alert/map/projection.dart';

/// Something that can produce a plain basemap image at a given camera.
///
/// Implemented by the hidden map in the widget tree, because MapLibre will only
/// render for a live map instance. Kept abstract so nothing below this line
/// knows that, and so the whole thing is a null check away from being absent.
abstract class MapBasemapSource {
  Future<Uint8List?> capture({
    required double latitude,
    required double longitude,
    required double zoom,
    required int width,
    required int height,
  });
}

/// Turns a snap into the picture attached to the complaint.
///
/// This is the point of the map feature. A council can argue with a decibel
/// figure; it is much harder to argue with a drawing of the flight path over
/// the complainant's house, to scale, with the time on it.
///
/// Written to the application *support* directory, not documents: that is the
/// only path `flutter_email_sender`'s FileProvider declares on Android, and an
/// attachment from anywhere else makes the whole send fail (see
/// LESSONS_LEARNT).
class MapImageService {
  MapImageService();

  /// Set by the hidden map when the app starts, and cleared when it goes.
  /// Null means no picture, never a failed send.
  MapBasemapSource? basemap;

  static final DateFormat _caption = DateFormat('HH:mm on d MMMM yyyy');

  /// Pale paper, for the case where the tiles could not be fetched. The
  /// geometry is still true and still worth sending; it just has no streets
  /// under it.
  static const Color _noBasemap = Color(0xFFEDEFF2);

  /// Path to a PNG of [snap]'s flight path, or null if there is nothing to
  /// draw or the render failed.
  ///
  /// Never throws. A missing map must cost the user a picture, not their
  /// complaint.
  Future<String?> renderForEmail(Snap snap) async {
    final double? lat = snap.latitude;
    final double? lon = snap.longitude;
    // No fix means no centre, and a map centred on a guess is worse than no
    // map: it would put the complainant's house in the wrong street.
    if (lat == null || lon == null) return null;

    try {
      final List<MapAircraft> aircraft = aircraftFor(snap);
      final MercatorView view = viewFor(lat, lon, aircraft);

      final Uint8List? tiles = await basemap?.capture(
        latitude: view.centreLat,
        longitude: view.centreLon,
        zoom: view.zoom,
        width: MapConfig.emailImageWidth,
        height: MapConfig.emailImageHeight,
      );

      final ui.Image? base = tiles == null ? null : await _decode(tiles);

      // Android's snapshotter renders at the size asked for; iOS renders at
      // the screen scale, so the same request comes back two or three times
      // bigger. Measuring the image rather than assuming is what keeps the
      // overlay on top of the right streets.
      final int width = base?.width ?? MapConfig.emailImageWidth;
      final int height = base?.height ?? MapConfig.emailImageHeight;
      final double scale = width / MapConfig.emailImageWidth;

      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      if (base == null) {
        canvas.drawRect(
          Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
          Paint()..color = _noBasemap,
        );
      } else {
        canvas.drawImage(base, Offset.zero, Paint());
      }

      MapOverlay(
        view: view.forImage(
          imageWidth: width.toDouble(),
          imageHeight: height.toDouble(),
          requestedWidth: MapConfig.emailImageWidth.toDouble(),
        ),
        aircraft: aircraft,
        observerLat: lat,
        observerLon: lon,
        caption: captionFor(snap),
        scale: scale,
      ).paint(canvas);

      base?.dispose();

      final ui.Image image =
          await recorder.endRecording().toImage(width, height);
      final ByteData? png =
          await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (png == null) return null;

      final Directory dir = Directory(
        p.join((await getApplicationSupportDirectory()).path, 'maps'),
      );
      await dir.create(recursive: true);
      final File file = File(p.join(dir.path, '${snap.id}-map.png'));
      await file.writeAsBytes(png.buffer.asUint8List(), flush: true);
      return file.path;
    } on Object {
      return null;
    }
  }

  /// The aircraft the picture should carry: the one the complaint names, drawn
  /// boldly, and the rest of the traffic behind it.
  ///
  /// The others are not padding. "This is the aircraft, and here is everything
  /// else that was in the sky at the time" is a stronger claim than a single
  /// line with nothing to compare it against.
  static List<MapAircraft> aircraftFor(Snap snap) {
    final FlightMatch? match = snap.match;
    if (match == null) return const <MapAircraft>[];
    final FlightCandidate? chosen = snap.confirmedCandidate;
    return <MapAircraft>[
      for (final FlightCandidate c in match.candidates)
        MapAircraft.ofCandidate(
          c,
          highlighted:
              chosen != null && c.aircraft.icao24 == chosen.aircraft.icao24,
        ),
    ];
  }

  /// The camera for the emailed image.
  ///
  /// Fitted to a shorter box than the image, so the footer strip cannot end up
  /// sitting over the end of the flight path.
  static MercatorView viewFor(
    double latitude,
    double longitude,
    List<MapAircraft> aircraft,
  ) {
    const double width = MapConfig.emailImageWidth * 1.0;
    const double height = MapConfig.emailImageHeight * 1.0;
    final MapFrame frame = MapFrame.around(
      latitude,
      longitude,
      points: framePoints(aircraft),
    );
    final MercatorView fitted = MercatorView.fit(
      frame,
      width: width,
      height: height - 100,
    );
    return MercatorView(
      centreLat: fitted.centreLat,
      centreLon: fitted.centreLon,
      zoom: fitted.zoom,
      width: width,
      height: height,
    );
  }

  /// One line saying what the picture shows.
  ///
  /// It says "closest match" in as many words, because the picture is the part
  /// of the complaint most likely to be read on its own, and the identification
  /// has not been independently verified.
  static String captionFor(Snap snap) {
    final String when = _caption.format(snap.recordedAt);
    final FlightCandidate? c = snap.confirmedCandidate;
    if (c == null) {
      return 'Aircraft noise reported at $when. No aircraft identified.';
    }
    final AircraftSample a = c.aircraft;
    return 'Closest match ${a.displayName} at $when: '
        '${c.horizontalRangeM.round()} m away, '
        '${c.heightAboveObserverFt.round()} ft overhead.';
  }

  static Future<ui.Image> _decode(Uint8List bytes) async {
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    codec.dispose();
    return frame.image;
  }
}
