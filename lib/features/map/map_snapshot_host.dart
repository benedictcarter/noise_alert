import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/constants.dart';
import '../../data/map/map_image_service.dart';

/// Renders basemap images for the complaint, out of sight.
///
/// A dedicated map rather than the one on screen, for two reasons.
///
/// MapLibre's `takeSnapshot` does not photograph the map you are looking at: on
/// both platforms it hands the job to `MapSnapshotter`, an independent renderer
/// given only the style URL and the camera. Runtime layers are absent from the
/// result, so the on-screen map's tracks and markers would not appear in the
/// picture anyway, and they are painted over the top in Dart instead.
///
/// And the picture needs its own camera. The record screen is framed on live
/// traffic and the review screen on one event, neither of which is the frame
/// the letter wants; retargeting whichever map happened to be mounted would
/// lurch under the user's thumb at the moment they pressed send.
///
/// What is left is a map that has to exist but not be seen. It is scaled into
/// a single pixel in the corner rather than hidden with [Offstage], because a
/// platform view that is never laid out or painted is a platform view that may
/// never be created, and this one only has to get as far as loading its style.
class MapSnapshotHost extends StatefulWidget {
  const MapSnapshotHost({
    super.key,
    required this.service,
    required this.child,
  });

  final MapImageService service;
  final Widget child;

  @override
  State<MapSnapshotHost> createState() => _MapSnapshotHostState();
}

class _MapSnapshotHostState extends State<MapSnapshotHost>
    implements MapBasemapSource {
  /// The single request in flight, if any.
  _SnapshotRequest? _request;

  /// Serialises callers. Two complaints composed at once would fight over the
  /// one map, and the second would get the first one's camera.
  Future<void> _queue = Future<void>.value();

  @override
  void initState() {
    super.initState();
    widget.service.basemap = this;
  }

  @override
  void didUpdateWidget(covariant MapSnapshotHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.service, widget.service)) {
      if (identical(oldWidget.service.basemap, this)) {
        oldWidget.service.basemap = null;
      }
      widget.service.basemap = this;
    }
  }

  @override
  void dispose() {
    if (identical(widget.service.basemap, this)) {
      widget.service.basemap = null;
    }
    _request?.complete(null);
    super.dispose();
  }

  @override
  Future<Uint8List?> capture({
    required double latitude,
    required double longitude,
    required double zoom,
    required int width,
    required int height,
  }) {
    final Completer<Uint8List?> done = Completer<Uint8List?>();
    _queue = _queue.then((_) async {
      if (!mounted) {
        done.complete(null);
        return;
      }
      final _SnapshotRequest request = _SnapshotRequest(
        latitude: latitude,
        longitude: longitude,
        zoom: zoom,
        width: width,
        height: height,
      );
      setState(() => _request = request);
      // No "style failed" callback exists, so a style that never arrives has
      // to be timed out or the user waits on a send that will not happen.
      final Uint8List? png = await request.result
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () => null,
          )
          .catchError((Object _) => null);
      if (mounted) setState(() => _request = null);
      done.complete(png);
    });
    return done.future;
  }

  Future<void> _onStyleLoaded(
    _SnapshotRequest request,
    MapLibreMapController controller,
  ) async {
    try {
      // Tiles are fetched lazily, and a snapshot taken before they land is a
      // grey rectangle with a perfectly accurate flight path drawn on it.
      await controller.waitUntilMapTilesAreLoaded();
      request.complete(
        await controller.takeSnapshot(
          width: request.width,
          height: request.height,
        ),
      );
    } on Object {
      request.complete(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final _SnapshotRequest? request = _request;
    return Stack(
      children: <Widget>[
        widget.child,
        if (request != null)
          Positioned(
            left: 0,
            bottom: 0,
            width: 1,
            height: 1,
            child: IgnorePointer(
              child: FittedBox(
                fit: BoxFit.fill,
                clipBehavior: Clip.hardEdge,
                child: SizedBox(
                  // A plausible map size. The snapshot is rendered offscreen at
                  // the size actually asked for, so this only has to be big
                  // enough that the platform view is real.
                  width: 320,
                  height: 240,
                  child: MapLibreMap(
                    key: ValueKey<int>(request.id),
                    styleString: MapConfig.styleUrl,
                    initialCameraPosition: CameraPosition(
                      target: LatLng(request.latitude, request.longitude),
                      zoom: request.zoom,
                    ),
                    onStyleLoadedCallback: () {
                      final MapLibreMapController? c = request.controller;
                      if (c != null) unawaited(_onStyleLoaded(request, c));
                    },
                    onMapCreated: (MapLibreMapController c) =>
                        request.controller = c,
                    compassEnabled: false,
                    logoEnabled: false,
                    scrollGesturesEnabled: false,
                    zoomGesturesEnabled: false,
                    rotateGesturesEnabled: false,
                    tiltGesturesEnabled: false,
                    dragEnabled: false,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SnapshotRequest {
  _SnapshotRequest({
    required this.latitude,
    required this.longitude,
    required this.zoom,
    required this.width,
    required this.height,
  }) : id = ++_counter;

  static int _counter = 0;

  /// Forces a fresh platform view per request, so a second complaint cannot be
  /// served the first one's camera.
  final int id;

  final double latitude;
  final double longitude;
  final double zoom;
  final int width;
  final int height;

  MapLibreMapController? controller;

  final Completer<Uint8List?> _completer = Completer<Uint8List?>();
  Future<Uint8List?> get result => _completer.future;

  void complete(Uint8List? png) {
    if (!_completer.isCompleted) _completer.complete(png);
  }
}
