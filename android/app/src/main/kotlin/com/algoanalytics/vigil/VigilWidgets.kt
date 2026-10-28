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
            val accent = WidgetUi.accent(d)
            v.setTextColor(R.id.w_title, accent)
            v.setTextViewText(R.id.w_ready, "READY " + d.getString("ready", "--"))
            v.setTextViewText(R.id.w_next, d.getString("next", "No data"))
            for ((i, rid) in listOf(R.id.w_o1, R.id.w_o2, R.id.w_o3).withIndex()) {
                val n = i + 1
                val title = d.getString("o${n}_t", "") ?: ""
                val done = d.getString("o${n}_done", "0") == "1"
                val oid = d.getString("o${n}_id", "") ?: ""
                v.setTextViewText(rid, if (title.isEmpty()) "" else (if (done) "\u25A0  " else "\u25A1  ") + title)
                v.setTextColor(rid, if (done) Color.parseColor("#7A8FB0") else Color.parseColor("#E6F0FF"))
                if (oid.isNotEmpty()) v.setOnClickPendingIntent(rid, WidgetUi.background(context, "vigil://toggle?id=$oid"))
            }
            v.setTextViewText(R.id.w_stats, d.getString("stats", ""))
            v.setInt(R.id.w_btn_capture, "setBackgroundColor", accent)
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
            v.setTextColor(R.id.w_ready, WidgetUi.accent(d))
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
