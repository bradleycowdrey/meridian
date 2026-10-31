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
                    Place(o.getString("name"), o.getString("zone"), o.optString("id").ifEmpty { java.util.UUID.randomUUID().toString() })
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
    var termsAccepted by mutableStateOf(demo || prefs.getString("terms.accepted", null) == Terms.VERSION)
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
        val passed = ((TimeMath.quarter(date).epochSecond - TimeMath.quarter(now).epochSecond) / 60).toInt()
        if (offsetMinutes != 0 && passed != 0) offsetMinutes -= passed
        now = date
    }

    val isNow get() = offsetMinutes == 0
    val moment: Instant get() = if (offsetMinutes == 0) now else TimeMath.quarter(now).plusSeconds(offsetMinutes * 60L)
    val onTheHour get() = moment.atZone(home).minute == 0

    fun jump(to: Instant) {
        offsetMinutes = ((TimeMath.quarter(to).epochSecond - TimeMath.quarter(now).epochSecond) / 60).toInt()
        userMoves++
    }

    fun scrub(to: Int) {
        if (to == offsetMinutes) return
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

    fun isWorkHour(hour: Int): Boolean {
        if (workStart == workEnd || (workStart == 0 && workEnd == 24)) return true
        return if (workStart <= workEnd) hour in workStart until workEnd else hour >= workStart || hour < workEnd
    }

    val outsideWorkHours: List<Place>
        get() = if (!showWorkHours) emptyList() else places.filter { !isWorkHour(moment.atZone(it.zone).hour) }

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
    }

    fun remove(place: Place) {
        // Deleting My Location turns it off, so it doesn't come straight back.
        if (place.isMyLocation) MyLocation.forget(prefs)
        update(places.filter { it.id != place.id })
        if (place.isMyLocation) updateUseMyLocation(false)
    }

    /** Adds, updates or removes the My Location row (call [locate] to look up the city name). */
    fun updateMyLocation() {
        if (demo) return
        val list = if (useMyLocation && locationChosen) MyLocation.apply(places, prefs) else MyLocation.remove(places, prefs)
        if (list != places) update(list)
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
        list.forEach { array.put(JSONObject().put("name", it.name).put("zone", it.zoneId).put("id", it.id)) }
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
    fun acceptTerms() { termsAccepted = true; prefs.edit().putString("terms.accepted", Terms.VERSION).apply() }

    private fun syncWidgets() = MeridianWidgets.updateAll(context)
}

object Terms {
    const val VERSION = "2026-10-31"
}
