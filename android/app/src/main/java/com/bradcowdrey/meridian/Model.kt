package com.bradcowdrey.meridian

import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import java.time.Instant
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.TextStyle
import java.time.temporal.ChronoUnit
import java.util.Locale
import java.util.UUID
import kotlin.math.abs

/** A city the user tracks. */
data class Place(
    val name: String,
    val zoneId: String,
    val id: String = UUID.randomUUID().toString(),
    /** This city's own working days (1 is Sunday) and hours; null uses the usual week there (WorkWeek) and Settings' hours. */
    val workDays: Set<Int>? = null,
    val workStart: Int? = null,
    val workEnd: Int? = null,
    /** The city's country (for its public holidays) and where it is (for its sunrise and sunset), from the city list; null for older cards, which use their time zone's. */
    val countryCode: String? = null,
    val latitude: Double? = null,
    val longitude: Double? = null,
    /** A person this card is for ("Ana", in Lisbon): shown as the card's name, with the city under. */
    val person: String? = null,
    /** Groups this card is in ("Design team"), for Find a Time and the list's filter. */
    val groups: List<String>? = null,
) {
    val zone: ZoneId get() = runCatching { ZoneId.of(zoneId) }.getOrDefault(ZoneId.systemDefault())
    val isMyLocation: Boolean get() = id == MyLocation.ID
    /** What the card is called: the person, or the city. */
    val title: String get() = person ?: name
    /** "Ana (Lisbon)" for a person, else the city: for copied and shared times. */
    val fullName: String get() = person?.let { "$it ($name)" } ?: name
    /** The city's country code: its own, or its time zone's. */
    val country: String? get() = countryCode ?: WorkWeek.countryByZone[zoneId]
}

/** The data files built into the app (Resources/Data, packaged as assets): the city list and public holidays. */
object DataFiles {
    @Volatile private var assets: android.content.res.AssetManager? = null

    fun init(context: android.content.Context) {
        if (assets == null) assets = context.applicationContext.assets
    }

    /** The file's lines, or null before [init] or if it can't be read. */
    fun lines(name: String): List<String>? = assets?.let { a ->
        runCatching { a.open(name).bufferedReader(Charsets.UTF_8).use { it.readLines() } }.getOrNull()
    }

    /** Reads both files in the background, so the first search and the first card don't wait. */
    fun preload() {
        Thread { runCatching { Holidays.load(); CityDirectory.all } }.start()
    }
}

/**
 * National public holidays, offline (Resources/Data/holidays.tsv: five years for every country the
 * python-holidays project covers), as on the iPhone. A city on a holiday isn't working.
 */
object Holidays {
    /** Settings: count public holidays as days off (on unless turned off). Set by the Store. */
    var counted by androidx.compose.runtime.mutableStateOf(true)

    @Volatile private var table: Map<String, Map<Int, String>>? = null

    /** Country code -> yyyymmdd -> name (empty until the file can be read). */
    fun load(): Map<String, Map<Int, String>> {
        table?.let { return it }
        synchronized(this) {
            table?.let { return it }
            val lines = DataFiles.lines("holidays.tsv") ?: return emptyMap()
            val map = HashMap<String, HashMap<Int, String>>()
            for (line in lines) {
                val p = line.split('\t', limit = 3)
                if (p.size != 3) continue
                val day = p[1].toIntOrNull() ?: continue
                val days = map.getOrPut(p[0]) { HashMap() }
                if (day !in days) days[day] = p[2]
            }
            table = map
            return map
        }
    }

    /** The holiday's name on this local day in the city ("Thanksgiving Day"), or null. */
    fun name(place: Place, at: Instant): String? {
        if (!counted) return null
        val cc = place.country ?: return null
        val d = at.atZone(place.zone).toLocalDate()
        return load()[cc]?.get(d.year * 10_000 + d.monthValue * 100 + d.dayOfMonth)
    }
}

/** Time arithmetic and labels, in the same style as the Mac and iPhone apps. */
object TimeMath {
    const val THIN = " "   // thin space before AM/PM

    fun offsetSeconds(zone: ZoneId, at: Instant): Int = zone.rules.getOffset(at).totalSeconds

