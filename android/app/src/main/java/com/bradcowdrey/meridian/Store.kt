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
        const val MAX_PLACES = 24
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
                        countryCode = if (o.has("countryCode")) o.getString("countryCode") else null,
                        latitude = if (o.has("latitude")) o.getDouble("latitude") else null,
                        longitude = if (o.has("longitude")) o.getDouble("longitude") else null,
                        person = if (o.has("person")) o.getString("person") else null,
                        groups = o.optJSONArray("groups")?.let { a -> (0 until a.length()).map { a.getString(it) } },
                    )
                }
            }.getOrNull()
        }

        fun use24h(context: Context): Boolean =
            prefs(context).let { if (it.contains("use24h")) it.getBoolean("use24h", false) else android.text.format.DateFormat.is24HourFormat(context) }
    }

    private val prefs = prefs(context)

    init {
        // The city list and holidays come from the app's data files; read them in the background.
        DataFiles.init(context)
        Holidays.counted = prefs.getBoolean("countHolidays", true)
        DataFiles.preload()
    }

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
    /** Count public holidays as days off (Settings). */
    var countHolidays by mutableStateOf(Holidays.counted)
        private set
    /** Group cards by continent automatically ("Europe", "Asia"), as well as their own groups (Settings; on unless turned off). */
    var continentGroups by mutableStateOf(prefs.getBoolean("continentGroups", true))
        private set
    /** The group the list shows ("Design team"); null shows everyone. */
    var groupFilter by mutableStateOf(if (demo) null else prefs.getString("groupFilter", null))
        private set
    /** Clock changes the user has closed the notice for ("Europe/London|1793000000"). */
    var dismissedClockChanges by mutableStateOf<Set<String>>(if (demo) emptySet() else prefs.getStringSet("dismissedClockChanges", null)?.toSet() ?: emptySet())
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
        now = date
        // A picked time stays exactly where it is as the clock moves; a shift ("+2 hr") moves with it.
        pinned?.let { offsetMinutes = minutesTo(it) }
    }

    val isNow get() = pinned == null && offsetMinutes == 0
    /** A picked time exactly (8:15:00 from the ruler, a tapped hour, a date), or now plus a shift. */
    val moment: Instant get() = pinned ?: now.plusSeconds(offsetMinutes * 60L)
    val onTheHour get() = offsetMinutes % 60 == 0 || moment.atZone(home).minute == 0

    /**
     * A picked clock time, kept exactly (not as minutes from now, which would round to the minute
     * and land on 8:14 or 8:16); null for now or a shift from now.
     */
    private var pinned by mutableStateOf<Instant?>(null)

    private fun minutesTo(at: Instant): Int = ((at.toEpochMilli() - now.toEpochMilli()) / 60_000.0).roundToInt()

    /** Pin a picked time (or let go of it at now). */
    private fun pin(at: Instant?) {
        pinned = at
        var next = at?.let { minutesTo(it) } ?: 0
        if (at != null && next == 0) next = if (at > now) 1 else -1   // still "away"
        offsetMinutes = next
    }

    /** Go to a moment, which then stays put. */
    fun jump(to: Instant) {
        pin(to)
        userMoves++
    }

    /** Look some minutes from now ("+2 hr"); it moves with the clock. */
    fun shift(minutes: Int) {
        pinned = null
        offsetMinutes = minutes
        userMoves++
    }

    private fun scrubbed() {
        userMoves++
        if (!hasScrubbed) { hasScrubbed = true; prefs.edit().putBoolean("hasScrubbed", true).apply() }
    }

    /**
     * While dragging a day bar: the quarter-hour on the clock nearest to this many minutes from
     * now (11:00, 11:15, 11:30), exactly, which then stays put as the clock moves.
     */
    fun scrubToQuarterNear(minutes: Double) {
        val target = now.epochSecond + (minutes * 60).toLong()
        val snapped = Instant.ofEpochSecond(Math.round(target / 900.0) * 900)
        val atNow = kotlin.math.abs(minutes) < 7.5
        if (if (atNow) isNow else pinned == snapped) return
        pin(if (atNow) null else snapped)
        scrubbed()
    }

    /** The time ruler settled on a quarter-hour of the clock, exactly; the quarter-hour just begun is now. */
    fun scrubToQuarter(at: Instant) {
        val quarterNow = Math.floorDiv(now.epochSecond, 900L) * 900
        val exact = Instant.ofEpochSecond(Math.floorDiv(at.epochSecond, 900L) * 900)
        val atNow = exact.epochSecond == quarterNow
        if (if (atNow) isNow else pinned == exact) return
        pin(if (atNow) null else exact)
        scrubbed()
    }

    fun scrub(to: Int) {
        if (to == offsetMinutes && pinned == null) return
        pinned = null
        offsetMinutes = to
        scrubbed()
    }

    fun travel(hours: Int) {
        val anchor = TimeMath.hourAnchor(moment, home)
        val aligned = anchor == moment
        jump(anchor.plusSeconds(((if (hours < 0 && !aligned) hours + 1 else hours) * 3600).toLong()))
    }

    fun backToNow() { pinned = null; offsetMinutes = 0; userMoves++ }

    fun isWorkHour(hour: Int): Boolean = WorkWeek.isWorkHour(hour, workStart, workEnd)

    /** A working day and hour in this city (its own week and hours, or the usual ones there). */
    fun isWorking(place: Place, at: Instant): Boolean = WorkWeek.isWorking(place, at, workStart, workEnd)

    /** Sets a city's own working days and hours; null goes back to the usual ones. */
    fun setWork(place: Place, days: Set<Int>?, start: Int?, end: Int?) =
        update(places.map { if (it.id == place.id) it.copy(workDays = days, workStart = start, workEnd = end) else it })

    val outsideWorkHours: List<Place>
        get() = if (!showWorkHours) emptyList() else places.filter { !isWorking(it, moment) }

    /** Plain text for the selected moment in every city, for a chat or invite ("Ana (Lisbon): ..."). */
    val momentText: String
        get() = places.joinToString("\n") {
            "${it.fullName}: ${TimeMath.fullMoment(moment, it.zone, use24h)} (${TimeMath.offsetLabel(TimeMath.offsetSeconds(it.zone, moment))})"
        }

    // MARK: Cities

    val canAdd get() = places.size < MAX_PLACES
    fun contains(entry: CityEntry) = places.any { it.person == null && it.name == entry.name && it.zoneId == entry.zoneId }

    fun add(entry: CityEntry) {
        if (!canAdd || contains(entry)) return
        update(places + Place(entry.name, entry.zoneId, countryCode = entry.countryCode,
            latitude = entry.latitude, longitude = entry.longitude))
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
        // A person's card renames the person; a city's, the city.
        update(places.map { if (it.id != place.id) it else if (it.person != null) it.copy(person = trimmed) else it.copy(name = trimmed) })
    }

    // MARK: People

    /** A card for a person in this card's city ("Ana", in Lisbon), right after it. */
    fun addPerson(name: String, at: Place) {
        val trimmed = name.trim()
        val i = places.indexOfFirst { it.id == at.id }
        if (trimmed.isEmpty() || !canAdd || i < 0) return
        val city = if (at.isMyLocation) hereCity ?: at.name else at.name
        val person = at.copy(id = java.util.UUID.randomUUID().toString(), person = trimmed.take(40), name = city)
        update(places.toMutableList().also { it.add(i + 1, person) })
    }

    // MARK: Groups

    /** The groups the user made ("Design team"), A to Z. */
    val customGroups: List<String>
        get() = places.flatMap { it.groups ?: emptyList() }.distinct().sortedWith(String.CASE_INSENSITIVE_ORDER)

    /** A card's groups: its own, and its continent (when Group by Continent is on). Derived, never saved. */
    fun groupsOf(place: Place): List<String> {
        val own = place.groups ?: emptyList()
        val continent = if (continentGroups) Continent.of(place) else null
        return if (continent == null || continent in own) own else own + continent
    }

    /** Every group on the list: the continents on it (North America first), then the user's own, A to Z. */
    val groups: List<String>
        get() {
            val continents = if (continentGroups) places.mapNotNull { Continent.of(it) }.toSet() else emptySet()
            return Continent.ordered.filter { it in continents } + customGroups.filter { it !in continents }
        }

    /** The cards the list shows: everyone, or one group. */
    val visiblePlaces: List<Place>
        get() {
            val group = groupFilter ?: return places
            if (group !in groups) return places
            return places.filter { group in groupsOf(it) }
        }

    fun setGroups(groups: List<String>, place: Place) {
        val clean = groups.map { it.trim() }.filter { it.isNotEmpty() }.distinct().sorted()
        update(places.map { if (it.id == place.id) it.copy(groups = clean.ifEmpty { null }) else it })
        groupFilter?.let { if (it !in this.groups) updateGroupFilter(null) }
    }

    fun updateGroupFilter(group: String?) {
        groupFilter = group
        if (demo) return
        val edit = prefs.edit()
        if (group == null) edit.remove("groupFilter") else edit.putString("groupFilter", group)
        edit.apply()
    }

    // MARK: Clock changes

    /**
     * Daylight-saving changes in the next two weeks, where any card is or where you are, with how
     * far each city will be from you afterwards; the ones closed with × are left out.
     */
    val clockChanges: List<ClockChange>
        get() {
            val horizon = now.plusSeconds(14 * 86_400L)
            val zones = LinkedHashMap<String, String>()   // zone -> a name for it
            places.forEach { if (it.zoneId !in zones) zones[it.zoneId] = it.name }
            if (home.id !in zones) zones[home.id] = "Your time zone"
            val changes = mutableListOf<ClockChange>()
            for ((id, name) in zones) {
                val zone = runCatching { ZoneId.of(id) }.getOrNull() ?: continue
                val transition = zone.rules.nextTransition(now) ?: continue
                if (!transition.instant.isBefore(horizon)) continue
                val key = "$id|${transition.instant.epochSecond}"
                if (key in dismissedClockChanges) continue
                val before = transition.offsetBefore.totalSeconds
                val after = transition.offsetAfter.totalSeconds
                val mineBefore = home.rules.getOffset(transition.instant.minusSeconds(60)).totalSeconds
                val mineAfter = home.rules.getOffset(transition.instant.plusSeconds(60)).totalSeconds
                changes += ClockChange(key, name, transition, isMine = id == home.id,
                    gapBefore = before - mineBefore, gapAfter = after - mineAfter)
            }
            return changes.sortedBy { it.transition.instant }
        }

    fun dismiss(change: ClockChange) {
        dismissedClockChanges = dismissedClockChanges + change.key
        if (!demo) prefs.edit().putStringSet("dismissedClockChanges", HashSet(dismissedClockChanges)).apply()
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
            p.countryCode?.let { o.put("countryCode", it) }
            p.latitude?.let { o.put("latitude", it) }
            p.longitude?.let { o.put("longitude", it) }
            p.person?.let { o.put("person", it) }
            p.groups?.let { o.put("groups", JSONArray(it)) }
            array.put(o)
        }
        prefs.edit().putString("places", array.toString()).apply()
        syncWidgets()
    }

    // MARK: Settings

    fun updateUse24h(on: Boolean) { use24h = on; prefs.edit().putBoolean("use24h", on).apply(); syncWidgets() }
    fun updateCountHolidays(on: Boolean) { countHolidays = on; Holidays.counted = on; prefs.edit().putBoolean("countHolidays", on).apply() }
    fun updateContinentGroups(on: Boolean) {
        continentGroups = on
        prefs.edit().putBoolean("continentGroups", on).apply()
        groupFilter?.let { if (it !in groups) updateGroupFilter(null) }
    }
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

