package com.bradcowdrey.meridian

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.os.Build
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import java.time.Instant
import java.time.ZoneId

/**
 * Home screen widgets: small (one city), medium (two) and large (five), each city with its time
 * (a live TextClock in the city's zone, so it never goes stale) and the hour before, now and the
 * hour after as day-and-night tiles. The tiles refresh on the hour and when the time or zone changes.
 */
object MeridianWidgets {
    enum class Size(val cities: Int) { SMALL(1), MEDIUM(2), LARGE(5) }

    private val providers = mapOf(
        Size.SMALL to SmallWidget::class.java,
        Size.MEDIUM to MediumWidget::class.java,
        Size.LARGE to LargeWidget::class.java,
    )

    fun updateAll(context: Context) {
        val manager = AppWidgetManager.getInstance(context)
        val places = Store.loadPlaces(context) ?: emptyList()
        val use24h = Store.use24h(context)
        providers.forEach { (size, cls) ->
            val ids = manager.getAppWidgetIds(ComponentName(context, cls))
            if (ids.isNotEmpty()) manager.updateAppWidget(ids, views(context, size, places, use24h, Instant.now(), ZoneId.systemDefault(), live = true))
        }
        scheduleNextHour(context)
    }

    /** The widget's views. [live] uses ticking clocks; previews (the store screenshot) use fixed text. */
    fun views(context: Context, size: Size, places: List<Place>, use24h: Boolean, now: Instant, home: ZoneId, live: Boolean = false): RemoteViews {
        val root = RemoteViews(context.packageName, if (size == Size.LARGE) R.layout.widget_root_large else R.layout.widget_root)
        root.removeAllViews(R.id.content)
        val cities = places.take(size.cities)
        if (size == Size.LARGE) {
            // The header and the Now column's outline only over cities.
            val shown = if (cities.isEmpty()) View.GONE else View.VISIBLE
            root.setViewVisibility(R.id.header, shown)
            root.setViewVisibility(R.id.now_overlay, shown)
        }
        if (cities.isEmpty()) {
            root.addView(R.id.content, RemoteViews(context.packageName, R.layout.widget_empty))
        } else if (size == Size.LARGE) {
            cities.forEach { root.addView(R.id.content, cell(context, R.layout.widget_row, it, use24h, now, home, live, 22f)) }
        } else {
            // Medium: two cities with a hairline between them.
            val clockSize = if (size == Size.SMALL) 40f else 34f
            cities.forEachIndexed { i, place ->
                if (i > 0) root.addView(R.id.content, RemoteViews(context.packageName, R.layout.widget_divider))
                root.addView(R.id.content, cell(context, R.layout.widget_cell, place, use24h, now, home, live, clockSize))
            }
        }
        val open = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        root.setOnClickPendingIntent(R.id.root, open)
        return root
    }

