import 'dart:async';

import 'package:flutter/services.dart';

/// Requests to capture immediately, arriving from the home-screen widget.
///
/// Two delivery paths, matching Android's two: a cold launch has already
/// happened by the time Dart is listening, so that one is *pulled* once at
/// startup ([consumePending]); a tap while the app is running is *pushed* over
/// the channel. Relying on the push alone would make the widget work only while
/// the app is already open, which is the opposite of the point.
class QuickSnapChannel {
  QuickSnapChannel({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('noise_alert/quick_snap') {
    _channel.setMethodCallHandler(_onCall);
  }

  final MethodChannel _channel;
  final StreamController<void> _requests = StreamController<void>.broadcast();

  /// Fires every time the widget is tapped while the app is running.
  Stream<void> get requests => _requests.stream;

  Future<void> _onCall(MethodCall call) async {
    if (call.method == 'snapNow' && !_requests.isClosed) {
      _requests.add(null);
    }
  }

  /// True at most once per widget tap that launched the app cold.
  ///
  /// Consuming clears it, so a later hot restart of the Dart isolate does not
  /// fire a second unwanted capture.
  Future<bool> consumePending() async {
    try {
      return await _channel.invokeMethod<bool>('consumePendingSnap') ?? false;
    } on MissingPluginException {
      // iOS has no widget yet, and the tests have no platform channel at all.
      return false;
    } on PlatformException {
      return false;
    }
  }

  void dispose() => _requests.close();
}