/** A city's clocks going forward or back soon. */
class ClockChange(
    val key: String,
    val name: String,
    val transition: java.time.zone.ZoneOffsetTransition,
    val isMine: Boolean,
    /** The city's offset from you, in seconds, just before and just after. */
    val gapBefore: Int,
    val gapAfter: Int,
) {
    /** Seconds the clocks move (+3600 forward, −3600 back). */
    val shift: Int get() = transition.offsetAfter.totalSeconds - transition.offsetBefore.totalSeconds

    /** "London's clocks go back 1 hr on Sun 25 Oct at 2:00 AM." */
    fun headline(use24h: Boolean): String {
        // The time on the clock as it changes (before it moves).
        val before = transition.offsetBefore
        val day = transition.instant.atOffset(before).format(java.time.format.DateTimeFormatter.ofPattern("EEE d MMM", java.util.Locale.ENGLISH))
        val at = TimeMath.time(transition.instant, before, use24h)
        val whose = if (isMine) "Your clocks" else "$name\u2019s clocks"
        return "$whose go ${if (shift > 0) "forward" else "back"} ${hours(kotlin.math.abs(shift))} on $day at $at."
    }

    /** "Then 7 hr ahead of you (now 8)." when the gap changes. */
    val detail: String?
        get() {
            if (isMine && gapBefore == gapAfter) return null
            if (gapBefore == gapAfter) return "Still the same time apart from you."
            fun gap(s: Int) = if (s == 0) "the same time as you" else "${hours(kotlin.math.abs(s))} ${if (s > 0) "ahead of" else "behind"} you"
            return "Then ${gap(gapAfter)} (now ${if (gapBefore == 0) "the same" else hours(kotlin.math.abs(gapBefore))})."
        }

    companion object {
        fun hours(seconds: Int): String {
            val h = seconds / 3600
            val m = seconds % 3600 / 60
            return if (m == 0) "$h hr" else if (h == 0) "$m min" else "$h:%02d hr".format(m)
        }
    }
}