    /** "UTC+5:30", "UTC−4", "UTC". */
    fun offsetLabel(seconds: Int): String {
        if (seconds == 0) return "UTC"
        val sign = if (seconds > 0) "+" else "−"
        val h = abs(seconds) / 3600
        val m = abs(seconds) % 3600 / 60
        return if (m == 0) "UTC$sign$h" else "UTC$sign$h:%02d".format(m)
    }

    /** ("2:05", "PM") or ("14:05", null). */
    fun clock(at: Instant, zone: ZoneId, use24h: Boolean): Pair<String, String?> {
        val t = at.atZone(zone)
        if (use24h) return "%02d:%02d".format(t.hour, t.minute) to null
        val h = if (t.hour % 12 == 0) 12 else t.hour % 12
        return "$h:%02d".format(t.minute) to (if (t.hour < 12) "AM" else "PM")
    }

    /** "2:05 PM" (thin space) or "14:05". */
    fun time(at: Instant, zone: ZoneId, use24h: Boolean): String {
        val (c, s) = clock(at, zone, use24h)
        return if (s == null) c else "$c$THIN$s"
    }

    /** "9 AM" or "09". */
    fun hourLabel(hour: Int, use24h: Boolean): String =
        if (use24h) "%02d".format(hour) else "${if (hour % 12 == 0) 12 else hour % 12}$THIN${if (hour < 12) "AM" else "PM"}"

    fun weekday(at: Instant, zone: ZoneId): String =
        at.atZone(zone).dayOfWeek.getDisplayName(TextStyle.SHORT, Locale.US)

    /** "Tue 3 Nov". */
    fun fullDay(at: Instant, zone: ZoneId): String {
        val t = at.atZone(zone)
        return "${weekday(at, zone)} ${t.dayOfMonth} ${t.month.getDisplayName(TextStyle.SHORT, Locale.US)}"
    }

    /** "Tue 9 Jun, 9:41 AM". */
    fun fullMoment(at: Instant, zone: ZoneId, use24h: Boolean): String {
        val t = at.atZone(zone)
        val month = t.month.getDisplayName(TextStyle.SHORT, Locale.US)
        return "${weekday(at, zone)} ${t.dayOfMonth} $month, ${time(at, zone, use24h)}"
    }

    /** Calendar-day difference between a zone and home at a moment: -1, 0 or +1. */
    fun dayShift(at: Instant, zone: ZoneId, home: ZoneId): Int =
        (at.atZone(zone).toLocalDate().toEpochDay() - at.atZone(home).toLocalDate().toEpochDay()).toInt()

    /** "+8 hr", "−5:30 hr", or null when it's the same offset as home. */
    fun relative(at: Instant, zone: ZoneId, home: ZoneId): String? {
        val diff = offsetSeconds(zone, at) - offsetSeconds(home, at)
        if (diff == 0) return null
        val h = abs(diff) / 3600
        val m = abs(diff) % 3600 / 60
        return "${if (diff > 0) "+" else "−"}$h${if (m > 0) ":%02d".format(m) else ""} hr"
    }

    fun hourAnchor(at: Instant, home: ZoneId): Instant = at.atZone(home).truncatedTo(ChronoUnit.HOURS).toInstant()

    /** Start of the quarter-hour (every time zone's offset is a whole number of quarter-hours). */
    fun quarter(at: Instant): Instant = Instant.ofEpochSecond(Math.floorDiv(at.epochSecond, 900L) * 900L)
}

/** Sky through the day in bradcowdrey.com tones: warm black at night, warm greys at twilight, cream by day. */
object DayColor {
    private val stops = listOf(
        0.0 to 0x161412, 5.0 to 0x1A1816, 6.5 to 0x4A4540, 8.0 to 0xB0A898, 9.5 to 0xE0D8D0,
        12.0 to 0xFFF1E5, 15.0 to 0xFFF1E5, 17.5 to 0xE0D8D0, 19.0 to 0x807870, 20.5 to 0x34302B,
        22.0 to 0x1C1A17, 24.0 to 0x161412,
    )

