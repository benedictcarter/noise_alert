package com.benedictcarter.noise_alert

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * A 1x1 home-screen button that starts a capture without going through the app
 * first.
 *
 * A widget cannot record on its own — the microphone belongs to a foreground
 * process — so the tap launches the activity with [EXTRA_SNAP_NOW] and the
 * Flutter side arms and captures as soon as the stream is live. The user still
 * sees the app come up, but they do not have to find and press anything.
 *
 * The measurement is honest about what this costs: a cold start has no pre-roll,
 * so there is no background level to compare against and the letter says so.
 */
class SnapWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        appWidgetIds.forEach { id ->
            val intent = Intent(context, MainActivity::class.java).apply {
                action = Intent.ACTION_MAIN
                addCategory(Intent.CATEGORY_LAUNCHER)
                putExtra(EXTRA_SNAP_NOW, true)
                // SINGLE_TOP so a tap while the app is already open is delivered
                // to onNewIntent rather than stacking a second activity;
                // CLEAR_TOP so it lands on the snap screen and not on whatever
                // was pushed on top of it.
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP
            }

            // A unique request code per widget id, otherwise the second widget
            // silently reuses the first one's PendingIntent.
            val pending = PendingIntent.getActivity(
                context,
                id,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )

            val views = RemoteViews(context.packageName, R.layout.snap_widget).apply {
                setOnClickPendingIntent(R.id.snap_widget_root, pending)
            }
            appWidgetManager.updateAppWidget(id, views)
        }
    }

    companion object {
        const val EXTRA_SNAP_NOW = "snap_now"
    }
}