    private fun cell(context: Context, layout: Int, place: Place, use24h: Boolean, now: Instant, home: ZoneId, live: Boolean, clockSize: Float): RemoteViews {
        val v = RemoteViews(context.packageName, layout)
        val zone = place.zone
        v.setTextViewText(R.id.name, place.name)
        // The time, with AM/PM at 0.42 of its size, as in the app.
        listOf(R.id.clock, R.id.clock_static).forEach { v.setTextViewTextSize(it, TypedValue.COMPLEX_UNIT_SP, clockSize) }
        listOf(R.id.ampm, R.id.ampm_static).forEach { v.setTextViewTextSize(it, TypedValue.COMPLEX_UNIT_SP, clockSize * 0.42f) }
        val (clock, suffix) = TimeMath.clock(now, zone, use24h)
        if (live) {
            v.setViewVisibility(R.id.clock_static, View.GONE)
            v.setViewVisibility(R.id.ampm_static, View.GONE)
            v.setString(R.id.clock, "setTimeZone", zone.id)
            v.setString(R.id.ampm, "setTimeZone", zone.id)
            val pattern = if (use24h) "HH:mm" else "h:mm"
            v.setCharSequence(R.id.clock, "setFormat12Hour", pattern)
            v.setCharSequence(R.id.clock, "setFormat24Hour", pattern)
            v.setCharSequence(R.id.ampm, "setFormat12Hour", "a")
            v.setCharSequence(R.id.ampm, "setFormat24Hour", "a")
            v.setViewVisibility(R.id.ampm, if (use24h) View.GONE else View.VISIBLE)
        } else {
            v.setViewVisibility(R.id.clock, View.GONE)
            v.setViewVisibility(R.id.ampm, View.GONE)
            v.setTextViewText(R.id.clock_static, clock)
            v.setTextViewText(R.id.ampm_static, suffix ?: "")
            v.setViewVisibility(R.id.ampm_static, if (suffix == null) View.GONE else View.VISIBLE)
        }
        // "+8 hr" or "Your time"; with the day first when it's another day there: "Tomorrow · +8 hr"
        // (small and medium) or "+1 d · +8 hr" (large).
        val shift = TimeMath.dayShift(now, zone, home)
        val relative = TimeMath.relative(now, zone, home) ?: if (zone.id == home.id) "Your time" else "Same time"
        val days = if (shift > 0) "+$shift d" else "−${-shift} d"
        if (layout == R.layout.widget_cell) {
            val day = when (shift) { 0 -> null; 1 -> "Tomorrow"; -1 -> "Yesterday"; else -> days }
            v.setTextViewText(R.id.caption, if (day == null) relative else "$day · $relative")
            v.setViewVisibility(R.id.badge, View.GONE)
        } else {
            v.setTextViewText(R.id.badge, if (shift == 0) relative else "$days · $relative")
            v.setViewVisibility(R.id.badge, View.VISIBLE)
        }
        // The hour before, now and the hour after, on the city's own clock.
        val hourStart = now.atZone(zone).withMinute(0).withSecond(0).withNano(0)
        listOf(R.id.tile0 to -1L, R.id.tile1 to 0L, R.id.tile2 to 1L).forEach { (id, k) ->
            val at = hourStart.plusHours(k)
            // Night tiles lifted just above the widget's background, so every hour reads as a tile.
            val color = DayColor.lifted(DayColor.at(at.hour + at.minute / 60.0))
            // "10 AM" with a smaller AM, as on the iPhone, so it fits its tile.
            val label = TimeMath.hourLabel(at.hour, use24h)
            val text = android.text.SpannableString(label)
            val cut = label.indexOfFirst { it == 'A' || it == 'P' }
            if (cut > 0) text.setSpan(android.text.style.RelativeSizeSpan(0.68f), cut, label.length, android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            v.setTextViewText(id, text)
            v.setTextColor(id, if (DayColor.isLight(color)) 0xFF1A1816.toInt() else 0xFFE0D8D0.toInt())
            if (Build.VERSION.SDK_INT >= 31) v.setColorStateList(id, "setBackgroundTintList", ColorStateList.valueOf(tone(color, false)))
            else v.setInt(id, "setBackgroundColor", tone(color, false))
        }
        return v
    }

    /** Refresh the hour tiles at the start of the next hour (inexact is fine; clocks tick on their own). */
    private fun scheduleNextHour(context: Context) {
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return
        val next = Instant.now().atZone(ZoneId.systemDefault()).withMinute(0).withSecond(5).withNano(0).plusHours(1)
        val intent = PendingIntent.getBroadcast(context, 1, Intent(context, WidgetClock::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        alarms.set(AlarmManager.RTC, next.toInstant().toEpochMilli(), intent)
    }
}

/** Hourly alarm, and the phone's time, time zone or date changing: redraw the widgets. */
class WidgetClock : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) = MeridianWidgets.updateAll(context)
}

open class MeridianWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = MeridianWidgets.updateAll(context)
}

class SmallWidget : MeridianWidgetProvider()
class MediumWidget : MeridianWidgetProvider()
class LargeWidget : MeridianWidgetProvider()
