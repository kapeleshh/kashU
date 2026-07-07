package com.kashu.kashu

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetPlugin
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Home screen widget that displays KashU portfolio summary.
 *
 * Data is written by Flutter via the home_widget package into
 * SharedPreferences. This provider reads those values on every
 * update and renders them into the widget layout.
 *
 * Keys written by WidgetUpdateService.dart:
 *   portfolio_value  – formatted value string (e.g. "₹12.5L")
 *   gain_loss        – formatted absolute gain/loss (e.g. "₹1.2L")
 *   gain_loss_pct    – percentage string (e.g. "+10.56%")
 *   is_positive      – boolean; true = green, false = red
 */
class PortfolioWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray
    ) {
        for (widgetId in appWidgetIds) {
            updateWidget(context, appWidgetManager, widgetId)
        }
    }

    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        // Triggered by HomeWidget.updateWidget() from Flutter
        if (intent.action == AppWidgetManager.ACTION_APPWIDGET_UPDATE) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(
                android.content.ComponentName(context, PortfolioWidgetProvider::class.java)
            )
            for (id in ids) updateWidget(context, manager, id)
        }
    }

    companion object {
        fun updateWidget(
            context: Context,
            appWidgetManager: AppWidgetManager,
            widgetId: Int
        ) {
            val prefs = HomeWidgetPlugin.getData(context)

            val value   = prefs.getString("portfolio_value", "—") ?: "—"
            val gain    = prefs.getString("gain_loss", "—") ?: "—"
            val pct     = prefs.getString("gain_loss_pct", "") ?: ""
            val isPos   = prefs.getBoolean("is_positive", true)

            val gainColor = if (isPos) 0xFF4CAF50.toInt() else 0xFFF44336.toInt()
            val gainPrefix = if (isPos) "▲ " else "▼ "

            val time = SimpleDateFormat("h:mm a", Locale.getDefault()).format(Date())

            val views = RemoteViews(context.packageName, R.layout.portfolio_widget)
            views.setTextViewText(R.id.widget_portfolio_value, value)
            views.setTextViewText(R.id.widget_gain_loss, "$gainPrefix$gain")
            views.setTextColor(R.id.widget_gain_loss, gainColor)
            views.setTextViewText(R.id.widget_gain_loss_pct, pct)
            views.setTextViewText(R.id.widget_updated_at, "Updated $time")

            // Tap widget → open app
            val launchIntent = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
            if (launchIntent != null) {
                val pending = android.app.PendingIntent.getActivity(
                    context, 0, launchIntent,
                    android.app.PendingIntent.FLAG_UPDATE_CURRENT or
                            android.app.PendingIntent.FLAG_IMMUTABLE
                )
                views.setOnClickPendingIntent(R.id.widget_portfolio_value, pending)
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }
}
