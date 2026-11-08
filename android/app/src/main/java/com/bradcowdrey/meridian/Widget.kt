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
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.LinearGradient
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.graphics.Shader
import android.os.Build
import android.os.Bundle
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import java.time.Instant
import java.time.ZoneId
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.roundToInt

/**
 * Home screen widgets, as the app's city cards: small (one city: its photo fills the widget, with a big
 * time, the name and what it's doing), medium (two) and large (five) as rows, each its city's photo
 * (shaded for the time of day there, with the cards' scrims) with the time (a live TextClock in the
 * city's zone, so it never goes stale), name and status bottom-left and the hour before, now and the
 * hour after as tiles bottom-right, and one Now capsule down the centre tiles of every row. The photos
 * are small copies the app keeps for them (WidgetPhotos); the widgets never use the network. The
 * pictures and tiles refresh on the hour, and when the time, the zone, the list or the widget's size
 * changes.
 */
object MeridianWidgets {
    enum class Size(val cities: Int) { SMALL(1), MEDIUM(2), LARGE(5) }

    private val providers = mapOf(
        Size.SMALL to SmallWidget::class.java,
        Size.MEDIUM to MediumWidget::class.java,
        Size.LARGE to LargeWidget::class.java,
    )

    // Geometry (dp), as the layouts: widget_photo_root's inset, widget_row_gap, and widget_photo_row's
    // insets, gap between the name column and the tiles, tile height and tile margins.
    private const val PAD = 6f
    private const val ROW_GAP = 5f
    private const val ROW_PAD_H = 10f
    private const val ROW_PAD_BOTTOM = 6f
    private const val LABEL_GAP = 6f
    private const val TILE_HEIGHT = 24f
    private const val TILE_MARGIN = 2f
    /** The tiles' share of a row's width beside the name column's 1 (layout weights). */
    private const val TILES_WEIGHT = 1.1f
    private const val ROW_RADIUS = 12f
    private const val SMALL_RADIUS = 22f

    /** One worker, so photos are decoded and pictures drawn off the main thread, one update at a time. */
    private val worker = Executors.newSingleThreadExecutor()

    /** A redraw is waiting to start (it will read the latest list and settings, so another isn't queued). */
    private val queued = AtomicBoolean(false)

    /** Makes the widgets' photo copies and redraws every widget, in the background; [done] runs after. */
    fun updateAll(context: Context, done: (() -> Unit)? = null) {
        val app = context.applicationContext
        if (queued.compareAndSet(false, true)) {
            worker.execute {
                queued.set(false)
                try {
                    render(app)
                } catch (e: Throwable) {
                    // A widget keeps its last picture.
                }
            }
        }
        // After the redraw that's queued (one worker, in order).
        if (done != null) worker.execute { done() }
        scheduleNextHour(app)
    }

    private fun render(context: Context) {
        DataFiles.init(context)
        val prefs = Store.prefs(context)
        val counted = prefs.getBoolean("countHolidays", true)
        if (Holidays.counted != counted) Holidays.counted = counted
        Holidays.load()
        val manager = AppWidgetManager.getInstance(context)
        val places = Store.loadPlaces(context) ?: emptyList()
        val use24h = Store.use24h(context)
        // The small copies for every city on the list (only missing ones are made), then which city uses which.
        val photos = runCatching { WidgetPhotos.export(context, places) }.getOrElse { WidgetPhotos.saved(context) }
        val now = Instant.now()
        val home = ZoneId.systemDefault()
        providers.forEach { (size, cls) ->
            manager.getAppWidgetIds(ComponentName(context, cls)).forEach { id ->
                val (w, h) = sizeOf(context, manager, id) ?: defaultSize(size)
                manager.updateAppWidget(id, views(context, size, places, use24h, now, home, live = true, widthDp = w, heightDp = h, photos = photos))
            }
        }
    }

