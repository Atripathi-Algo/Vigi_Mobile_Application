package com.algoanalytics.vigil

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.graphics.Color
import android.net.Uri
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** Shared rendering. The Dart side saves plain strings under these keys (lib/services/home_widgets.dart). */
private object WidgetUi {
    fun accent(d: SharedPreferences): Int =
        try { Color.parseColor(d.getString("accent", "#3FB6FF")) } catch (_: Exception) { Color.parseColor("#3FB6FF") }

    fun open(context: Context, uri: String) =
        HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java, Uri.parse(uri))

    fun background(context: Context, uri: String) =
        HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse(uri))
}

class VigilObjectivesWidget : HomeWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray, d: SharedPreferences) {
        for (id in ids) {
            val v = RemoteViews(context.packageName, R.layout.widget_objectives)
            v.setTextColor(R.id.w_title, context.getColor(R.color.w_accent))
            v.setTextViewText(R.id.w_ready, "READY " + d.getString("ready", "--"))
            v.setTextViewText(R.id.w_next, d.getString("next", "No data"))
            for ((i, rid) in listOf(R.id.w_o1, R.id.w_o2, R.id.w_o3).withIndex()) {
                val n = i + 1
                val title = d.getString("o${n}_t", "") ?: ""
                val done = d.getString("o${n}_done", "0") == "1"
                val oid = d.getString("o${n}_id", "") ?: ""
                v.setTextViewText(rid, if (title.isEmpty()) "" else (if (done) "\u25A0  " else "\u25A1  ") + title)
                v.setTextColor(rid, context.getColor(if (done) R.color.w_muted else R.color.w_text))
                if (oid.isNotEmpty()) v.setOnClickPendingIntent(rid, WidgetUi.background(context, "vigil://toggle?id=$oid"))
            }
            v.setTextViewText(R.id.w_stats, d.getString("stats", ""))
            v.setInt(R.id.w_btn_capture, "setBackgroundResource", R.drawable.widget_btn_primary)
            v.setTextColor(R.id.w_btn_capture, Color.WHITE)
            v.setOnClickPendingIntent(R.id.w_btn_water, WidgetUi.background(context, "vigil://water?ml=250"))
            v.setOnClickPendingIntent(R.id.w_btn_capture, WidgetUi.open(context, "vigil://capture"))
            val open = WidgetUi.open(context, "vigil://ops")
            v.setOnClickPendingIntent(R.id.w_title, open)
            v.setOnClickPendingIntent(R.id.w_ready, open)
            v.setOnClickPendingIntent(R.id.w_next, open)
            v.setOnClickPendingIntent(R.id.w_stats, open)
            manager.updateAppWidget(id, v)
        }
    }
}

class VigilSmallWidget : HomeWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray, d: SharedPreferences) {
        for (id in ids) {
            val v = RemoteViews(context.packageName, R.layout.widget_small)
            v.setTextColor(R.id.w_ready, context.getColor(R.color.w_accent))
            v.setTextViewText(R.id.w_ready, d.getString("ready", "--"))
            v.setTextViewText(R.id.w_stats, d.getString("stats_small", ""))
            v.setOnClickPendingIntent(R.id.w_btn_water, WidgetUi.background(context, "vigil://water?ml=250"))
            val open = WidgetUi.open(context, "vigil://open")
            v.setOnClickPendingIntent(R.id.w_root, open)
            v.setOnClickPendingIntent(R.id.w_ready, open)
            v.setOnClickPendingIntent(R.id.w_title, open)
            v.setOnClickPendingIntent(R.id.w_stats, open)
            manager.updateAppWidget(id, v)
        }
    }
}


/** K - Water (2x1): today's water and a +250 ml button that logs without opening the app. */
class VigilWaterWidget : HomeWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray, d: SharedPreferences) {
        for (id in ids) {
            val v = RemoteViews(context.packageName, R.layout.widget_water)
            v.setTextViewText(R.id.w_amount, d.getString("water_amount", "--"))
            v.setOnClickPendingIntent(R.id.w_btn, WidgetUi.background(context, "vigil://water?ml=250"))
            v.setOnClickPendingIntent(R.id.w_root, WidgetUi.open(context, "vigil://open"))
            manager.updateAppWidget(id, v)
        }
    }
}

/** K - Next up (2x1): the next event and how long until it. */
class VigilNextOpWidget : HomeWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray, d: SharedPreferences) {
        for (id in ids) {
            val v = RemoteViews(context.packageName, R.layout.widget_nextop)
            v.setTextViewText(R.id.w_title, d.getString("next_title", "Nothing next"))
            v.setTextViewText(R.id.w_when, d.getString("next_when", ""))
            v.setOnClickPendingIntent(R.id.w_root, WidgetUi.open(context, "vigil://timeline"))
            manager.updateAppWidget(id, v)
        }
    }
}

/** K - Ask (4x1): a bar that opens the K chat; the K button opens it ready to talk. */
class VigilAskWidget : HomeWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray, d: SharedPreferences) {
        for (id in ids) {
            val v = RemoteViews(context.packageName, R.layout.widget_ask)
            v.setOnClickPendingIntent(R.id.w_root, WidgetUi.open(context, "vigil://ask"))
            v.setOnClickPendingIntent(R.id.w_bar, WidgetUi.open(context, "vigil://ask"))
            v.setOnClickPendingIntent(R.id.w_mic, WidgetUi.open(context, "vigil://voice"))
            manager.updateAppWidget(id, v)
        }
    }
}

/** K - Spend (2x2): this month's spending. Masked until the user allows amounts in Settings. */
class VigilSpendWidget : HomeWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray, d: SharedPreferences) {
        for (id in ids) {
            val v = RemoteViews(context.packageName, R.layout.widget_spend)
            v.setTextViewText(R.id.w_amount, d.getString("spend_amount", "\u20B9 \u2022\u2022\u2022\u2022"))
            v.setTextViewText(R.id.w_of, d.getString("spend_of", "Tap to open"))
            v.setOnClickPendingIntent(R.id.w_root, WidgetUi.open(context, "vigil://money"))
            manager.updateAppWidget(id, v)
        }
    }
}

/** K - Garage (4x2): the first bike: odometer, mileage and cost, the next reminder, and a Log fuel button. */
class VigilGarageWidget : HomeWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray, d: SharedPreferences) {
        for (id in ids) {
            val v = RemoteViews(context.packageName, R.layout.widget_garage)
            v.setTextViewText(R.id.w_name, d.getString("garage_name", "Garage"))
            v.setTextViewText(R.id.w_odo, d.getString("garage_odo", "No bike yet"))
            v.setTextViewText(R.id.w_stats, d.getString("garage_stats", "Add one in Plan, Garage"))
            v.setTextViewText(R.id.w_next, d.getString("garage_next", ""))
            val open = WidgetUi.open(context, "vigil://garage")
            v.setOnClickPendingIntent(R.id.w_root, open)
            v.setOnClickPendingIntent(R.id.w_btn, open)
            manager.updateAppWidget(id, v)
        }
    }
}