    /** ARGB colour of the sky at an hour of the day (0–24). */
    fun at(hour: Double): Int {
        val h = ((hour % 24) + 24) % 24
        for (i in 0 until stops.size - 1) {
            val (h0, c0) = stops[i]
            val (h1, c1) = stops[i + 1]
            if (h >= h0 && h <= h1) {
                val t = if (h1 == h0) 0.0 else (h - h0) / (h1 - h0)
                fun ch(shift: Int) = (((c0 shr shift) and 0xFF) + (((c1 shr shift) and 0xFF) - ((c0 shr shift) and 0xFF)) * t).toInt()
                return (0xFF shl 24) or (ch(16) shl 16) or (ch(8) shl 8) or ch(0)
            }
        }
        return 0xFF000000.toInt() or stops.first().second
    }

    /** Light enough that dark text reads on it. */
    fun isLight(argb: Int): Boolean {
        val r = (argb shr 16) and 0xFF; val g = (argb shr 8) and 0xFF; val b = argb and 0xFF
        return (0.299 * r + 0.587 * g + 0.114 * b) / 255 > 0.55
    }
}

data class CityEntry(
    val name: String,
    val region: String,
    val zoneId: String,
    val aliases: List<String> = emptyList(),
    /** From the world city list (GeoNames): country, where it is, and how many live there (to rank the bigger city first). */
    val countryCode: String? = null,
    val latitude: Double? = null,
    val longitude: Double? = null,
    val population: Int = 0,
) {
    val id: String get() = "$name|$region|$zoneId"
}

/**
 * Searchable list of cities, all on the device (no network): every IANA zone city, popular cities
 * that share a zone, airport codes, abbreviations (PST, CET) and UTC offsets.
 */
