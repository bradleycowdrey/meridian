package com.bradcowdrey.meridian

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
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
import android.graphics.Typeface
import android.os.Build
import android.os.Bundle
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import org.json.JSONArray
import org.json.JSONObject
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
 * hour after as tiles bottom-right (the day photo by day, the night photo by night where the city has one), and one Now capsule down the centre tiles of every row. The photos
 * are small copies the app keeps for them (WidgetPhotos); the widgets never use the network. The
 * pictures, status and tiles refresh every quarter hour (every city's working hours start and end on a
 * quarter), and when the time, the zone, the list or the widget's size changes. Each widget shows the
 * app's cities, or its own (Edit Widget: WidgetConfigActivity), as the iPhone's.
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
    private const val ROW_GAP = 6f
    private const val ROW_PAD_H = 10f
    private const val ROW_PAD_TOP = 0f
    private const val ROW_PAD_BOTTOM = 6f
    private const val LABEL_GAP = 6f
    private const val TILE_HEIGHT = 24f
    /** widget_photo_row's tiles_tall (the hour over AM/PM), used in rows at least TALL_TILE_ROW tall. */
    private const val TILE_TALL_HEIGHT = 38f
    private const val TALL_TILE_ROW = 56f
    /** Extra space under the name column (dp, padding on text_col) beyond ROW_PAD_BOTTOM: none, so the pill and the tiles share one bottom edge on every widget size. */
    private const val TEXT_CLEARANCE = 0f
    private const val TILE_MARGIN = 2f
    /** The tile drawable's corner radius (drawable/tile). */
    private const val TILE_CORNER = 6f
    /**
     * The Now (centre) tile: NOW_WIDTH times as wide as the hour before and after (widget_photo_row's tile1 weights
     * 1.12 beside 1 and 1), and NOW_GROW dp taller above and below their common centre (tile1_slot is 8 dp taller than
     * its neighbours; the code pads it back where a row is too short). Its hour digits NOW_DIGITS_UP sp and its
     * AM/PM and ":30" NOW_SMALL_UP sp larger than the row's other tiles, where they fit.
     */
    private const val NOW_WIDTH = 1.12f
    private const val NOW_GROW = 4f
    private const val NOW_DIGITS_UP = 2
    private const val NOW_SMALL_UP = 1f
    /**
     * Extra clear space (dp) each side of the Now tile, beyond the usual 4 dp gap (2 * TILE_MARGIN): widget_photo_row's
     * tile1 slots have 5 dp side margins (TILE_MARGIN + NOW_EXTRA), so the gap either side of the Now tile is 7 dp.
     */
    private const val NOW_EXTRA = 3f
    /** Half the 7 dp gap beside the Now tile: the Now outline's centre line runs this far outside the Now tiles. */
    private const val NOW_INSET = TILE_MARGIN + NOW_EXTRA / 2
    /**
     * The row height (dp) the widget's text and tiles are designed for (two rows on the 152 dp medium widget). Taller
     * rows (fewer cities than the widget holds, or a widget resized taller) scale their contents with the row, up to
     * TIME_GROW_MAX (the time), TEXT_GROW_MAX (name and status) and TILE_GROW_MAX (the tall tiles' height, Android 12+).
     */
    private const val REF_ROW_H = 67f
    private const val TIME_GROW_MAX = 1.5f
    private const val TEXT_GROW_MAX = 1.25f
    private const val TILE_GROW_MAX = 1.4f
    /**
     * The clear gap between a row's text block and its tiles (dp): what the text column leaves (40 dp or more on the
     * default widgets), never under MIN_CLEAR (a long name ellipsizes rather than close it).
     */
    private const val MIN_CLEAR = 16f
    private const val GROW_CLEAR = 40f
    /**
     * The dark halo under the Now outline's white line (black 60%, CAPSULE_HALO_ALPHA), so the line holds 3:1 on a bright day sky too.
     * The outline's centre line runs midway in the 7 dp gap (2 * TILE_MARGIN + NOW_EXTRA) between the Now tile and its neighbours,
     * 3.5 dp from each; 3 dp wide, it stays 2 dp clear of both tiles.
     */
    private const val CAPSULE_HALO = 3f
    /** Black 60% (was 40%), as the app's capsule edge: about 0.07 L on a 0.45 day sky, 3.9:1 (was 0.14 L at best, and a single 0.21 L pixel at 1x). */
    private const val CAPSULE_HALO_ALPHA = 0.6f
    private const val CAPSULE_ALPHA = 0.85f
    /** The white line's drawn width (dp): 1.5 inside the 3 dp halo, so a 0.75 dp dark band shows on each side. */
    private const val CAPSULE_LINE = 1.5f
    /** Roboto's line height (ascent + descent, includeFontPadding off), in ems: for fitting a row's text. */
    private const val LINE_EM = 1.172f
    /** widget_photo_row's status pill: text size (sp), icon, gap above the full pill (none above the compact one), and its normal top and bottom padding (dp). */
    private const val STATUS_SP = 13f
    /** The compact pill's text (sp), one step down, so five rows on the large widget keep their status words. */
    private const val STATUS_COMPACT_SP = 12f
    private const val STATUS_ICON = 12f
    /** 2 dp (was 1): about 4.4 dp clear between the name's glyphs and the pill, so time, name and status read as three steps; fits the 67 dp rows of the 2-row widget with the full pill at font scale 1 with about 0.74 dp to spare for rounding. */
    private const val PILL_GAP = 2f
    private const val PILL_PAD_V = 1f
    /** The tiles' share of a row's width beside the name column's 1 (layout weights). */
    private const val TILES_WEIGHT = 1.1f
    private const val ROW_RADIUS = 12f
    private const val SMALL_RADIUS = 22f
    /** The smallest AM/PM (sp), by the time and on the tiles: a fixed span on the tiles (in sp, so it follows the font scale), so auto-size never shrinks it. */
    private const val AMPM_MIN_SP = 12f
    /** A half-hour city's ":30" on the tiles (sp, a fixed span that follows the font scale): 12 sp (was 11), level with AM/PM, as the app's inline ":30". */
    private const val MINUTES_SP = 12f
    /** Gap (dp) above the compact pill (five rows on the large widget; was 0), so the name never sits on the pill's outline. */
    private const val COMPACT_GAP = 1f
    /** Off-hours and night tiles (fill at most this luminance) get a 1 dp white 32% edge (widget_tile_edge), so they read as tiles on a night photo. */
    private const val EDGE_MAX_LUMINANCE = 0.05
    /**
     * The new day's weekday tag ("WED", widget_photo_row's day_tag0..2) over the tile where a new day starts there
     * (midnight): 11 dp text whatever the font scale (it must stay narrower than a tile) in a pill TAG_H dp high
     * (TAG_COMPACT_H where the row is short), TAG_PAD_H dp each side of the text, its bottom TAG_GAP dp above the
     * tile's top; above the first row's Now tile, TAG_LINE_CLEAR dp above the Now outline's top line instead. Never
     * nearer than TAG_TOP_CLEAR dp to the row's top; inside the first row's Now tile it starts TAG_INSET dp under the tile's top.
     */
    private const val TAG_DP = 11f
    private const val TAG_H = 15f
    private const val TAG_COMPACT_H = 13f
    private const val TAG_PAD_H = 5f
    private const val TAG_GAP = 3f
    private const val TAG_LINE_CLEAR = 2f
    private const val TAG_TOP_CLEAR = 0.5f
    private const val TAG_INSET = 1f
    /** A weekday tag's place: its [bottom] above the row's bottom and its [height] (dp); [inside]: within the Now tile's top, under the Now outline. */
    private class DayTag(val bottom: Float, val height: Float, val inside: Boolean)
    /** The least clear space (dp) above the time's line in a row with the compact pill (five rows on the large widget): with the cap's own 3.7 dp, about 6 dp from the row's top edge to the time. */
    private const val COMPACT_TOP_CLEAR = 2f
    /**
     * Tile fills no lighter than this relative luminance (that of #3F6A97, as the app's tiles, DayColor.tile),
     * so white numbers and AM/PM on them are at least 5.6:1 (1.05 / 0.186).
     */
    private const val TILE_MAX_LUMINANCE = 0.136
    /**
     * Working (not dimmed) tile fills no darker than this relative luminance, as the app's (DayColor.WORKING_FLOOR):
     * 3.05:1 from an off-hours tile (0.006) at the shoulder hours too (9 AM was 2.9:1), white on it 6.3:1.
     */
    private const val TILE_WORKING_FLOOR = 0.12
    // Outside working hours a tile is dimmed exactly as the app's tiles, via TileDim.opaque (MainActivity.kt): same hue,
    // opaque so no photo shows through, 30% of its luminance, no lighter than 0.006 and no darker than the #0A0E1C night
    // tile (0.0048). A working day tile (0.136) against the brightest off one (0.006) is 3.3:1 (WCAG 1.4.11).

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
        scheduleNextQuarter(app)
    }

    /** A widget's own city (WidgetConfigActivity): its name and zone, with its country and place when known. */
    class Chosen(val name: String, val zoneId: String, val countryCode: String? = null, val latitude: Double? = null, val longitude: Double? = null)

    /** Whether widget [id] shows the app's cities (true unless set otherwise), and its own chosen cities. */
    fun followKey(id: Int) = "widget.$id.follow"
    fun citiesKey(id: Int) = "widget.$id.cities"

    fun loadChosen(prefs: SharedPreferences, id: Int): List<Chosen> = runCatching {
        val array = JSONArray(prefs.getString(citiesKey(id), null) ?: return@runCatching emptyList<Chosen>())
        (0 until array.length()).map { i ->
            val o = array.getJSONObject(i)
            Chosen(o.getString("name"), o.getString("timeZoneID"),
                countryCode = if (o.has("countryCode")) o.getString("countryCode") else null,
                latitude = if (o.has("latitude")) o.getDouble("latitude") else null,
                longitude = if (o.has("longitude")) o.getDouble("longitude") else null)
        }
    }.getOrDefault(emptyList())

    fun saveChosen(prefs: SharedPreferences, id: Int, follow: Boolean, chosen: List<Chosen>) {
        val array = JSONArray()
        chosen.forEach { c ->
            val o = JSONObject().put("name", c.name).put("timeZoneID", c.zoneId)
            c.countryCode?.let { o.put("countryCode", it) }
            c.latitude?.let { o.put("latitude", it) }
            c.longitude?.let { o.put("longitude", it) }
            array.put(o)
        }
        prefs.edit().putBoolean(followKey(id), follow).putString(citiesKey(id), array.toString()).apply()
    }

    /**
     * Widget [id]'s cities, as the iPhone's ClockConfiguration: the app's list while it follows the app (the default) or
     * has no cities of its own; else its chosen cities in their order, each the app's card for it where the city is on
     * the list (keeping its country, location and working week), else the city alone.
     */
    fun citiesFor(prefs: SharedPreferences, id: Int, places: List<Place>): List<Place> {
        if (prefs.getBoolean(followKey(id), true)) return places
        val chosen = loadChosen(prefs, id)
        if (chosen.isEmpty()) return places
        return chosen.map { c ->
            places.firstOrNull { it.name == c.name && it.zoneId == c.zoneId }
                ?: Place(name = c.name, zoneId = c.zoneId, id = "widget|${c.name}|${c.zoneId}",
                    countryCode = c.countryCode, latitude = c.latitude, longitude = c.longitude)
        }
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
        // Each widget's cities: the app's, or its own (Edit Widget).
        val lists = providers.values.flatMap { cls -> manager.getAppWidgetIds(ComponentName(context, cls)).toList() }
            .associateWith { id -> citiesFor(prefs, id, places) }
        // The small copies for every city on the list and every widget's own (only missing ones are made), then
        // which city uses which. A city with no photo has the drawn sky.
        val shown = (places + lists.values.flatten()).distinctBy { it.id }
        val photos = runCatching { WidgetPhotos.export(context, shown) }.getOrElse { WidgetPhotos.saved(context) }
        val now = Instant.now()
        val home = ZoneId.systemDefault()
        providers.forEach { (size, cls) ->
            manager.getAppWidgetIds(ComponentName(context, cls)).forEach { id ->
                val (w, h) = sizeOf(context, manager, id) ?: defaultSize(size)
                val cities = lists[id] ?: places
                manager.updateAppWidget(id, views(context, size, cities, use24h, now, home, live = true, widthDp = w, heightDp = h, photos = photos))
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

    /** How a row shows its status: the pill under the name, the pill without its vertical padding, a dot before the name, or none (hidden in Settings). */
    private enum class StatusFit { PILL, COMPACT, DOT, NONE }

    /**
     * A row's text sizes and status, the space under its name column ([textPad], dp), whether its tiles stack
     * the hour over AM/PM ([tallTiles]), and how much its status text grows in a taller row ([statusScale]).
     */
    private class RowFit(
        val timeSp: Float, val nameSp: Float, val status: StatusFit, val textPad: Float, val tallTiles: Boolean,
        val statusScale: Float = 1f,
    ) {
        /** The status text (sp): 13 in the full pill, 12 in the compact one (times statusScale in taller rows). */
        val statusSp: Float get() = (if (status == StatusFit.COMPACT) STATUS_COMPACT_SP else STATUS_SP) * statusScale
    }

    /** How much a row [rowHDp] tall grows its contents (1: the designed REF_ROW_H row or shorter), before the caps. */
    private fun rowGrow(rowHDp: Float): Float = (rowHDp / REF_ROW_H).coerceAtLeast(1f)

    /** The tall tiles' height (dp) in a row [rowHDp] tall: TILE_TALL_HEIGHT, up to TILE_GROW_MAX times in taller rows (Android 12+, which can size them). */
    private fun tallTileHeight(rowHDp: Float): Float =
        if (Build.VERSION.SDK_INT >= 31) TILE_TALL_HEIGHT * rowGrow(rowHDp).coerceAtMost(TILE_GROW_MAX) else TILE_TALL_HEIGHT

    /**
     * What fits a row [rowHDp] tall at the phone's font scale, keeping time > name > status (as the app): a
     * 20 sp time and 15 sp name (as the iPhone widget's subheadline) with the full 13 sp pill, then the compact 12 sp pill,
     * then a 14 sp name, then an 18 sp time, then a 13 sp name, then 12 sp; else a status dot before the name and the
     * largest time and name that fit (20, 18 or 15 sp over a 15, 14, 13, 12 or 11 sp name; down to a 10 sp time at the
     * largest font scales). The name column's bottom is level with the tiles' (TEXT_CLEARANCE is 0). At font scale 1:
     * 5 rows at 320 dp (56.8 dp rows): 17 sp time, 12.5 sp name, compact pill (COMPACT_TOP_CLEAR: about 6 dp above
     * the time's cap, 6 dp under the pill; 18/13 left 4.2 dp); 2 rows at 152 dp (67 dp rows) and 4 at
     * 320 dp: 20 sp, 15 sp, full 13 sp pill. Tall tiles (hour over
     * AM/PM) in rows at least TALL_TILE_ROW tall, only while both lines fit the tile at the font scale (through 1.3, about 1.33).
     */
    private fun rowFit(context: Context, rowHDp: Float, wantStatus: Boolean, widthOk: (Float, Float, Float) -> Boolean = { _, _, _ -> true }): RowFit {
        val fs = context.resources.configuration.fontScale.coerceAtLeast(0.5f)
        fun line(sp: Float) = sp * LINE_EM * fs
        val avail = rowHDp - ROW_PAD_TOP - ROW_PAD_BOTTOM
        fun pillH(s: StatusFit, k: Float = 1f): Float = when (s) {
            StatusFit.PILL -> PILL_GAP + maxOf(line(STATUS_SP * k), STATUS_ICON) + 2 * PILL_PAD_V
            StatusFit.COMPACT -> COMPACT_GAP + maxOf(line(STATUS_COMPACT_SP), STATUS_ICON)
            else -> 0f
        }
        fun height(t: Float, n: Float, s: StatusFit) = line(t) + line(n) + pillH(s)
        val tries = if (wantStatus) listOf(
            Triple(20f, 15f, StatusFit.PILL), Triple(20f, 15f, StatusFit.COMPACT),
            Triple(20f, 14f, StatusFit.PILL), Triple(20f, 14f, StatusFit.COMPACT),
            Triple(18f, 15f, StatusFit.PILL), Triple(18f, 15f, StatusFit.COMPACT),
            Triple(18f, 14f, StatusFit.PILL), Triple(18f, 14f, StatusFit.COMPACT),
            Triple(18f, 13f, StatusFit.PILL), Triple(18f, 13f, StatusFit.COMPACT),
            Triple(17f, 12.5f, StatusFit.COMPACT), Triple(18f, 12f, StatusFit.COMPACT),
        ) else emptyList()
        // The compact pill only with COMPACT_TOP_CLEAR above the time; else, as before, the first that fits at all.
        // Rows taller than REF_ROW_H (fewer cities than the widget holds): the 20 sp time, 15 sp name and 13 sp pill
        // grown with the row (time up to TIME_GROW_MAX, name and status up to TEXT_GROW_MAX), as far as they fit.
        val grow = rowGrow(rowHDp)
        val statusMode = if (wantStatus) StatusFit.PILL else StatusFit.NONE
        val gt = grow.coerceAtMost(TIME_GROW_MAX)
        val gn = grow.coerceAtMost(TEXT_GROW_MAX)
        val grown = if (grow <= 1f) null else listOf(1f, 0.75f, 0.5f, 0.25f).map { f ->
            val k = 1f + (gn - 1f) * f
            Triple(20f * (1f + (gt - 1f) * f), 15f * k, k)
        }.firstOrNull { (t, n, k) -> line(t) + line(n) + pillH(statusMode, k) <= avail && widthOk(t, n, k) }
        val statusScale = grown?.third ?: 1f
        val chosen: Triple<Float, Float, StatusFit> =
            grown?.let { Triple(it.first, it.second, statusMode) } ?:
            tries.firstOrNull { (t, n, s) -> height(t, n, s) + (if (s == StatusFit.COMPACT) COMPACT_TOP_CLEAR else 0f) <= avail }
            ?: tries.firstOrNull { (t, n, s) -> height(t, n, s) <= avail }
            ?: run {
                // No room for the pill: the largest time, then the largest name, that fit; at the largest font scales an 11 sp name and a time sized to what is left.
                val pairs = listOf(20f to 15f, 20f to 14f, 20f to 13f, 18f to 15f, 18f to 14f, 18f to 13f, 15f to 13f, 15f to 12f, 15f to 11f)
                val (t, n) = pairs.firstOrNull { (pt, pn) -> line(pt) + line(pn) <= avail }
                    ?: (((avail - line(11f)) / (LINE_EM * fs)).coerceIn(10f, 15f) to 11f)
                Triple(t, n, if (wantStatus) StatusFit.DOT else StatusFit.NONE)
            }
        val (timeSp, nameSp, status) = chosen
        val textH = line(timeSp) + line(nameSp) + pillH(status, statusScale)
        val textPad = if (textH + TEXT_CLEARANCE <= avail) TEXT_CLEARANCE else 0f
        // Tall tiles only while the 13 sp digits (auto-size minimum) over the 12 sp AM/PM, both at the font scale as drawn
        // (applyDimension, non-linear on Android 14+), fit the 38 dp tile (less up to 1 dp of the AM/PM descent); else the one-line tiles.
        val dm = context.resources.displayMetrics
        fun drawnLine(sp: Float) = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, sp, dm) / dm.density * LINE_EM
        val tall = rowHDp >= TALL_TILE_ROW && drawnLine(13f) + drawnLine(AMPM_MIN_SP) <= TILE_TALL_HEIGHT + 1f  // the AM/PM line's descent (no descenders in AM/PM) may overhang
        return RowFit(timeSp, nameSp, status, textPad, tall, statusScale)
    }

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
                w.toFloat(), h.toFloat(), SMALL_RADIUS, maxPx = 400,
                timeSp = 34f, nameSp = 15f, statusSp = STATUS_SP, statusFit = StatusFit.PILL, tiles = false, work = work, textPad = 0f,
                tallTiles = false, home = home))
        } else {
            root.setViewPadding(R.id.content, pad, pad, pad, pad)
            val n = cities.size
            val innerW = w - 2 * PAD
            val innerH = h - 2 * PAD
            val rowH = ((innerH - (n - 1) * ROW_GAP) / n).coerceAtLeast(1f)
            // Every row keeps its status (time > name > status, as the app): a full pill, a tighter one, a
            // slightly smaller time, or at the least a status dot before the name, by what fits the row.
            // Grown text (rows taller than REF_ROW_H) only as far as every city's time, name and pill still fit the text
            // column less MIN_CLEAR (or no wider than at the usual sizes), so growing never truncates anything.
            val capW = (innerW - 2 * ROW_PAD_H - LABEL_GAP) / (1f + TILES_WEIGHT) - (GROW_CLEAR - LABEL_GAP)
            val words = cities.map { p -> if (work.show) status(p, TimeMath.quarter(now), work).second else "" }
            val fit = rowFit(context, rowH, work.show) { t, nm, k ->
                timeWidth(context, t, use24h) <= maxOf(capW, timeWidth(context, 20f, use24h)) &&
                    cities.all { p -> textWidth(context, p.name, nm) <= maxOf(capW, textWidth(context, p.name, 15f)) } &&
                    words.all { wd -> wd.isEmpty() || textWidth(context, wd, STATUS_SP * k) <= maxOf(capW - 29f, textWidth(context, wd, STATUS_SP)) }
            }
            // Tall tiles for the whole widget (the Now capsule's height is shared) only while every half-hour city's widest
            // hour, "10" at the 13 sp auto-size floor plus the 12 sp ":30", fits the tile's width; else every row takes
            // the one-line tiles, whose guard drops AM/PM rather than clip it.
            val tileW = sideTileWidth(innerW)
            val tall = fit.tallTiles && run {
                val dm = context.resources.displayMetrics
                val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
                    fontFeatureSettings = "tnum"
                }
                fun widthDp(t: String, size: Float, unit: Int): Float {
                    paint.textSize = TypedValue.applyDimension(unit, size, dm)
                    return paint.measureText(t) / dm.density
                }
                val anchor = TimeMath.hourAnchor(now, home)
                cities.all { p ->
                    listOf(-1L, 0L, 1L).all { k ->
                        val at = anchor.plusSeconds(k * 3600L).atZone(p.zone)
                        at.minute == 0 ||
                            widthDp(if (use24h) "%02d".format(at.hour) else "${if (at.hour % 12 == 0) 12 else at.hour % 12}", 13f, TypedValue.COMPLEX_UNIT_SP) +
                            widthDp(":%02d".format(at.minute), MINUTES_SP, TypedValue.COMPLEX_UNIT_SP) + 2f <= tileW
                    }
                }
            }
            cities.forEachIndexed { i, place ->
                if (i > 0) root.addView(R.id.content, RemoteViews(context.packageName, R.layout.widget_row_gap))
                root.addView(R.id.content, cell(context, R.layout.widget_photo_row, place, refs[place.id], use24h, now, live,
                    innerW, rowH, ROW_RADIUS, maxPx = 480,
                    timeSp = fit.timeSp, nameSp = fit.nameSp, statusSp = fit.statusSp, statusFit = fit.status, tiles = true, work = work,
                    textPad = fit.textPad, tallTiles = tall, home = home, first = i == 0))
            }
            // One Now capsule down the centre tiles of every row, over the tile column (the overlay spans the widget's full height).
            val blockW = (innerW - 2 * ROW_PAD_H - LABEL_GAP) * TILES_WEIGHT / (1f + TILES_WEIGHT)
            val tileH = if (tall) tallTileHeight(rowH) else TILE_HEIGHT
            capsule(density, blockW, h.toFloat(), n, rowH, tileH, nowGrow(rowH, tileH))?.let {
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
        OFF_HOURS(0xFFD9DEE6.toInt(), R.drawable.ic_moon),
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
        wDp: Float, hDp: Float, cornerDp: Float, maxPx: Int,
        timeSp: Float, nameSp: Float, statusSp: Float, statusFit: StatusFit, tiles: Boolean, work: Work,
        textPad: Float, tallTiles: Boolean, home: ZoneId, first: Boolean = false,
    ): RemoteViews {
        val v = RemoteViews(context.packageName, layout)
        val phase = WidgetSky.phase(place, now)
        // A row is [text block] [clear gap] [tiles]: the text column (weight 1 beside the tiles' TILES_WEIGHT) keeps
        // only what its widest line needs (the time, the name or the status pill); the rest of it, with LABEL_GAP,
        // is the clear gap, never under MIN_CLEAR. The photo slides toward the middle of that gap (PhotoFocus.place).
        var focusDp: Float? = null
        var textEndDp = 0f
        var padEndDp = 0f
        if (tiles) {
            val colW = (wDp - 2 * ROW_PAD_H - LABEL_GAP) / (1f + TILES_WEIGHT)
            val words = if (statusFit != StatusFit.NONE && work.show) status(place, TimeMath.quarter(now), work).second else null
            val block = textBlockWidth(context, place.name, words, statusFit, timeSp, nameSp, statusSp, use24h)
                .coerceAtMost(colW - (MIN_CLEAR - LABEL_GAP)).coerceAtLeast(0f)
            padEndDp = colW - block
            textEndDp = ROW_PAD_H + block
            focusDp = textEndDp + (padEndDp + LABEL_GAP) / 2f
        }
        val art = WidgetSky.background(context, ref, WidgetPhotos.city(context, place), phase, WidgetSky.wantsNight(place, now),
            wDp, hDp, cornerDp, maxPx, focusDp, textEndDp)
        v.setImageViewBitmap(R.id.bg, art.bitmap)
        // White words with a dark halo on every photo (the photo is hardly darkened now; art.bright is always false).
        val ink = if (art.bright) darkInk else lightInk
        v.setViewVisibility(lightInk.box, if (art.bright) View.GONE else View.VISIBLE)
        v.setViewVisibility(darkInk.box, if (art.bright) View.VISIBLE else View.GONE)
        clock(v, ink, place.zone, use24h, now, live, timeSp)
        v.setTextViewText(R.id.name, place.name)
        v.setTextViewTextSize(R.id.name, TypedValue.COMPLEX_UNIT_SP, nameSp)
        // Only the row layout has the status dot.
        val hasDot = layout == R.layout.widget_photo_row
        val d = context.resources.displayMetrics.density
        if (hasDot) {
            v.setViewVisibility(R.id.status_dot, View.GONE)
            // The clear gap (the text column's end padding, worked out above) and the space under the name column.
            v.setViewPadding(R.id.text_col, 0, 0, (padEndDp * d).roundToInt(), (textPad * d).roundToInt())
            // The gap above the full pill only (rowFit counts it there alone).
            val gap = if (!work.show) 0 else when (statusFit) {
                StatusFit.PILL -> (PILL_GAP * d).roundToInt()
                StatusFit.COMPACT -> (COMPACT_GAP * d).roundToInt()
                else -> 0
            }
            v.setViewPadding(R.id.name_row, 0, 0, 0, gap)
        }
        v.setContentDescription(R.id.name, null)
        if (statusFit != StatusFit.NONE && work.show) {
            val (kind, text) = status(place, TimeMath.quarter(now), work)
            if (statusFit == StatusFit.DOT && hasDot) {
                // No room for the pill: its colour as a dot before the name, and its words for TalkBack.
                v.setViewVisibility(R.id.status, View.GONE)
                v.setInt(R.id.status_dot, "setColorFilter", kind.color)
                v.setViewVisibility(R.id.status_dot, View.VISIBLE)
                v.setContentDescription(R.id.name, "${place.name}, $text")
            } else {
                val padV = if (statusFit == StatusFit.COMPACT) 0 else (PILL_PAD_V * d).roundToInt()
                v.setViewPadding(R.id.status, (6 * d).roundToInt(), padV, (7 * d).roundToInt(), padV)
                v.setTextViewText(R.id.status_text, text)
                v.setTextViewTextSize(R.id.status_text, TypedValue.COMPLEX_UNIT_SP, statusSp)
                v.setTextColor(R.id.status_text, kind.color)
                v.setImageViewResource(R.id.status_icon, kind.icon)
                v.setInt(R.id.status_icon, "setColorFilter", kind.color)
                v.setViewVisibility(R.id.status, View.VISIBLE)
            }
        } else {
            v.setViewVisibility(R.id.status, View.GONE)
        }
        if (tiles) tiles(context, v, place, use24h, now, home, work, wDp, hDp, tallTiles, first)
        return v
    }

    /** The AM/PM beside a time [size] sp (see clock). */
    private fun ampmSize(size: Float): Float = maxOf(size * 0.45f, AMPM_MIN_SP).coerceAtMost(maxOf(size - 3f, minOf(AMPM_MIN_SP, size)))

    /**
     * The width (dp) a row's text block needs: its widest line of the time (any time: tabular digits), the name
     * (after the status dot, where it has one) and the status pill (6 + 12 icon + 4 + words + 7 dp), plus 2 dp.
     */
    private fun textBlockWidth(
        context: Context, name: String, words: String?, fit: StatusFit, timeSp: Float, nameSp: Float, statusSp: Float, use24h: Boolean,
    ): Float {
        val time = timeWidth(context, timeSp, use24h)
        val title = textWidth(context, name, nameSp) + (if (fit == StatusFit.DOT) 12f else 0f)
        val pill = if (words != null && (fit == StatusFit.PILL || fit == StatusFit.COMPACT)) 6f + STATUS_ICON + 4f + 7f + textWidth(context, words, statusSp) else 0f
        return maxOf(time, title, pill) + 2f
    }

    /** [text]'s width (dp) in the widgets' medium face at [sp] (tabular digits with [tabular]). */
    private fun textWidth(context: Context, text: String, sp: Float, tabular: Boolean = false): Float {
        val dm = context.resources.displayMetrics
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            if (tabular) fontFeatureSettings = "tnum"
            textSize = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, sp, dm)
        }
        return paint.measureText(text) / dm.density
    }

    /** The widest a time at [sp] gets (dp): "12:00" (tabular digits) and, on the 12-hour clock, 2 dp and AM or PM. */
    private fun timeWidth(context: Context, sp: Float, use24h: Boolean): Float =
        if (use24h) textWidth(context, "00:00", sp, true)
        else textWidth(context, "12:00", sp, true) + 2f + maxOf(textWidth(context, "AM", ampmSize(sp), true), textWidth(context, "PM", ampmSize(sp), true))

    /** The time, with AM/PM at 0.45 of its size, as on the cards, never under AMPM_MIN_SP (12 sp), and never above the digits (only a time under 12 sp pulls AM/PM below the floor, to the digits' own size). */
    private fun clock(v: RemoteViews, ids: TimeIds, zone: ZoneId, use24h: Boolean, now: Instant, live: Boolean, size: Float) {
        listOf(ids.clock, ids.clockStatic).forEach { v.setTextViewTextSize(it, TypedValue.COMPLEX_UNIT_SP, size) }
        listOf(ids.ampm, ids.ampmStatic).forEach { v.setTextViewTextSize(it, TypedValue.COMPLEX_UNIT_SP, ampmSize(size)) }
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

    /**
     * The hour before, now and the hour after, lined up on the home hour (as the app's tiles and the iPhone widget) and
     * shown on the city's clock, so a half-hour city reads "9:30 PM" under the Now capsule on every surface: the day's
     * colour there, quieter outside working hours.
     */
    /** The hour before's and after's tile width (dp) in a row [wDp] wide: the tile column less its six margins (2 dp, the Now tile's 5 dp), shared 1 : NOW_WIDTH : 1. */
    private fun sideTileWidth(wDp: Float): Float =
        ((wDp - 2 * ROW_PAD_H - LABEL_GAP) * TILES_WEIGHT / (1f + TILES_WEIGHT) - 6 * TILE_MARGIN - 2 * NOW_EXTRA) / (2f + NOW_WIDTH)

    /** How far (dp) the Now tile reaches above and below its neighbours: NOW_GROW, or less where the row has no room above the tiles. */
    private fun nowGrow(rowHDp: Float, tileHDp: Float): Float =
        minOf(NOW_GROW, rowHDp - ROW_PAD_TOP - ROW_PAD_BOTTOM - tileHDp, ROW_PAD_BOTTOM).coerceAtLeast(0f)

    private fun tiles(context: Context, v: RemoteViews, place: Place, use24h: Boolean, now: Instant, home: ZoneId, work: Work, wDp: Float, hDp: Float, tall: Boolean, first: Boolean) {
        val zone = place.zone
        // Rows at least TALL_TILE_ROW tall: the hour over AM/PM (as the app's tiles); shorter rows: "10 AM" on one line.
        v.setViewVisibility(R.id.tiles, if (tall) View.GONE else View.VISIBLE)
        v.setViewVisibility(R.id.tiles_tall, if (tall) View.VISIBLE else View.GONE)
        val ids = if (tall) listOf(R.id.tile0_tall, R.id.tile1_tall, R.id.tile2_tall) else listOf(R.id.tile0, R.id.tile1, R.id.tile2)
        val edges = if (tall) listOf(R.id.tile0_tall_edge, R.id.tile1_tall_edge, R.id.tile2_tall_edge) else listOf(R.id.tile0_edge, R.id.tile1_edge, R.id.tile2_edge)
        // AM/PM is always 12 sp (as the app), following the font scale; where "10 PM" would not fit the tile (the
        // narrowest widths, large font scales) the row drops AM/PM (keepSuffix) rather than shrink or cut it. The digits
        // take one size for the row (rowSp, below), 17 sp down to 11; the layout's auto-size stays only as a safety net.
        val tileW = sideTileWidth(wDp)
        val nowW = tileW * NOW_WIDTH
        val tileH = if (tall) tallTileHeight(hDp) else TILE_HEIGHT
        val grow = nowGrow(hDp, tileH)
        // Taller rows (Android 12+): the tall tiles grow with the row (tallTileHeight), the Now slot NOW_GROW more each way.
        if (tall && Build.VERSION.SDK_INT >= 31 && tileH > TILE_TALL_HEIGHT) {
            v.setViewLayoutHeight(R.id.tiles_tall, tileH + 2 * NOW_GROW, TypedValue.COMPLEX_UNIT_DIP)
            v.setViewLayoutHeight(R.id.tile0_tall_slot, tileH, TypedValue.COMPLEX_UNIT_DIP)
            v.setViewLayoutHeight(R.id.tile2_tall_slot, tileH, TypedValue.COMPLEX_UNIT_DIP)
        }
        val nowH = tileH + 2 * grow
        // The Now tile's slot is NOW_GROW taller each way in the layout; pad it back where the row is shorter.
        val trim = ((NOW_GROW - grow) * context.resources.displayMetrics.density).roundToInt()
        v.setViewPadding(if (tall) R.id.tile1_tall_slot else R.id.tile1_slot, 0, trim, 0, trim)
        val ampmSp = AMPM_MIN_SP
        val starts = listOf(-1L, 0L, 1L).map { TimeMath.hourAnchor(now, home).plusSeconds(it * 3600L).atZone(zone) }
        // Half-hour cities: the minutes as a small ":30" (12 sp, MINUTES_SP) after the hour.
        fun digits(hour: Int) = if (use24h) "%02d".format(hour) else "${if (hour % 12 == 0) 12 else hour % 12}"
        fun suffix(hour: Int) = if (use24h) null else if (hour < 12) "AM" else "PM"
        // One-line tiles: "10:30 PM" with the digits at their 11 sp floor must fit the tile; if the widest of the row's
        // three does not (half-hour cities on narrow widgets, 12-hour clock), the row's tiles drop AM/PM together (the
        // city's own time beside them carries it, and the tile's sky colour says day or night) rather than clip it.
        val dm = context.resources.displayMetrics
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
            fontFeatureSettings = "tnum"
        }
        fun widthDp(text: String, size: Float, unit: Int): Float {
            paint.textSize = TypedValue.applyDimension(unit, size, dm)
            return paint.measureText(text) / dm.density
        }
        fun drawnLine(sp: Float) = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, sp, dm) / dm.density * LINE_EM
        // One-line tiles: AM/PM at the font scale must also fit the 24 dp tile's height.
        val keepSuffix = tall || (drawnLine(ampmSp) <= TILE_HEIGHT && run {
            starts.maxOf { at ->
                widthDp(digits(at.hour) + TimeMath.THIN, 11f, TypedValue.COMPLEX_UNIT_SP) +
                    widthDp(":%02d".format(at.minute), MINUTES_SP, TypedValue.COMPLEX_UNIT_SP) +
                    widthDp(suffix(at.hour) ?: "", ampmSp, TypedValue.COMPLEX_UNIT_SP)
            } + 2f <= tileW
        })
        // One hour size for the whole row (as the app's HourTiles), not each tile auto-sizing on its own (which put
        // "10 PM" at 14 sp beside "9 PM" at 17): the largest size from 17 sp down to 11 at which all three labels fit
        // the tile's width (and, one-line, the 24 dp tile's height), set as an absolute span below so auto-size
        // cannot pull the tiles apart. Tall tiles: AM/PM is on its own line, so only the digits (and ":30") count
        // across, both lines count down, and the row keeps its 13 sp floor (the tall gate already checked 13 sp fits).
        // The largest digits: 17 sp, grown with taller tiles (tall tiles only).
        val maxSp = if (tall) (17f * tileH / TILE_TALL_HEIGHT).toInt().coerceAtLeast(17) else 17
        val fitSp = (maxSp downTo 11).firstOrNull { sp ->
            starts.all { at ->
                widthDp(digits(at.hour), sp.toFloat(), TypedValue.COMPLEX_UNIT_SP) +
                    (if (at.minute != 0) widthDp(":%02d".format(at.minute), MINUTES_SP, TypedValue.COMPLEX_UNIT_SP) else 0f) +
                    (if (keepSuffix && !use24h && !tall) widthDp(TimeMath.THIN + (suffix(at.hour) ?: ""), ampmSp, TypedValue.COMPLEX_UNIT_SP) else 0f) +
                    2f <= tileW
            } && (if (tall) drawnLine(sp.toFloat()) + drawnLine(ampmSp) <= tileH + 1f else drawnLine(sp.toFloat()) <= TILE_HEIGHT)
        }?.toFloat() ?: 11f
        val rowSp = if (tall) minOf(fitSp, maxSp.toFloat()).coerceAtLeast(13f) else fitSp
        // The Now tile: its digits up to NOW_DIGITS_UP sp and AM/PM and ":30" NOW_SMALL_UP sp larger, as far as its
        // label fits its wider, taller tile (else the row's sizes, which fit the narrower tiles).
        val nowAt = starts[1]
        fun nowFits(sp: Float, small: Float): Boolean =
            widthDp(digits(nowAt.hour), sp, TypedValue.COMPLEX_UNIT_SP) +
                (if (nowAt.minute != 0) widthDp(":%02d".format(nowAt.minute), MINUTES_SP + (small - ampmSp), TypedValue.COMPLEX_UNIT_SP) else 0f) +
                (if (keepSuffix && !use24h && !tall) widthDp(TimeMath.THIN + (suffix(nowAt.hour) ?: ""), small, TypedValue.COMPLEX_UNIT_SP) else 0f) +
                2f <= nowW &&
                (if (tall) drawnLine(sp) + drawnLine(small) <= nowH + 1f else drawnLine(sp) <= nowH && drawnLine(small) <= nowH)
        // The new day's weekday tag, over the tile where a new day starts there (midnight; every tile keeps its hour and
        // AM/PM, "12" over "AM"): TAG_GAP above the tile, full height or compact, whichever keeps TAG_TOP_CLEAR from the
        // row's top. The first row's Now tile has the Now outline's top line just above it (capsule: TILE_MARGIN out,
        // CAPSULE_HALO wide), so there the tag sits TAG_LINE_CLEAR above that line, or, with no room, inside the tile's
        // top (never on the line). Any other tile in a row too short: the compact tag as high as the row allows, over
        // the tile's top edge (in the 56.8 dp rows of five cities, 0.7 dp over a side tile and 4.7 dp over the Now tile, both
        // above the hour's digits).
        val dayTags: List<DayTag?> = starts.mapIndexed { i, at ->
            if (at.toLocalDate() == at.toInstant().minusSeconds(3600L).atZone(zone).toLocalDate()) null else {
                val tileTop = ROW_PAD_BOTTOM + tileH + (if (i == 1) grow else 0f)
                val underLine = first && i == 1
                val gap = if (underLine) NOW_INSET + CAPSULE_HALO / 2 + TAG_LINE_CLEAR else TAG_GAP
                val fits = listOf(TAG_H, TAG_COMPACT_H).firstOrNull { tileTop + gap + it + TAG_TOP_CLEAR <= hDp }
                when {
                    fits != null -> DayTag(tileTop + gap, fits, false)
                    underLine -> DayTag((tileTop - TAG_INSET - TAG_COMPACT_H).coerceAtLeast(0f), TAG_COMPACT_H, true)
                    else -> DayTag((hDp - TAG_TOP_CLEAR - TAG_COMPACT_H).coerceAtLeast(0f), TAG_COMPACT_H, false)
                }
            }
        }
        // With the tag inside the Now tile, the tile's label takes the row's sizes and sits under the tag (nowPush, below).
        val tagInNow = dayTags[1]?.inside == true
        // Its digits: the largest size from the row's down to 11 sp whose cap (0.18 of the line under the line's top) clears the tag.
        val nowSizes = if (tagInNow) ((rowSp.toInt() downTo 11).map { it.toFloat() }.firstOrNull { (if (tall) drawnLine(it) + drawnLine(ampmSp) else drawnLine(it)) + TAG_INSET + TAG_COMPACT_H <= nowH + drawnLine(it) * 0.18f } ?: 11f) to ampmSp else (NOW_DIGITS_UP downTo 0).map { up -> (rowSp + up) to (if (up > 0) ampmSp + NOW_SMALL_UP else ampmSp) }
            .firstOrNull { (sp, small) -> nowFits(sp, small) } ?: (rowSp to ampmSp)
        // Top padding (dp) on the Now tile's label then: what its lines leave of the tile, at most the tag's depth.
        val nowPush = if (!tagInNow) 0f else
            minOf(nowH - (if (tall) drawnLine(nowSizes.first) + drawnLine(ampmSp) else drawnLine(nowSizes.first)), TAG_INSET + TAG_COMPACT_H).coerceAtLeast(0f)
        v.setViewPadding(ids[1], 0, (nowPush * dm.density).roundToInt(), 0, 0)
        val tagIds = listOf(R.id.day_tag0, R.id.day_tag1, R.id.day_tag2)
        val tagSlots = listOf(R.id.day_tag0_slot, R.id.day_tag1_slot, R.id.day_tag2_slot)
        tagIds.indices.forEach { i ->
            val tag = dayTags[i]
            if (tag == null) {
                v.setViewVisibility(tagIds[i], View.GONE)
            } else {
                val name = TimeMath.weekday(starts[i].toInstant(), zone).uppercase()
                // Never wider than its tile, so it stays between the Now outline's vertical lines (in the gaps beside the Now tile).
                val padH = minOf(TAG_PAD_H, ((if (i == 1) nowW else tileW) - widthDp(name, TAG_DP, TypedValue.COMPLEX_UNIT_DIP) - 1f) / 2f).coerceAtLeast(0f)
                val padV = ((tag.height - TAG_DP * LINE_EM) / 2f).coerceAtLeast(0f)
                val padHPx = (padH * dm.density).roundToInt()
                val padVPx = (padV * dm.density).roundToInt()
                v.setTextViewText(tagIds[i], name)
                v.setTextViewTextSize(tagIds[i], TypedValue.COMPLEX_UNIT_DIP, TAG_DP)
                v.setViewPadding(tagIds[i], padHPx, padVPx, padHPx, padVPx)
                v.setViewPadding(tagSlots[i], 0, 0, 0, (tag.bottom * dm.density).roundToInt())
                v.setViewVisibility(tagIds[i], View.VISIBLE)
            }
        }
        ids.indices.forEach { i ->
            val id = ids[i]
            val at = starts[i]
            val dim = work.show && !WorkWeek.isWorking(place, at.toInstant().plusSeconds(1800), work.start, work.end)
            // Working tiles (where working hours show) no darker than TILE_WORKING_FLOOR, as the app's; dimmed ones as before.
            // Only at day and shoulder hours (6:30 AM to 8:30 PM), as the app's, so a working night tile keeps its navy.
            val h = at.hour + at.minute / 60.0
            val color = capped(DayColor.at(h), if (work.show && !dim && h >= 6.5 && h <= 20.5) TILE_WORKING_FLOOR else 0.0)
            val head = digits(at.hour)
            val minutes = if (at.minute != 0) ":%02d".format(at.minute) else ""
            val period = if (keepSuffix) suffix(at.hour) else null
            // "10 AM" with a smaller AM, as on the iPhone (12 sp, following the font scale; the hour at the row's
            // rowSp); tall tiles: "10" over "AM" (rowSp digits, 17 sp down to 13; 12 sp AM/PM).
            val label = head + minutes + when {
                period == null -> ""
                tall -> "\n$period"
                else -> TimeMath.THIN + period
            }
            val text = android.text.SpannableString(label)
            val flags = android.text.Spanned.SPAN_EXCLUSIVE_EXCLUSIVE
            // Sizes in px from sp (dip = false), so ":30" and AM/PM follow the font scale with the hour digits.
            fun spPx(sp: Float) = TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_SP, sp, dm).roundToInt()
            val digitSp = if (i == 1) nowSizes.first else rowSp
            val smallSp = if (i == 1) nowSizes.second else ampmSp
            val minutesSp = MINUTES_SP + (smallSp - ampmSp)
            text.setSpan(android.text.style.AbsoluteSizeSpan(spPx(digitSp), false), 0, head.length, flags)
            if (minutes.isNotEmpty()) text.setSpan(android.text.style.AbsoluteSizeSpan(spPx(minutesSp), false), head.length, head.length + minutes.length, flags)
            // The separator before AM/PM (the thin space, or the tall tiles' line break) at AM/PM's size too, as rowSp
            // measured it, so no character is left at the auto-sized base size (a 17 sp break would heighten the hour's line).
            if (period != null) text.setSpan(android.text.style.AbsoluteSizeSpan(spPx(smallSp), false), label.length - period.length - 1, label.length, flags)
            v.setTextViewText(id, text)
            // TalkBack: the tile's own text, and at a new day its weekday too ("12 AM, Wednesday").
            v.setContentDescription(id, if (dayTags[i] == null) null else
                head + minutes + (suffix(at.hour)?.let { " $it" } ?: "") + ", " +
                    at.dayOfWeek.getDisplayName(java.time.format.TextStyle.FULL, java.util.Locale.US))
            v.setTextColor(id, 0xFFFFFFFF.toInt())
            // Opaque either way: the dimmed tile is darker, not see-through, so photo highlights never sit under its text.
            val fill = if (dim) TileDim.opaque(color) else color
            if (Build.VERSION.SDK_INT >= 31) v.setColorStateList(id, "setBackgroundTintList", ColorStateList.valueOf(fill))
            else v.setInt(id, "setBackgroundColor", fill)
            // Off-hours and night tiles: a 1 dp white 32% edge over the tile (an overlay, so the tint above never touches it).
            v.setViewVisibility(edges[i], if (luminance(fill) <= EDGE_MAX_LUMINANCE) View.VISIBLE else View.GONE)
        }
    }

    /** [rgb]'s relative luminance (WCAG). */
    private fun luminance(rgb: Int): Double {
        fun lin(v: Int): Double { val c = v / 255.0; return if (c <= 0.04045) c / 12.92 else Math.pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin((rgb shr 16) and 0xFF) + 0.7152 * lin((rgb shr 8) and 0xFF) + 0.0722 * lin(rgb and 0xFF)
    }

    /** [rgb] with its linear light scaled (same hue) so its relative luminance is at most [TILE_MAX_LUMINANCE] and at least [floor]. */
    private fun capped(rgb: Int, floor: Double = 0.0): Int {
        fun lin(v: Int): Double { val c = v / 255.0; return if (c <= 0.04045) c / 12.92 else Math.pow((c + 0.055) / 1.055, 2.4) }
        fun enc(l: Double): Int { val c = if (l <= 0.0031308) l * 12.92 else 1.055 * Math.pow(l, 1 / 2.4) - 0.055; return (c * 255).roundToInt().coerceIn(0, 255) }
        val r = lin((rgb shr 16) and 0xFF); val g = lin((rgb shr 8) and 0xFF); val b = lin(rgb and 0xFF)
        val l = 0.2126 * r + 0.7152 * g + 0.0722 * b
        if (l <= 0.0 || (l <= TILE_MAX_LUMINANCE && l >= floor)) return rgb
        val k = (if (l > TILE_MAX_LUMINANCE) TILE_MAX_LUMINANCE else floor) / l
        return (0xFF shl 24) or (enc(r * k) shl 16) or (enc(g * k) shl 8) or enc(b * k)
    }

    /**
     * The Now outline: a rounded rectangle concentric with the Now (centre) tiles of every row, its stroke's centre
     * line midway in the 7 dp gap between the Now tiles and their neighbours (inset = NOW_INSET, 3.5 dp, outside the
     * Now tiles' sides, above the first row's Now tile and below the last's), its corners the tiles' 6 dp radius plus
     * that inset, so its ends follow the tiles' corners. A 1.5 dp white 85% line over a 3 dp black 60% halo (no fill or
     * glow), 2 dp clear of the tiles on both sides. Drawn for the tile column ([blockWDp] by the widget's full
     * [heightDp]), which the layout stretches to fit, so it stays on the tiles if the launcher's size is a little off.
     */
    private fun capsule(density: Float, blockWDp: Float, heightDp: Float, n: Int, rowHDp: Float, tileHDp: Float, growDp: Float): Bitmap? {
        if (blockWDp <= 0f || heightDp <= 0f || n <= 0) return null
        val s = minOf(density, 2f)
        val bw = (blockWDp * s).roundToInt()
        val bh = (heightDp * s).roundToInt()
        if (bw < 4 || bh < 4) return null
        val side = ((blockWDp - 6 * TILE_MARGIN - 2 * NOW_EXTRA) / (2f + NOW_WIDTH)).coerceAtLeast(0f)
        // The Now tiles' edges (dp, in the overlay, which spans the widget: rows start at PAD), growDp above and below
        // their neighbours' common centre.
        val tileLeft = side + 3 * TILE_MARGIN + NOW_EXTRA
        val tileRight = tileLeft + side * NOW_WIDTH
        val firstTop = PAD + rowHDp - ROW_PAD_BOTTOM - tileHDp - growDp
        val lastBottom = PAD + (n - 1) * (rowHDp + ROW_GAP) + rowHDp - ROW_PAD_BOTTOM + growDp
        // The stroke's centre line: half the 7 dp gap (NOW_INSET) outside the Now tiles, kept 1 dp inside the overlay.
        val inset = NOW_INSET
        val edge = CAPSULE_HALO / 2 + 1f
        val left = tileLeft - inset
        val right = tileRight + inset
        val top = maxOf(firstTop - inset, edge)
        val bottom = minOf(lastBottom + inset, heightDp - edge)
        if (bottom <= top || right <= left) return null
        val radius = minOf(TILE_CORNER + inset, (right - left) / 2f, (bottom - top) / 2f)
        val bitmap = Bitmap.createBitmap(bw, bh, Bitmap.Config.ARGB_8888)
        val c = Canvas(bitmap)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        fun white(alpha: Float) = ((alpha * 255).roundToInt().coerceIn(0, 255) shl 24) or 0xFFFFFF
        paint.style = Paint.Style.STROKE
        // First the dark halo, then the white line on it, both centred on the same line.
        val line = RectF(left * s, top * s, right * s, bottom * s)
        paint.strokeWidth = CAPSULE_HALO * s
        paint.color = ((CAPSULE_HALO_ALPHA * 255).roundToInt() shl 24)
        c.drawRoundRect(line, radius * s, radius * s, paint)
        paint.strokeWidth = CAPSULE_LINE * s
        paint.color = white(CAPSULE_ALPHA)
        c.drawRoundRect(line, radius * s, radius * s, paint)
        return bitmap
    }

    /**
     * Refresh the pictures, status and tiles at the start of the next quarter hour (inexact is fine; clocks tick on their
     * own). Every zone's offset is a whole number of quarter hours, so every city's working hours start and end on one.
     */
    private fun scheduleNextQuarter(context: Context) {
        val alarms = context.getSystemService(AlarmManager::class.java) ?: return
        val next = TimeMath.quarter(Instant.now()).plusSeconds(900 + 5)
        val intent = PendingIntent.getBroadcast(context, 1, Intent(context, WidgetClock::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        alarms.set(AlarmManager.RTC, next.toEpochMilli(), intent)
    }
}

/**
 * A widget's photo, drawn as the cards draw theirs: cropped to fill (its skyline at the middle), the city's
 * day photo by day and its night photo (the app's <key>-night.jpg copy) by night and after sunset, each
 * as taken; dawn is the day photo a little warmer, and a city with no night photo has its day photo
 * darkened and cooled as before. Sharp and hardly darkened: in a row, centred in the clear gap between the words
 * and the tiles and shaded only over the words (see background), with rounded corners; or, with no photo, a sky for
 * the time of day with a skyline drawn for the city.
 */
private object WidgetSky {
    enum class Phase { DAY, TWILIGHT, NIGHT }

    /** The picture, and whether it's bright behind the time (for dark numbers; now always false: white words with a halo). */
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

    /**
     * The night photo only once the sun has set and sunrise is more than an hour away, as the iPhone's
     * (WidgetSky.wantsNightPhoto); the hour before sunset keeps the day photo, a little warmer.
     */
    fun wantsNight(place: Place, at: Instant): Boolean = when (Sun.phase(place, at)) {
        is Sun.Phase.Day, Sun.Phase.AllDay -> false
        Sun.Phase.AllNight -> true
        is Sun.Phase.Night -> Sun.phase(place, at.plusSeconds(3600)).let { it is Sun.Phase.Night || it == Sun.Phase.AllNight }
        null -> at.atZone(place.zone).hour !in 7..18
    }

    /** The fallback shading, for a city with no night photo: night about 45% darker and a little cooler; dawn and dusk a little warmer; day as taken. */
    private fun gain(phase: Phase): FloatArray? = when (phase) {
        Phase.NIGHT -> floatArrayOf(0.400f, 0.459f, 0.522f)
        Phase.TWILIGHT -> floatArrayOf(1f, 0.949f, 0.878f)
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
     * a widget's pictures stay small. The photo covers the picture with its skyline (the manifest's focus) at the
     * middle of the height (PhotoFocus.place); a row ([focusDp] set: the middle of its clear gap, dp from its left)
     * may zoom up to 15% more only to move the photo's centre toward there. In a row the only darkening is over its text block (to [textEndDp]): black 45% at the left edge easing
     * (smoothstep) to nothing at the block's end, none over the gap and the tiles. The small widget ([focusDp] null):
     * the photo cropped to fill as the cards, darkened only behind its words at the bottom: black 45% at the bottom
     * easing to nothing 45% up. No blur; the words carry their own halo (and the status its pill).
     */
    fun background(
        context: Context, ref: WidgetPhotos.Ref?, city: String, phase: Phase, wantsNight: Boolean,
        wDp: Float, hDp: Float, cornerDp: Float, maxPx: Int, focusDp: Float?, textEndDp: Float,
    ): Art {
        val density = context.resources.displayMetrics.density
        val scale = minOf(density, maxPx / wDp.coerceAtLeast(1f)).coerceAtLeast(0.25f)
        val bw = (wDp * scale).roundToInt().coerceAtLeast(2)
        val bh = (hDp * scale).roundToInt().coerceAtLeast(2)
        val out = Bitmap.createBitmap(bw, bh, Bitmap.Config.ARGB_8888)
        val c = Canvas(out)
        val w = bw.toFloat()
        val h = bh.toFloat()
        // A row's photo centre (px), in the middle of its clear gap.
        val fx = focusDp?.let { (it * scale).coerceIn(0f, w) }
        // After sunset with sunrise over an hour away ([wantsNight]): the night photo as taken. Else (or with no night
        // photo) the day photo, shaded as before.
        // Cropped to fill, at most 15% more on a row (only to move its centre toward fx): see PhotoFocus.place.
        // Decoded at about the width it is drawn (never over 600 px), so it stays sharp and small.
        val needW = if (fx != null) w * 1.15f else w
        val decodeW = minOf(needW.roundToInt().coerceAtLeast(bw), 600)
        val night = if (wantsNight && ref != null) WidgetPhotos.loadNight(context, ref, decodeW) else null
        val photo = night ?: ref?.let { WidgetPhotos.load(context, it, decodeW) }
        if (photo != null && ref != null) {
            val iw = photo.width.toFloat()
            val ih = photo.height.toFloat()
            // The photo's skyline (the manifest's focus for the photo drawn) at the middle of the height, as the cards.
            val at = PhotoFocus.place(iw, ih, w, h, if (night != null) ref.nightFocus else ref.focus, fx)
            val dw = iw * at[0]
            val dh = ih * at[0]
            val offX = at[1]
            val offY = at[2]
            val paint = Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG)
            (if (night != null) null else gain(phase))?.let { g ->
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
        // The one shade: black SHADE_MAX easing by smoothstep to nothing (eleven stops, so no band shows), from the
        // left edge to the text block's end (rows) or from the bottom to 45% up (the small widget).
        val stops = 11
        val positions = FloatArray(stops) { it / (stops - 1f) }
        val colors = IntArray(stops) { i ->
            val t = positions[i]
            ((SHADE_MAX * (1f - t * t * (3f - 2f * t)) * 255).roundToInt().coerceIn(0, 255)) shl 24
        }
        val shade = Paint()
        if (fx != null) {
            val end = (textEndDp * scale).coerceIn(1f, w)
            shade.shader = LinearGradient(0f, 0f, end, 0f, colors, positions, Shader.TileMode.CLAMP)
            c.drawRect(0f, 0f, end, h, shade)
        } else {
            val top = h * 0.55f
            shade.shader = LinearGradient(0f, h, 0f, top, colors, positions, Shader.TileMode.CLAMP)
            c.drawRect(0f, top, w, h, shade)
        }
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
        return Art(out, false)
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

    /** The darkening at the far left of a row's text block (and the bottom of the small widget), black 45%. */
    private const val SHADE_MAX = 0.45f
}

/** The quarter-hour alarm, and the phone's time, time zone or date changing: redraw the widgets. */
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

    /** Removed: forget the widget's own cities. */
    override fun onDeleted(context: Context, ids: IntArray) {
        val edit = Store.prefs(context).edit()
        ids.forEach { id -> edit.remove(MeridianWidgets.followKey(id)).remove(MeridianWidgets.citiesKey(id)) }
        edit.apply()
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
