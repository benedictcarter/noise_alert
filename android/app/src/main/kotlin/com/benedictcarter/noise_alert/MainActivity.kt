package com.benedictcarter.noise_alert

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter app and relays home-screen widget taps to it.
 *
 * Two separate paths, because Android has two: a cold launch carries the extra
 * on the intent the activity is created with, and a tap while the app is
 * already running arrives at [onNewIntent]. Handling only the first is the
 * usual bug: the widget then works exactly once per app lifetime.
 */
class MainActivity : FlutterActivity() {

    private var channel: MethodChannel? = null

    /**
     * Set by a cold-launch intent and cleared when Dart collects it. Dart is
     * not listening yet at that point, so the request has to wait rather than
     * be delivered and dropped.
     */
    private var pendingSnap = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    // Called once the Dart side is ready to act on it.
                    "consumePendingSnap" -> {
                        result.success(pendingSnap)
                        pendingSnap = false
                    }
                    else -> result.notImplemented()
                }
            }
        }

        pendingSnap = pendingSnap || intent.hasSnapRequest()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (!intent.hasSnapRequest()) return

        val live = channel
        if (live != null) {
            live.invokeMethod("snapNow", null)
        } else {
            pendingSnap = true
        }
    }

    private fun Intent.hasSnapRequest() =
        getBooleanExtra(SnapWidgetProvider.EXTRA_SNAP_NOW, false)

    companion object {
        private const val CHANNEL = "noise_alert/quick_snap"
    }
}
