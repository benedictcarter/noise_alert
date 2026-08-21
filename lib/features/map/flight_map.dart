import 'dart:async';

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../core/constants.dart';
import 'map_geometry.dart';
import 'map_layers.dart';
import 'plane_icon.dart';

/// Colours the map draws with. Fixed rather than taken from the theme: they sit
/// on an OpenStreetMap basemap that is light whichever theme the app is in, and
/// the same values have to work in the PNG that goes to the council.
class MapPalette {
  static const Color observer = Color(0xFF1B4965);
  static const Color highlight = Color(0xFFE85D04);
  static const Color other = Color(0xFF54606C);
}

/// A map of the ground around the listener with aircraft paths drawn on it.
///
/// One widget serves three jobs: the live view on the record screen, the still
/// of a finished event on the review screen, and the source of the picture
/// attached to the complaint. They differ only in what they are handed and
/// whether the user can move them.
class FlightMapView extends StatefulWidget {
  const FlightMapView({
    super.key,
    required this.latitude,
    required this.longitude,
    this.aircraft = const <MapAircraft>[],
    this.interactive = true,
    this.onControllerReady,
  });

  /// Where the listener is. This widget requires a centre; the no-fix case is
  /// [FlightMapPanel]'s to handle.
  final double latitude;
  final double longitude;

  final List<MapAircraft> aircraft;

  /// False wherever the map sits in a scrolling list -- which is both screens
  /// that show one. A map that accepts drags swallows the vertical scroll, and
  /// the page appears stuck whenever the user's thumb lands on it.
  final bool interactive;

  /// Handed the controller once the style is up and the layers exist, and null
  /// again when the map goes away. This is what the snapshot service holds.
  final void Function(MapLibreMapController?)? onControllerReady;

  @override
  State<FlightMapView> createState() => _FlightMapViewState();
}

class _FlightMapViewState extends State<FlightMapView> {
  MapLibreMapController? _controller;
  bool _layersReady = false;
  bool _styleTimedOut = false;
  Timer? _styleTimer;

  /// The span the camera was last set to, so the live map only moves when the
  /// picture would actually change. Recomputing the frame every three seconds
  /// and obeying it would leave the map permanently twitching.
  double? _cameraSpanM;

  MapFrame get _frame => MapFrame.around(
        widget.latitude,
        widget.longitude,
        points: framePoints(widget.aircraft),
      );

  @override
  void initState() {
    super.initState();
    _styleTimer = Timer(
      const Duration(milliseconds: MapConfig.styleTimeoutMs),
      () {
        if (mounted && !_layersReady) setState(() => _styleTimedOut = true);
      },
    );
  }

