package com.bradcowdrey.meridian

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.ZoneId
import kotlin.math.roundToInt

/**
 * All app state. Settings and cities persist to SharedPreferences (the widgets read the same
 * cities from there). Demo mode (store screenshots): fixed cities and a fixed moment, nothing saved.
 */
class Store(private val context: Context, val demo: Boolean = false) {
    companion object {
        const val MAX_PLACES = 12
        /** Demo moment: Tuesday 9 June 2026, 9:41 AM in San Francisco. */
        val DEMO_DATE: Instant = Instant.ofEpochSecond(1_781_023_260)

        fun prefs(context: Context) = context.getSharedPreferences("meridian", Context.MODE_PRIVATE)

        fun loadPlaces(context: Context): List<Place>? {
            val json = prefs(context).getString("places", null) ?: return null
            return runCatching {
                val array = JSONArray(json)
                (0 until array.length()).map {
                    val o = array.getJSONObject(it)
                    Place(
                        o.getString("name"), o.getString("zone"), o.optString("id").ifEmpty { java.util.UUID.randomUUID().toString() },
                        workDays = o.optJSONArray("workDays")?.let { a -> (0 until a.length()).map { a.getInt(it) }.toSet() },
                        workStart = if (o.has("workStart")) o.getInt("workStart") else null,
                        workEnd = if (o.has("workEnd")) o.getInt("workEnd") else null,
                    )
                }
            }.getOrNull()
        }

        fun use24h(context: Context): Boolean =
            prefs(context).let { if (it.contains("use24h")) it.getBoolean("use24h", false) else android.text.format.DateFormat.is24HourFormat(context) }
    }

    private val prefs = prefs(context)

    /** "Your time": the phone's zone (Los Angeles in demo mode, so screenshots are the same everywhere). */
    val home: ZoneId = if (demo) ZoneId.of("America/Los_Angeles") else ZoneId.systemDefault()

    var places by mutableStateOf(
        if (demo) listOf(
            Place("San Francisco", "America/Los_Angeles"), Place("New York", "America/New_York"),
            Place("London", "Europe/London"), Place("Dubai", "Asia/Dubai"),
            Place("Mumbai", "Asia/Kolkata"), Place("Tokyo", "Asia/Tokyo"),
        ) else loadPlaces(context) ?: starterPlaces()
    )
        private set
    var use24h by mutableStateOf(if (demo) false else use24h(context))
        private set
    var showWorkHours by mutableStateOf(prefs.getBoolean("showWorkHours", true))
        private set
    var workStart by mutableIntStateOf(prefs.getInt("workStart", 9))
        private set
    var workEnd by mutableIntStateOf(prefs.getInt("workEnd", 18))
        private set
    var termsAccepted by mutableStateOf(demo || !Terms.due(prefs))
        private set
    var hasScrubbed by mutableStateOf(demo || prefs.getBoolean("hasScrubbed", false))
        private set
    /** Keep a "My Location" row for the city you're in (on unless turned off in Settings). */
    var useMyLocation by mutableStateOf(!demo && prefs.getBoolean("useMyLocation", true))
        private set
    /** Answered the first-launch "Use your location?" question (or changed the setting). */
    var locationChosen by mutableStateOf(demo || prefs.getBoolean("myLocation.chosen", false))
        private set

    /** Time travel in minutes (whole quarter-hours) from the current quarter-hour; 0 is now. */
    var offsetMinutes by mutableIntStateOf(0)
        private set
    /** Counts the user's own moves through time, for haptics. */
    var userMoves by mutableIntStateOf(0)
        private set
    var now by mutableStateOf(if (demo) DEMO_DATE else Instant.now())
        private set

    /** The card standing in for My Location (you already have a card in this time zone).
     *  Declared before init, which sets it. */
    var myLocationHost by mutableStateOf<String?>(null)
        private set

    init {
        if (!demo) {
            if (loadPlaces(context) == null) update(places)   // save the starter cities for the widgets
            updateMyLocation()
            syncWidgets()
        }
    }

    private fun starterPlaces(): List<Place> {
        val local = ZoneId.systemDefault().id
        val name = local.substringAfterLast('/').replace("_", " ")
        val list = mutableListOf(Place(name, local))
        listOf("New York" to "America/New_York", "London" to "Europe/London", "Tokyo" to "Asia/Tokyo")
            .filter { it.second != local }.forEach { list += Place(it.first, it.second) }
        return list
    }

    // MARK: Clock

    /** Called every second; moves the clock on when the minute changes. */
    fun tick() {
        if (demo) return
        val date = Instant.now()
        if (date.epochSecond / 60 == now.epochSecond / 60) return
        // A picked time (a date, a tapped hour) stays where it is as the clock moves; a shift
        // ("+3 hr") moves with it.
        if (anchored && offsetMinutes != 0) {
            val passed = ((date.epochSecond - now.epochSecond) / 60.0).roundToInt()
            if (passed != 0) offsetMinutes -= passed
        }
        now = date
    }