object CityDirectory {
    val all: List<CityEntry> by lazy {
        val entries = ZoneId.getAvailableZoneIds().mapNotNull { id ->
            val parts = id.split("/")
            if (parts.size < 2 || parts[0] in setOf("Etc", "SystemV", "US", "Canada", "Brazil", "Chile", "Mexico")) null
            else CityEntry(parts.last().replace("_", " "), parts[0], id)
        }.toMutableList()
        val extras = listOf(
            CityEntry("San Francisco", "United States", "America/Los_Angeles", listOf("SFO", "SF", "Bay Area")),
            CityEntry("Seattle", "United States", "America/Los_Angeles", listOf("SEA")),
            CityEntry("San Diego", "United States", "America/Los_Angeles", listOf("SAN")),
            CityEntry("Las Vegas", "United States", "America/Los_Angeles", listOf("LAS")),
            CityEntry("Portland", "United States", "America/Los_Angeles", listOf("PDX")),
            CityEntry("Salt Lake City", "United States", "America/Denver", listOf("SLC")),
            CityEntry("Austin", "United States", "America/Chicago", listOf("AUS")),
            CityEntry("Dallas", "United States", "America/Chicago", listOf("DFW")),
            CityEntry("Houston", "United States", "America/Chicago", listOf("IAH")),
            CityEntry("Minneapolis", "United States", "America/Chicago", listOf("MSP")),
            CityEntry("Boston", "United States", "America/New_York", listOf("BOS")),
            CityEntry("Washington DC", "United States", "America/New_York", listOf("DC", "IAD", "DCA")),
            CityEntry("Miami", "United States", "America/New_York", listOf("MIA")),
            CityEntry("Atlanta", "United States", "America/New_York", listOf("ATL")),
            CityEntry("Philadelphia", "United States", "America/New_York", listOf("PHL")),
            CityEntry("Mumbai", "India", "Asia/Kolkata", listOf("BOM", "Bombay")),
            CityEntry("Delhi", "India", "Asia/Kolkata", listOf("DEL", "New Delhi")),
            CityEntry("Bengaluru", "India", "Asia/Kolkata", listOf("BLR", "Bangalore")),
            CityEntry("Beijing", "China", "Asia/Shanghai", listOf("PEK")),
            CityEntry("Shenzhen", "China", "Asia/Shanghai", listOf("SZX")),
            CityEntry("Osaka", "Japan", "Asia/Tokyo", listOf("KIX")),
            CityEntry("Tel Aviv", "Israel", "Asia/Jerusalem", listOf("TLV")),
            CityEntry("Abu Dhabi", "United Arab Emirates", "Asia/Dubai", listOf("AUH")),
            CityEntry("Barcelona", "Spain", "Europe/Madrid", listOf("BCN")),
            CityEntry("Munich", "Germany", "Europe/Berlin", listOf("MUC")),
            CityEntry("Frankfurt", "Germany", "Europe/Berlin", listOf("FRA")),
            CityEntry("Milan", "Italy", "Europe/Rome", listOf("MXP")),
            CityEntry("Geneva", "Switzerland", "Europe/Zurich", listOf("GVA")),
            CityEntry("Edinburgh", "United Kingdom", "Europe/London", listOf("EDI")),
            CityEntry("Manchester", "United Kingdom", "Europe/London", listOf("MAN")),
            CityEntry("Cape Town", "South Africa", "Africa/Johannesburg", listOf("CPT")),
            CityEntry("Rio de Janeiro", "Brazil", "America/Sao_Paulo", listOf("GIG", "Rio")),
            CityEntry("Brisbane", "Australia", "Australia/Brisbane", listOf("BNE")),
            CityEntry("Wellington", "New Zealand", "Pacific/Auckland", listOf("WLG")),
            CityEntry("UTC", "Coordinated Universal Time", "UTC", listOf("GMT", "Zulu", "Z")),
        )
        entries += extras
        val airports = mapOf(
            "Los Angeles" to listOf("LAX"), "New York" to listOf("JFK", "NYC", "LGA", "EWR"), "Chicago" to listOf("ORD"),
            "Denver" to listOf("DEN"), "Phoenix" to listOf("PHX"), "Toronto" to listOf("YYZ"), "Vancouver" to listOf("YVR"),
            "Mexico City" to listOf("MEX"), "Sao Paulo" to listOf("GRU", "São Paulo"), "London" to listOf("LHR", "LGW"),
            "Paris" to listOf("CDG"), "Amsterdam" to listOf("AMS"), "Berlin" to listOf("BER"), "Madrid" to listOf("MAD"),
            "Rome" to listOf("FCO"), "Zurich" to listOf("ZRH"), "Dublin" to listOf("DUB"), "Lisbon" to listOf("LIS"),
            "Stockholm" to listOf("ARN"), "Warsaw" to listOf("WAW"), "Istanbul" to listOf("IST"), "Moscow" to listOf("SVO"),
            "Dubai" to listOf("DXB"), "Singapore" to listOf("SIN"), "Hong Kong" to listOf("HKG"), "Tokyo" to listOf("HND", "NRT"),
            "Seoul" to listOf("ICN"), "Shanghai" to listOf("PVG"), "Bangkok" to listOf("BKK"), "Jakarta" to listOf("CGK"),
            "Manila" to listOf("MNL"), "Sydney" to listOf("SYD"), "Melbourne" to listOf("MEL"), "Auckland" to listOf("AKL"),
            "Johannesburg" to listOf("JNB"), "Cairo" to listOf("CAI"), "Lagos" to listOf("LOS"), "Nairobi" to listOf("NBO"),
            "Honolulu" to listOf("HNL"), "Anchorage" to listOf("ANC"), "Kolkata" to listOf("CCU", "Calcutta"),
        )
        val merged = entries.map { it.copy(aliases = it.aliases + (airports[it.name] ?: emptyList())) }.toMutableList()
        // Every city of 15,000 people or more (Resources/Data/cities.tsv), so Boulder and Leeds are
        // there too; a city already listed above gains its country and place.
        val index = HashMap<String, Int>()
        merged.forEachIndexed { i, e -> index["${e.name.lowercase()}|${e.zoneId}"] = i }
        for (city in worldCities()) {
            val key = "${city.name.lowercase()}|${city.zoneId}"
            val i = index[key]
            if (i != null) {
                val e = merged[i]
                if (e.latitude == null) merged[i] = e.copy(region = city.region, countryCode = city.countryCode,
                    latitude = city.latitude, longitude = city.longitude, population = city.population)
            } else {
                index[key] = merged.size
                merged += city
            }
        }
        merged.sortedBy { it.name }
    }