    /** The widget's size in dp, as the launcher reports it (portrait: min width by max height). */
    private fun sizeOf(context: Context, manager: AppWidgetManager, id: Int): Pair<Int, Int>? {
        val o = manager.getAppWidgetOptions(id) ?: return null
        val landscape = context.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        val w = o.getInt(if (landscape) AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH else AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
        val h = o.getInt(if (landscape) AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT else AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT)
        return if (w > 0 && h > 0) w to h else null
    }

    /** Until the launcher says: the sizes of the app's widget previews. */
    private fun defaultSize(size: Size): Pair<Int, Int> = when (size) {
        Size.SMALL -> 152 to 152
        Size.MEDIUM -> 320 to 152
        Size.LARGE -> 320 to 320
    }

    /** Settings' working hours, for the status and the dimmed tiles. */
    private class Work(val show: Boolean, val start: Int, val end: Int)

    /**
     * The widget's views. [live] uses ticking clocks; previews (the app's widget screen) use fixed text.
     * [widthDp] and [heightDp] are the widget's size (0: the preview's); [photos] each card's photo by
     * card id (null: looked up now, without writing anything).
     */
    fun views(
        context: Context, size: Size, places: List<Place>, use24h: Boolean, now: Instant, home: ZoneId, live: Boolean = false,
        widthDp: Int = 0, heightDp: Int = 0, photos: Map<String, WidgetPhotos.Ref>? = null,
    ): RemoteViews {
        DataFiles.init(context)
        val (w, h) = if (widthDp > 0 && heightDp > 0) widthDp to heightDp else defaultSize(size)
        val prefs = Store.prefs(context)
        val work = Work(prefs.getBoolean("showWorkHours", true), prefs.getInt("workStart", 9), prefs.getInt("workEnd", 18))
        val cities = places.take(size.cities)
        val refs = photos ?: WidgetPhotos.refs(context, cities)
        val density = context.resources.displayMetrics.density
        val root = RemoteViews(context.packageName, R.layout.widget_photo_root)
        root.removeAllViews(R.id.content)
        root.setViewVisibility(R.id.now_overlay, View.GONE)
        val pad = (PAD * density).roundToInt()
        if (cities.isEmpty()) {
            root.setViewPadding(R.id.content, pad, pad, pad, pad)
            root.addView(R.id.content, RemoteViews(context.packageName, R.layout.widget_empty))
        } else if (size == Size.SMALL) {
            // One city: its photo fills the widget, edge to edge.
            root.setViewPadding(R.id.content, 0, 0, 0, 0)
            val place = cities.first()
            root.addView(R.id.content, cell(context, R.layout.widget_photo_small, place, refs[place.id], use24h, now, live,
                w.toFloat(), h.toFloat(), SMALL_RADIUS, maxPx = 400, region = RectF(0f, 0.4f, 0.7f, 0.72f),
                timeSp = 34f, nameSp = 13f, showStatus = true, tiles = false, work = work))
        } else {
            root.setViewPadding(R.id.content, pad, pad, pad, pad)
            val n = cities.size
            val innerW = w - 2 * PAD
            val innerH = h - 2 * PAD
            val rowH = ((innerH - (n - 1) * ROW_GAP) / n).coerceAtLeast(1f)
            // Shorter rows: a smaller time, and the status gives way.
            val showStatus = rowH >= 64f
            val timeSp = when { rowH >= 56f -> 20f; rowH >= 46f -> 18f; else -> 15f }
            val nameSp = if (rowH >= 44f) 12f else 11f
            cities.forEachIndexed { i, place ->
                if (i > 0) root.addView(R.id.content, RemoteViews(context.packageName, R.layout.widget_row_gap))
                root.addView(R.id.content, cell(context, R.layout.widget_photo_row, place, refs[place.id], use24h, now, live,
                    innerW, rowH, ROW_RADIUS, maxPx = 480, region = RectF(0f, 0.25f, 0.4f, 0.7f),
                    timeSp = timeSp, nameSp = nameSp, showStatus = showStatus, tiles = true, work = work))
            }
            // One Now capsule down the centre tiles of every row, over the tile column.
            val blockW = (innerW - 2 * ROW_PAD_H - LABEL_GAP) * TILES_WEIGHT / (1f + TILES_WEIGHT)
            capsule(density, blockW, innerH, n, rowH)?.let {
                root.setImageViewBitmap(R.id.now_capsule, it)
                root.setViewVisibility(R.id.now_overlay, View.VISIBLE)
            }
        }
        val open = PendingIntent.getActivity(context, 0, Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        root.setOnClickPendingIntent(R.id.root, open)
        return root
    }

    /** The views of a time: white (dark photo) or dark (bright photo), each with its live and fixed clock. */
    private class TimeIds(val box: Int, val clock: Int, val clockStatic: Int, val ampm: Int, val ampmStatic: Int)
    private val lightInk = TimeIds(R.id.time_light, R.id.clock, R.id.clock_static, R.id.ampm, R.id.ampm_static)
    private val darkInk = TimeIds(R.id.time_dark, R.id.clock_d, R.id.clock_static_d, R.id.ampm_d, R.id.ampm_static_d)

    /** What a city is doing now, for the pill under its name: the cards' colours and icons. */
    private enum class Status(val color: Int, val icon: Int) {
        WORKING(0xFF9AD3A8.toInt(), R.drawable.ic_briefcase),
        OFF_HOURS(0xFFB9C3CF.toInt(), R.drawable.ic_moon),
        WEEKEND(0xFFF2C66D.toInt(), R.drawable.ic_sun),
        DAY_OFF(0xFFF2C66D.toInt(), R.drawable.ic_sun),
        HOLIDAY(0xFFF39A72.toInt(), R.drawable.ic_star),
    }

    /** "Working", "Off hours", "Weekend", "Day off" or the holiday's name, as the cards work it out. */
    private fun status(place: Place, at: Instant, work: Work): Pair<Status, String> {
        val off = WorkWeek.offLabel(place, at, work.start, work.end)
        val holiday = Holidays.name(place, at)
        val kind = when {
            off == null -> Status.WORKING
            holiday != null && off == holiday -> Status.HOLIDAY
            off == "Weekend" -> Status.WEEKEND
            off == "Day off" -> Status.DAY_OFF
            else -> Status.OFF_HOURS
        }
        return kind to (off ?: "Working")
    }

    private fun cell(
        context: Context, layout: Int, place: Place, ref: WidgetPhotos.Ref?, use24h: Boolean, now: Instant, live: Boolean,
        wDp: Float, hDp: Float, cornerDp: Float, maxPx: Int, region: RectF,
        timeSp: Float, nameSp: Float, showStatus: Boolean, tiles: Boolean, work: Work,
    ): RemoteViews {
        val v = RemoteViews(context.packageName, layout)
        val phase = WidgetSky.phase(place, now)
        val art = WidgetSky.background(context, ref, WidgetPhotos.city(context, place), phase, wDp, hDp, cornerDp, maxPx, region)
        v.setImageViewBitmap(R.id.bg, art.bitmap)
        // Adaptive ink: dark numbers with a white outline on a bright photo, white ones with a dark one otherwise.
        val ink = if (art.bright) darkInk else lightInk
        v.setViewVisibility(lightInk.box, if (art.bright) View.GONE else View.VISIBLE)
        v.setViewVisibility(darkInk.box, if (art.bright) View.VISIBLE else View.GONE)
        clock(v, ink, place.zone, use24h, now, live, timeSp)
        v.setTextViewText(R.id.name, place.title)
        v.setTextViewTextSize(R.id.name, TypedValue.COMPLEX_UNIT_SP, nameSp)
        if (showStatus && work.show) {
            val (kind, text) = status(place, TimeMath.quarter(now), work)
            v.setTextViewText(R.id.status_text, text)
            v.setTextColor(R.id.status_text, kind.color)
            v.setImageViewResource(R.id.status_icon, kind.icon)
            v.setInt(R.id.status_icon, "setColorFilter", kind.color)
            v.setViewVisibility(R.id.status, View.VISIBLE)
        } else {
            v.setViewVisibility(R.id.status, View.GONE)
        }
        if (tiles) tiles(v, place, use24h, now, work)
        return v
    }

    /** The time, with AM/PM at 0.45 of its size, as on the cards. */
    private fun clock(v: RemoteViews, ids: TimeIds, zone: ZoneId, use24h: Boolean, now: Instant, live: Boolean, size: Float) {
        listOf(ids.clock, ids.clockStatic).forEach { v.setTextViewTextSize(it, TypedValue.COMPLEX_UNIT_SP, size) }
        listOf(ids.ampm, ids.ampmStatic).forEach { v.setTextViewTextSize(it, TypedValue.COMPLEX_UNIT_SP, size * 0.45f) }
        if (live) {
            v.setViewVisibility(ids.clockStatic, View.GONE)
            v.setViewVisibility(ids.ampmStatic, View.GONE)
            v.setViewVisibility(ids.clock, View.VISIBLE)
            v.setString(ids.clock, "setTimeZone", zone.id)
            v.setString(ids.ampm, "setTimeZone", zone.id)
            val pattern = if (use24h) "HH:mm" else "h:mm"
            v.setCharSequence(ids.clock, "setFormat12Hour", pattern)
            v.setCharSequence(ids.clock, "setFormat24Hour", pattern)
            v.setCharSequence(ids.ampm, "setFormat12Hour", "a")
            v.setCharSequence(ids.ampm, "setFormat24Hour", "a")
            v.setViewVisibility(ids.ampm, if (use24h) View.GONE else View.VISIBLE)
        } else {
            val (digits, suffix) = TimeMath.clock(now, zone, use24h)
            v.setViewVisibility(ids.clock, View.GONE)
            v.setViewVisibility(ids.ampm, View.GONE)
            v.setViewVisibility(ids.clockStatic, View.VISIBLE)
            v.setTextViewText(ids.clockStatic, digits)
            v.setTextViewText(ids.ampmStatic, suffix ?: "")
            v.setViewVisibility(ids.ampmStatic, if (suffix == null) View.GONE else View.VISIBLE)
        }
    }

    /** The hour before, now and the hour after, on the city's own clock: the day's colour there, quieter outside working hours. */
    private fun tiles(v: RemoteViews, place: Place, use24h: Boolean, now: Instant, work: Work) {
        val zone = place.zone
        val hourStart = now.atZone(zone).withMinute(0).withSecond(0).withNano(0)
        listOf(R.id.tile0 to -1L, R.id.tile1 to 0L, R.id.tile2 to 1L).forEach { (id, k) ->
            val at = hourStart.plusHours(k)
            val color = DayColor.at(at.hour + at.minute / 60.0)
            // "10 AM" with a smaller AM, as on the iPhone, so it fits its tile.
            val label = TimeMath.hourLabel(at.hour, use24h)
            val text = android.text.SpannableString(label)
            val cut = label.indexOfFirst { it == 'A' || it == 'P' }
            if (cut > 0) text.setSpan(android.text.style.RelativeSizeSpan(0.68f), cut, label.length, android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            v.setTextViewText(id, text)
            v.setTextColor(id, 0xFFFFFFFF.toInt())
            val dim = work.show && !WorkWeek.isWorking(place, at.toInstant().plusSeconds(1800), work.start, work.end)
            val fill = if (dim) (color and 0x00FFFFFF) or (0xB8 shl 24) else color
            if (Build.VERSION.SDK_INT >= 31) v.setColorStateList(id, "setBackgroundTintList", ColorStateList.valueOf(fill))
            else v.setInt(id, "setBackgroundColor", fill)
        }
    }

    /**
     * The Now capsule, as on the cards: through the centre tile of every row, from a little above the
     * first row's tile to a little below the last's, a little wider than the tile; white 62% outline, a
     * faint glass fill and a soft glow. Drawn for the tile column ([blockWDp] by [heightDp]), which the
     * layout stretches to fit, so it stays on the tiles if the launcher's size is a little off.
     */
    private fun capsule(density: Float, blockWDp: Float, heightDp: Float, n: Int, rowHDp: Float): Bitmap? {
        if (blockWDp <= 0f || heightDp <= 0f || n <= 0) return null
        val s = minOf(density, 2f)
        val bw = (blockWDp * s).roundToInt()
        val bh = (heightDp * s).roundToInt()
        if (bw < 4 || bh < 4) return null
        val slot = blockWDp / 3f
        val side = 4f
        val overhang = 6f
        val left = (slot + TILE_MARGIN - side) * s
        val right = (2 * slot - TILE_MARGIN + side) * s
        val top = maxOf(rowHDp - ROW_PAD_BOTTOM - TILE_HEIGHT - overhang, 1f) * s
        val bottom = minOf((n - 1) * (rowHDp + ROW_GAP) + rowHDp - ROW_PAD_BOTTOM + overhang, heightDp - 1f) * s
        if (bottom <= top || right <= left) return null
        val bitmap = Bitmap.createBitmap(bw, bh, Bitmap.Config.ARGB_8888)
        val c = Canvas(bitmap)
        val rect = RectF(left, top, right, bottom)
        val radius = rect.width() / 2f
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        fun white(alpha: Float) = ((alpha * 255).roundToInt().coerceIn(0, 255) shl 24) or 0xFFFFFF
        // The glow: wider, fainter strokes behind.
        paint.style = Paint.Style.STROKE
        for ((spread, alpha) in listOf(10f to 0.035f, 7f to 0.05f, 4f to 0.07f)) {
            paint.strokeWidth = spread * s
            paint.color = white(alpha)
            c.drawRoundRect(rect, radius, radius, paint)
        }
        // The glass.
        paint.style = Paint.Style.FILL
        paint.shader = LinearGradient(0f, top, 0f, bottom, white(0.07f), white(0.025f), Shader.TileMode.CLAMP)
        c.drawRoundRect(rect, radius, radius, paint)
        paint.shader = null
        // The outline, 2 dp.
        val stroke = 2f * s
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = stroke
        paint.color = white(0.62f)
        val inner = RectF(left + stroke / 2, top + stroke / 2, right - stroke / 2, bottom - stroke / 2)
        c.drawRoundRect(inner, radius - stroke / 2, radius - stroke / 2, paint)
        return bitmap
    }

    /** Refresh the pictures and tiles at the start of the next hour (inexact is fine; clocks tick on their own). */
    private fun scheduleNextHour(context: Context) {
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return
        val next = Instant.now().atZone(ZoneId.systemDefault()).withMinute(0).withSecond(5).withNano(0).plusHours(1)
        val intent = PendingIntent.getBroadcast(context, 1, Intent(context, WidgetClock::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        alarms.set(AlarmManager.RTC, next.toInstant().toEpochMilli(), intent)
    }
}

/**
 * A widget's photo, drawn as the cards draw theirs: cropped to fill (a little above centre), shaded for
 * the time of day there (night darker and cooler, dawn and dusk warmer, day as taken), under the cards'
 * scrims (darkest at the bottom and the left), with rounded corners; or, with no photo, a sky for the
 * time of day with a skyline drawn for the city.
 */
private object WidgetSky {
    enum class Phase { DAY, TWILIGHT, NIGHT }

    /** The picture, and whether it's bright behind the time (for dark numbers). */
    class Art(val bitmap: Bitmap, val bright: Boolean)

    /** Day, twilight (within an hour of sunrise or sunset) or night, as the cards. */
    fun phase(place: Place, at: Instant): Phase {
        fun isDay(t: Instant): Boolean? = when (Sun.phase(place, t)) {
            is Sun.Phase.Day, Sun.Phase.AllDay -> true
            is Sun.Phase.Night, Sun.Phase.AllNight -> false
            null -> null
        }
        val now = isDay(at) ?: return if (at.atZone(place.zone).hour in 7..18) Phase.DAY else Phase.NIGHT
        if (isDay(at.minusSeconds(3600)) != now || isDay(at.plusSeconds(3600)) != now) return Phase.TWILIGHT
        return if (now) Phase.DAY else Phase.NIGHT
    }

    /** The cards' shading: night about 45% darker and a little cooler; dawn and dusk a little warmer; day as taken. */
    private fun gain(phase: Phase): FloatArray? = when (phase) {
        Phase.NIGHT -> floatArrayOf(0.400f, 0.459f, 0.522f)
        Phase.TWILIGHT -> floatArrayOf(0.941f, 0.820f, 0.714f)
        Phase.DAY -> null
    }

    /** The drawn sky's top and bottom, and its buildings. */
    private fun drawnColors(phase: Phase): Triple<Int, Int, Int> = when (phase) {
        Phase.DAY -> Triple(0xFF3D74B0.toInt(), 0xFF1C3A5E.toInt(), 0xFF0A0E1C.toInt())
        Phase.TWILIGHT -> Triple(0xFF4F78A3.toInt(), 0xFF24384F.toInt(), 0xFF0A0E1C.toInt())
        Phase.NIGHT -> Triple(0xFF141E3C.toInt(), 0xFF0A0E1C.toInt(), 0xFF000000.toInt())
    }

    /**
     * The picture for a card [wDp] by [hDp], at most [maxPx] wide (the layout stretches it to fit), so all
     * a widget's pictures stay small. [region] is where the time is, as fractions of the card.
     */
    fun background(
        context: Context, ref: WidgetPhotos.Ref?, city: String, phase: Phase,
        wDp: Float, hDp: Float, cornerDp: Float, maxPx: Int, region: RectF,
    ): Art {
        val density = context.resources.displayMetrics.density
        val scale = minOf(density, maxPx / wDp.coerceAtLeast(1f)).coerceAtLeast(0.25f)
        val bw = (wDp * scale).roundToInt().coerceAtLeast(2)
        val bh = (hDp * scale).roundToInt().coerceAtLeast(2)
        val out = Bitmap.createBitmap(bw, bh, Bitmap.Config.ARGB_8888)
        val c = Canvas(out)
        val w = bw.toFloat()
        val h = bh.toFloat()
        val photo = ref?.let { WidgetPhotos.load(context, it, minOf(bw, 600)) }
        if (photo != null && ref != null) {
            // Crop to fill, then a little above centre, as the cards.
            val iw = photo.width.toFloat()
            val ih = photo.height.toFloat()
            val s = maxOf(w / iw, h / ih)
            val dw = iw * s
            val dh = ih * s
            val offX = (w - dw) / 2f
            val offY = (h - dh) / 2f * (1f + ref.biasY)
            val paint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)
            gain(phase)?.let { g ->
                paint.colorFilter = ColorMatrixColorFilter(ColorMatrix(floatArrayOf(
                    g[0], 0f, 0f, 0f, 0f,
                    0f, g[1], 0f, 0f, 0f,
                    0f, 0f, g[2], 0f, 0f,
                    0f, 0f, 0f, 1f, 0f,
                )))
            }
            c.drawBitmap(photo, null, RectF(offX, offY, offX + dw, offY + dh), paint)
            photo.recycle()
        } else {
            drawn(c, w, h, phase, city, scale)
        }
        // The cards' scrim: black 55% at the bottom fading to nothing by 55% of the height, and black 35%
        // at the left fading to nothing by 60% of the width.
        val scrim = Paint()
        scrim.shader = LinearGradient(0f, 0f, 0f, h, intArrayOf(0, 0, 0x33000000, 0x8C000000.toInt()),
            floatArrayOf(0f, 0.45f, 0.7f, 1f), Shader.TileMode.CLAMP)
        c.drawRect(0f, 0f, w, h, scrim)
        scrim.shader = LinearGradient(0f, 0f, w * 0.6f, 0f, 0x59000000, 0, Shader.TileMode.CLAMP)
        c.drawRect(0f, 0f, w, h, scrim)
        val bright = luminance(out, region) > 0.40f
        // Rounded corners: clear outside them (anti-aliased).
        if (cornerDp > 0f) {
            val r = cornerDp * scale
            val corners = Path().apply {
                fillType = Path.FillType.EVEN_ODD
                addRect(0f, 0f, w, h, Path.Direction.CW)
                addRoundRect(RectF(0f, 0f, w, h), r, r, Path.Direction.CW)
            }
            c.drawPath(corners, Paint(Paint.ANTI_ALIAS_FLAG).apply { xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_OUT) })
        }
        return Art(out, bright)
    }

    /** No photo: the sky for the time of day, the sun or moon, and a skyline drawn for the city (the same city, the same buildings), as the cards. */
    private fun drawn(c: Canvas, w: Float, h: Float, phase: Phase, city: String, u: Float) {
        val (top, bottom, ink) = drawnColors(phase)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.shader = LinearGradient(0f, 0f, 0f, h, top, bottom, Shader.TileMode.CLAMP)
        c.drawRect(0f, 0f, w, h, paint)
        paint.shader = null
        when (phase) {
            Phase.NIGHT -> { paint.color = 0xE6EFE3CC.toInt(); c.drawCircle(w * 0.86f, h * 0.28f, 9 * u, paint) }
            Phase.TWILIGHT -> { paint.color = 0xD9F39A72.toInt(); c.drawCircle(w * 0.88f, h * 0.82f, 22 * u, paint) }
            Phase.DAY -> { paint.color = 0xF2FFFFFF.toInt(); c.drawCircle(w * 0.86f, h * 0.25f, 12 * u, paint) }
        }
        val seed = city.lowercase().hashCode().toLong()
        // The far buildings, fainter.
        val back = java.util.Random(seed xor 0x5DEECE66DL)
        paint.color = (ink and 0x00FFFFFF) or (0x8C shl 24)
        repeat(30) {
            val x = back.nextFloat() * w
            val bw = (10 + back.nextFloat() * 22) * u
            val bh = h * (0.25f + back.nextFloat() * 0.35f)
            c.drawRect(x, h - bh, x + bw, h, paint)
        }
        // The near buildings, with windows lit at dusk and at night.
        val r = java.util.Random(seed)
        val lit = when (phase) { Phase.NIGHT -> 0.35f; Phase.TWILIGHT -> 0.18f; Phase.DAY -> 0f }
        val window = Paint()
        var x = 0f
        while (x < w) {
            val bw = (8 + r.nextFloat() * 18) * u
            val bh = h * (0.18f + r.nextFloat() * 0.42f)
            paint.color = ink
            c.drawRect(x, h - bh, x + bw, h, paint)
            if (lit > 0f) {
                var y = h - bh + 4 * u
                while (y < h - 3 * u) {
                    var wx = x + 2 * u
                    while (wx < x + bw - 2 * u) {
                        if (r.nextFloat() < lit) {
                            window.color = (((0.6f + r.nextFloat() * 0.4f) * 255).toInt() shl 24) or 0xF2C66D
                            c.drawRect(wx, y, wx + 1.6f * u, y + 2 * u, window)
                        }
                        wx += 4 * u
                    }
                    y += 5 * u
                }
            }
            x += (6 + r.nextFloat() * 14) * u
        }
    }

    private fun linear(c: Float): Double =
        if (c <= 0.04045f) c / 12.92 else Math.pow((c + 0.055) / 1.055, 2.4)

    /** The mean relative luminance of the picture in [region] (fractions), sampled on a 16 by 8 grid. */
    private fun luminance(b: Bitmap, region: RectF): Float {
        var sum = 0.0
        val cols = 16
        val rows = 8
        for (j in 0 until rows) for (i in 0 until cols) {
            val x = ((region.left + region.width() * (i + 0.5f) / cols) * b.width).toInt().coerceIn(0, b.width - 1)
            val y = ((region.top + region.height() * (j + 0.5f) / rows) * b.height).toInt().coerceIn(0, b.height - 1)
            val p = b.getPixel(x, y)
            sum += 0.2126 * linear(((p shr 16) and 0xFF) / 255f) + 0.7152 * linear(((p shr 8) and 0xFF) / 255f) +
                0.0722 * linear((p and 0xFF) / 255f)
        }
        return (sum / (cols * rows)).toFloat()
    }
}

/** Hourly alarm, and the phone's time, time zone or date changing: redraw the widgets. */
class WidgetClock : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        MeridianWidgets.updateAll(context) { pending.finish() }
    }
}

open class MeridianWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        val pending = goAsync()
        MeridianWidgets.updateAll(context) { pending.finish() }
    }

    /** Resized: the pictures and the capsule are drawn for the widget's size. */
    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, newOptions: Bundle?) {
        val pending = goAsync()
        MeridianWidgets.updateAll(context) { pending.finish() }
    }
}

class SmallWidget : MeridianWidgetProvider()
class MediumWidget : MeridianWidgetProvider()
class LargeWidget : MeridianWidgetProvider()