    val isNow get() = offsetMinutes == 0
    /** Now, or some minutes from now ("+3 hr" is exactly three hours on). */
    val moment: Instant get() = now.plusSeconds(offsetMinutes * 60L)
    val onTheHour get() = offsetMinutes % 60 == 0 || moment.atZone(home).minute == 0

    /** The moment was picked (a date, a tapped hour), so it stays put as the clock moves. */
    private var anchored = false

    /** Go to a moment, which then stays put. */
    fun jump(to: Instant) {
        anchored = true
        offsetMinutes = ((to.epochSecond - now.epochSecond) / 60.0).roundToInt()
        userMoves++
    }

    /** Look some minutes from now ("+3 hr"); it moves with the clock. */
    fun shift(minutes: Int) {
        anchored = false
        offsetMinutes = minutes
        userMoves++
    }

    fun scrub(to: Int) {
        if (to == offsetMinutes) return
        anchored = false
        offsetMinutes = to
        userMoves++
        if (!hasScrubbed) { hasScrubbed = true; prefs.edit().putBoolean("hasScrubbed", true).apply() }
    }

    fun travel(hours: Int) {
        val anchor = TimeMath.hourAnchor(moment, home)
        val aligned = anchor == moment
        jump(anchor.plusSeconds(((if (hours < 0 && !aligned) hours + 1 else hours) * 3600).toLong()))
    }

    fun backToNow() { offsetMinutes = 0; userMoves++ }

    fun isWorkHour(hour: Int): Boolean = WorkWeek.isWorkHour(hour, workStart, workEnd)

    /** A working day and hour in this city (its own week and hours, or the usual ones there). */
    fun isWorking(place: Place, at: Instant): Boolean = WorkWeek.isWorking(place, at, workStart, workEnd)

    /** Sets a city's own working days and hours; null goes back to the usual ones. */
    fun setWork(place: Place, days: Set<Int>?, start: Int?, end: Int?) =
        update(places.map { if (it.id == place.id) it.copy(workDays = days, workStart = start, workEnd = end) else it })

    val outsideWorkHours: List<Place>
        get() = if (!showWorkHours) emptyList() else places.filter { !isWorking(it, moment) }

    /** Plain text for the selected moment in every city, for a chat or invite. */
    val momentText: String
        get() = places.joinToString("\n") {
            "${it.name}: ${TimeMath.fullMoment(moment, it.zone, use24h)} (${TimeMath.offsetLabel(TimeMath.offsetSeconds(it.zone, moment))})"
        }

    // MARK: Cities

    val canAdd get() = places.size < MAX_PLACES
    fun contains(entry: CityEntry) = places.any { it.name == entry.name && it.zoneId == entry.zoneId }

    fun add(entry: CityEntry) {
        if (!canAdd || contains(entry)) return
        update(places + Place(entry.name, entry.zoneId))
        // A city in your own time zone becomes My Location, rather than showing twice.
        updateMyLocation()
    }

    fun remove(place: Place) {
        // Deleting My Location turns it off, so it doesn't come straight back.
        if (place.isMyLocation) MyLocation.forget(prefs)
        val wasHost = place.id == myLocationHost
        update(places.filter { it.id != place.id })
        // Deleting the card standing in for My Location brings the My Location card back.
        if (place.isMyLocation) updateUseMyLocation(false) else if (wasHost) updateMyLocation()
    }

    /** The card is where you are: the My Location card, or the one standing in for it. */
    fun isHere(place: Place) = place.isMyLocation || place.id == myLocationHost

    /** The city you're in, when location has named it ("Boulder" while your card says Denver). */
    val hereCity: String? get() = MyLocation.city(prefs)

    /** Adds, updates or removes the My Location row (call [locate] to look up the city name). */
    fun updateMyLocation() {
        if (demo) return
        val on = useMyLocation && locationChosen
        val list = if (on) MyLocation.apply(places, prefs) else MyLocation.remove(places, prefs)
        if (list != places) update(list)
        myLocationHost = if (on) MyLocation.hostId(prefs) else null
    }

    /** Looks up the city name (if allowed), then updates the row. */
    fun locate() {
        if (demo || !useMyLocation || !locationChosen) return
        MyLocation.locate(context) { updateMyLocation() }
    }

    /** Asked for location permission at launch already (so it isn't asked every time). */
    val locationAsked get() = prefs.getBoolean("myLocation.asked", false)
    fun markLocationAsked() = prefs.edit().putBoolean("myLocation.asked", true).apply()

    fun move(place: Place, by: Int) {
        val i = places.indexOfFirst { it.id == place.id }
        val j = i + by
        if (i < 0 || j !in places.indices) return
        update(places.toMutableList().also { it.add(j, it.removeAt(i)) })
    }