    /** cities.tsv: name, region, country code, zone, latitude, longitude, population (biggest first). */
    private fun worldCities(): List<CityEntry> {
        val lines = DataFiles.lines("cities.tsv") ?: return emptyList()
        val known = ZoneId.getAvailableZoneIds()
        val seen = HashSet<String>()
        return lines.mapNotNull { line ->
            val p = line.split('\t')
            // One of each name in each region and zone (the biggest, as the file is by size).
            if (p.size != 7 || p[3] !in known || !seen.add("${p[0]}|${p[1]}|${p[3]}")) null
            else CityEntry(p[0], p[1], p[3], countryCode = p[2].ifEmpty { null }, latitude = p[4].toDoubleOrNull(),
                longitude = p[5].toDoubleOrNull(), population = p[6].toIntOrNull() ?: 0)
        }
    }

    private val abbreviations = mapOf(
        "PST" to "America/Los_Angeles", "PDT" to "America/Los_Angeles", "MST" to "America/Denver", "MDT" to "America/Denver",
        "CST" to "America/Chicago", "CDT" to "America/Chicago", "EST" to "America/New_York", "EDT" to "America/New_York",
        "AKST" to "America/Anchorage", "HST" to "Pacific/Honolulu", "AST" to "America/Halifax", "BST" to "Europe/London",
        "WET" to "Europe/Lisbon", "CET" to "Europe/Paris", "CEST" to "Europe/Paris", "EET" to "Europe/Athens",
        "MSK" to "Europe/Moscow", "IST" to "Asia/Kolkata", "SGT" to "Asia/Singapore", "HKT" to "Asia/Hong_Kong",
        "JST" to "Asia/Tokyo", "KST" to "Asia/Seoul", "AEST" to "Australia/Sydney", "AEDT" to "Australia/Sydney",
        "NZST" to "Pacific/Auckland", "NZDT" to "Pacific/Auckland",
    )

    fun search(query: String): List<CityEntry> {
        val q = query.trim()
        if (q.isEmpty()) return emptyList()
        val lower = q.lowercase()
        val ranked = all.mapNotNull { e ->
            val name = e.name.lowercase()
            when {
                e.aliases.any { it.lowercase() == lower } -> 0 to e
                name.startsWith(lower) -> 1 to e
                name.contains(lower) || e.aliases.any { it.lowercase().startsWith(lower) } -> 2 to e
                e.region.lowercase().startsWith(lower) -> 3 to e
                else -> null
            }
        }.sortedWith(compareBy({ it.first }, { -it.second.population }, { it.second.name })).map { it.second }.toMutableList()
        // Best match first; then the bigger city (Paris, France before Paris, Texas).
        val offset = offsetZone(q)
        if (offset == null) abbreviations[q.uppercase()]?.let { ranked.add(0, CityEntry(q.uppercase(), it, it)) }
        if (offset != null) {
            ranked.add(0, CityEntry(TimeMath.offsetLabel(offset.totalSeconds), "Fixed offset, no daylight saving", "UTC" + offset.id.replace("Z", "")))
        }
        return ranked.distinctBy { it.id }.take(40)
    }

    /** "UTC+5", "GMT-3", "+9", "UTC+5:30". */
    private fun offsetZone(query: String): ZoneOffset? {
        var text = query.uppercase().replace(" ", "").replace("−", "-")
        for (prefix in listOf("UTC", "GMT")) if (text.startsWith(prefix)) text = text.removePrefix(prefix)
        val sign = text.firstOrNull() ?: return null
        if (sign != '+' && sign != '-') return null
        val parts = text.drop(1).split(":")
        val hours = parts.firstOrNull()?.toIntOrNull() ?: return null
        val minutes = if (parts.size > 1) parts[1].toIntOrNull() ?: -1 else 0
        if (hours > 14 || minutes !in 0..59 || parts.size > 2) return null
        val total = (hours * 3600 + minutes * 60) * (if (sign == '-') -1 else 1)
        return runCatching { ZoneOffset.ofTotalSeconds(total) }.getOrNull()
    }
}