  @override
  void dispose() {
    _styleTimer?.cancel();
    widget.onControllerReady?.call(null);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant FlightMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_layersReady) unawaited(_pushData());
  }

  Future<void> _onStyleLoaded() async {
    final MapLibreMapController? c = _controller;
    if (c == null) return;

    try {
      await c.addImage(
        MapIds.planeImage,
        await PlaneIcon.render(fill: MapPalette.highlight),
      );
      await c.addImage(
        MapIds.planeImageDim,
        await PlaneIcon.render(fill: MapPalette.other),
      );

      await c.addGeoJsonSource(
        MapIds.observerSource,
        observerGeoJson(widget.latitude, widget.longitude),
      );
      await c.addGeoJsonSource(
        MapIds.trackSource,
        trackGeoJson(const <MapAircraft>[]),
      );
      await c.addGeoJsonSource(
        MapIds.planeSource,
        planeGeoJson(const <MapAircraft>[]),
      );

      // Order is draw order. Tracks under the house, the house under the
      // aeroplanes, labels over everything.
      await c.addLineLayer(
        MapIds.trackSource,
        MapIds.trackLine,
        LineLayerProperties(
          lineColor: _byHighlight(
            _hex(MapPalette.highlight),
            _hex(MapPalette.other),
          ),
          lineWidth: _byHighlight(4.0, 2.0),
          lineOpacity: _byHighlight(0.95, 0.45),
          lineCap: 'round',
          lineJoin: 'round',
        ),
      );

      await c.addCircleLayer(
        MapIds.observerSource,
        MapIds.observerHalo,
        const CircleLayerProperties(
          circleRadius: 11.0,
          circleColor: '#FFFFFF',
          circleOpacity: 0.9,
        ),
      );
      await c.addCircleLayer(
        MapIds.observerSource,
        MapIds.observerDot,
        CircleLayerProperties(
          circleRadius: 6.0,
          circleColor: _hex(MapPalette.observer),
        ),
      );

      await c.addSymbolLayer(
        MapIds.planeSource,
        MapIds.planeIcon,
        SymbolLayerProperties(
          iconImage: _byHighlight(MapIds.planeImage, MapIds.planeImageDim),
          iconSize: PlaneIcon.displayScale,
          iconRotate: <Object>['get', 'heading'],
          // Rotate with the ground, not with the screen. The aircraft has a
          // heading over the earth, and the line drawn behind it is on the
          // earth too.
          iconRotationAlignment: 'map',
          iconAllowOverlap: true,
          iconIgnorePlacement: true,
        ),
      );

      await c.addSymbolLayer(
        MapIds.planeSource,
        MapIds.planeLabel,
        SymbolLayerProperties(
          textField: <Object>['get', 'label'],
          // A font the style actually ships glyphs for. Name one it does not
          // and the labels silently fail to draw.
          textFont: const <String>['Noto Sans Bold'],
          textSize: 12.0,
          textOffset: const <double>[0, 1.6],
          textAnchor: 'top',
          textColor: _byHighlight(
            _hex(MapPalette.highlight),
            _hex(MapPalette.other),
          ),
          textHaloColor: '#FFFFFF',
          textHaloWidth: 1.6,
        ),
      );

      _styleTimer?.cancel();
      if (!mounted) return;
      setState(() {
        _layersReady = true;
        _styleTimedOut = false;
      });
      await _pushData(force: true);
      widget.onControllerReady?.call(c);
    } on Object {
      // A style that loaded but would not take a layer leaves the user exactly
      // where a style that never loaded does: no picture, and a complaint that
      // still goes.
      if (mounted) setState(() => _styleTimedOut = true);
    }
  }

  Future<void> _pushData({bool force = false}) async {
    final MapLibreMapController? c = _controller;
    if (c == null) return;
    try {
      await c.setGeoJsonSource(
        MapIds.observerSource,
        observerGeoJson(widget.latitude, widget.longitude),
      );
      await c.setGeoJsonSource(
        MapIds.trackSource,
        trackGeoJson(widget.aircraft),
      );
      await c.setGeoJsonSource(
        MapIds.planeSource,
        planeGeoJson(widget.aircraft),
      );
      await _fit(c, force: force);
    } on Object {
      // The map is a picture of the event, not part of capturing it. A failed
      // update leaves the previous frame up and costs nothing else.
    }
  }

  Future<void> _fit(MapLibreMapController c, {bool force = false}) async {
    final MapFrame frame = _frame;
    final double? was = _cameraSpanM;
    // A quarter is about a third of a zoom level. Below that the camera would
    // nudge back and forth on every poll for no visible gain.
    final bool worthMoving =
        force || was == null || (frame.spanM - was).abs() / was > 0.25;
    if (!worthMoving) return;
    _cameraSpanM = frame.spanM;
    await c.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(frame.south, frame.west),
          northeast: LatLng(frame.north, frame.east),
        ),
        left: 24,
        right: 24,
        top: 24,
        bottom: 24,
      ),
      duration: Duration(milliseconds: force ? 0 : 600),
    );
  }

  /// `["case", ["get", "highlighted"], hot, cold]` — one style expression, used
  /// by every layer, so "which aircraft is the complaint about" is answered in
  /// one place and the map never needs a second source to hold the other one.
  static List<Object> _byHighlight(Object hot, Object cold) => <Object>[
        'case',
        <Object>['get', 'highlighted'],
        hot,
        cold,
      ];

  static String _hex(Color c) {
    String part(double v) =>
        (v * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
    return '#${part(c.r)}${part(c.g)}${part(c.b)}';
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        MapLibreMap(
          styleString: MapConfig.styleUrl,
          initialCameraPosition: CameraPosition(
            target: LatLng(widget.latitude, widget.longitude),
            zoom: 14,
          ),
          onMapCreated: (MapLibreMapController c) => _controller = c,
          onStyleLoadedCallback: () => unawaited(_onStyleLoaded()),
          compassEnabled: false,
          logoEnabled: false,
          rotateGesturesEnabled: false,
          tiltGesturesEnabled: false,
          scrollGesturesEnabled: widget.interactive,
          zoomGesturesEnabled: widget.interactive,
          doubleClickZoomEnabled: widget.interactive,
          dragEnabled: false,
          myLocationEnabled: false,
        ),
        if (!_layersReady)
          IgnorePointer(
            child: Container(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              alignment: Alignment.center,
              child: _styleTimedOut
                  ? const _MapUnavailable()
                  : const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
            ),
          ),
      ],
    );
  }
}

class _MapUnavailable extends StatelessWidget {
  const _MapUnavailable();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.public_off, size: 28),
          const SizedBox(height: 8),
          Text(
            'Map unavailable offline',
            style: text.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            'Everything else about this recording is saved.',
            style: text.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

/// The map with its attribution line, and something sensible in place of it
/// when there is no fix to centre on.
///
/// The attribution is not a decoration: it is the whole of what OpenFreeMap
/// asks in return for the tiles. Keeping it in the same widget as the map means
/// a map cannot be put on a screen without it.
class FlightMapPanel extends StatelessWidget {
  const FlightMapPanel({
    super.key,
    required this.latitude,
    required this.longitude,
    this.aircraft = const <MapAircraft>[],
    this.height,
    this.interactive = true,
    this.emptyMessage = 'No location fix, so there is no map to draw.',
    this.onControllerReady,
  });

  final double? latitude;
  final double? longitude;
  final List<MapAircraft> aircraft;

  /// A fixed height, or null to take whatever the parent has left.
  ///
  /// Null is how the record screen gets a map that grows and shrinks with the
  /// banners and the status line above it, which is what lets that screen hold
  /// everything at once without a scrollbar. Requires a parent that bounds it:
  /// [Expanded], or a [SizedBox].
  final double? height;
  final bool interactive;
  final String emptyMessage;
  final void Function(MapLibreMapController?)? onControllerReady;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final double? lat = latitude;
    final double? lon = longitude;

    final Widget body = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: lat == null || lon == null
          ? Container(
              color: theme.colorScheme.surfaceContainerHighest,
              alignment: Alignment.center,
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const Icon(Icons.location_off_outlined, size: 28),
                  const SizedBox(height: 8),
                  Text(
                    emptyMessage,
                    style: theme.textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : FlightMapView(
              latitude: lat,
              longitude: lon,
              aircraft: aircraft,
              interactive: interactive,
              onControllerReady: onControllerReady,
            ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (height == null)
          Expanded(child: body)
        else
          SizedBox(height: height, child: body),
        if (lat != null && lon != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              MapConfig.attribution,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