    fun rename(place: Place, name: String) {
        val trimmed = name.trim().take(40)
        if (trimmed.isEmpty()) return
        update(places.map { if (it.id == place.id) it.copy(name = trimmed) else it })
    }

    private fun update(list: List<Place>) {
        places = list
        if (demo) return
        val array = JSONArray()
        list.forEach { p ->
            val o = JSONObject().put("name", p.name).put("zone", p.zoneId).put("id", p.id)
            p.workDays?.let { o.put("workDays", JSONArray(it.sorted())) }
            p.workStart?.let { o.put("workStart", it) }
            p.workEnd?.let { o.put("workEnd", it) }
            array.put(o)
        }
        prefs.edit().putString("places", array.toString()).apply()
        syncWidgets()
    }

    // MARK: Settings

    fun updateUse24h(on: Boolean) { use24h = on; prefs.edit().putBoolean("use24h", on).apply(); syncWidgets() }
    fun updateShowWorkHours(on: Boolean) { showWorkHours = on; prefs.edit().putBoolean("showWorkHours", on).apply() }
    fun updateWorkStart(hour: Int) { workStart = hour.coerceIn(0, 23); prefs.edit().putInt("workStart", workStart).apply() }
    fun updateWorkEnd(hour: Int) { workEnd = hour.coerceIn(1, 24); prefs.edit().putInt("workEnd", workEnd).apply() }
    fun updateUseMyLocation(on: Boolean) {
        useMyLocation = on
        locationChosen = true
        prefs.edit().putBoolean("useMyLocation", on).putBoolean("myLocation.chosen", true).apply()
        // Turning it back on asks for permission again if it was declined.
        if (on) prefs.edit().putBoolean("myLocation.asked", false).apply()
        updateMyLocation()
    }
    fun acceptTerms() { termsAccepted = true; Terms.accept(prefs) }

    /** Changed terms on GitHub: ask again (at most once a month). */
    fun checkTerms() {
        if (demo) return
        Terms.refresh(prefs) { if (Terms.due(prefs)) termsAccepted = false }
    }

    private fun syncWidgets() = MeridianWidgets.updateAll(context)
}

/**
 * Terms of Use and Privacy, the same rules as the Mac and iPhone apps: the latest version is the
 * "Last updated" date of TERMS.md on GitHub (looked up at most once a day) or the one built in,
 * whichever is newer. The first time, you're always asked; a changed version is asked for at
 * most once a month (30 days after you last agreed).
 */
object Terms {
    const val VERSION = "2026-10-31"
    private const val SOURCE = "https://raw.githubusercontent.com/bradleycowdrey/cowdrey-md/main/TERMS.md"
    private const val MONTH_MS = 30L * 86_400_000
    private const val DAY_MS = 86_400_000L

    fun agreed(prefs: android.content.SharedPreferences): String? = prefs.getString("terms.accepted", null)
    fun latest(prefs: android.content.SharedPreferences): String = maxOf(VERSION, prefs.getString("terms.latest", "") ?: "")

    fun due(prefs: android.content.SharedPreferences, now: Long = System.currentTimeMillis()): Boolean {
        val agreed = agreed(prefs) ?: return true
        if (agreed >= latest(prefs)) return false
        return now - prefs.getLong("terms.acceptedAt", 0L) >= MONTH_MS
    }

    fun accept(prefs: android.content.SharedPreferences) {
        prefs.edit().putString("terms.accepted", latest(prefs)).putLong("terms.acceptedAt", System.currentTimeMillis()).apply()
    }

    /** "Last updated: October 31, 2026" -> "2026-10-31". */
    fun version(markdown: String): String? {
        val match = Regex("Last updated: ([A-Z][a-z]+ \\d{1,2}, \\d{4})").find(markdown) ?: return null
        return runCatching {
            java.time.LocalDate.parse(match.groupValues[1], java.time.format.DateTimeFormatter.ofPattern("MMMM d, yyyy", java.util.Locale.US)).toString()
        }.getOrNull()
    }

    /** Looks up the latest version on GitHub (at most daily), then calls [done] on the main thread. */
    fun refresh(prefs: android.content.SharedPreferences, done: () -> Unit) {
        if (System.currentTimeMillis() - prefs.getLong("terms.checkedAt", 0L) < DAY_MS) { done(); return }
        Thread {
            runCatching {
                val connection = java.net.URL(SOURCE).openConnection() as java.net.HttpURLConnection
                connection.connectTimeout = 10_000; connection.readTimeout = 10_000
                val text = connection.inputStream.bufferedReader().use { it.readText() }
                version(text)?.let { prefs.edit().putString("terms.latest", it).putLong("terms.checkedAt", System.currentTimeMillis()).apply() }
            }
            android.os.Handler(android.os.Looper.getMainLooper()).post(done)
        }.start()
    }

    fun changed(prefs: android.content.SharedPreferences) = agreed(prefs) != null
}
