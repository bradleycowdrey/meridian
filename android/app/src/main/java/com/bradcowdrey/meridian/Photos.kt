package com.bradcowdrey.meridian

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.time.Instant
import java.time.ZoneId
import java.util.Locale

/** Who made a picture, under which licence, and where it came from (an AI plate: no licence link, no source). */
data class PhotoCredit(val author: String, val license: String, val licenseUrl: String?, val source: String) {
    companion object {
        /** Every city picture's credit, built in or downloaded: generated with AI for Meridian, no link. */
        val AI = PhotoCredit("Generated with AI for Meridian", "AI-generated image", null, "")
    }
}

/**
 * The skyline photos built into the app: Resources/Data/skylines.json (written by the photo pipeline:
 * key, names and aliases, time zone, file, credit, "focus", from v2 `night`: {file, credit, focus} or null,
 * and from v3 "focusX" beside each "focus", and optionally "top", the landmark's tip, 0..1 down the photo), each a drawable "skyline_<key>" (the day photo) and, where
 * there is one, "skyline_<key>_night". v1 and v2 are a bare array of entries; v3 is an object with
 * "version": 3 and the entries under one array-valued key ([readEntries]). Until the manifest lands (or
 * for a key it leaves out) the four original photos still work. A v1 manifest (no `night`) still reads:
 * a night drawable is found by its name alone. An entry with a "scene" field (scenecoast, scenemountains, ...) is a
 * default scene: never matched by name and never listed in Photo Credits, only picked by [resolve]'s last step.
 */
object SkylineManifest {
    /**
     * [focus] / [nightFocus]: the manifest's "focus" for the day photo and "night"."focus"; [focusX] / [nightFocusX]:
     * its "focusX" (v3: the landmark's place across the photo) for each (null when it has none); [top] / [nightTop]:
     * its "top" (the landmark's tip, 0..1 down the photo) for each (null when it has none: no tip rule). [scene]: the
     * entry's "scene" ("coast"), for a default scene; null for a city's photo.
     */
    data class Entry(val key: String, val names: List<String>, val zone: String?, val credit: PhotoCredit?, val nightCredit: PhotoCredit? = null,
        val focus: Float? = null, val nightFocus: Float? = null, val focusX: Float? = null, val nightFocusX: Float? = null,
        val top: Float? = null, val nightTop: Float? = null, val scene: String? = null)

    /**
     * A built-in photo for a card: its key, its day drawable, and its night one (0 for none), with where each
     * photo's skyline is ([focus] / [nightFocus]: 0..1 down the photo; [PhotoFocus.DEFAULT] when the manifest has none)
     * and its landmark ([focusX] / [nightFocusX]: 0..1 across the photo; [PhotoFocus.DEFAULT_X], the centre, when it has none).
     * [plate] / [nightPlate]: the manifest gave that photo a focusX (an AI plate: its landmark goes to the clear right-hand
     * column of a small widget, not the centre). [top] / [nightTop]: the landmark's tip, 0..1 down the photo (null: no tip rule).
     */
    data class Photo(val key: String, val resId: Int, val nightResId: Int = 0,
        val focus: Float = PhotoFocus.DEFAULT, val nightFocus: Float = PhotoFocus.DEFAULT,
        val focusX: Float = PhotoFocus.DEFAULT_X, val nightFocusX: Float = PhotoFocus.DEFAULT_X,
        val plate: Boolean = false, val nightPlate: Boolean = false,
        val top: Float? = null, val nightTop: Float? = null)

    /**
     * Which picture a card shows ([resolve]): [photo], a built-in one (the city's own, a metro's, or a default scene);
     * [hosted], a hosted plate to download and show in its place (with [photo] its default scene, shown while the plate
     * isn't on the phone, or when Download City Photos is off). Both null: the drawn skyline.
     */
    data class Resolved(val photo: Photo?, val hosted: RemotePlates.Plate? = null)

    private val fallback = listOf(
        Entry("sanfrancisco", listOf("San Francisco"), "America/Los_Angeles", PhotoCredit.AI),
        Entry("newyork", listOf("New York", "New York City", "Manhattan"), "America/New_York", PhotoCredit.AI),
        Entry("london", listOf("London"), "Europe/London", PhotoCredit.AI),
        Entry("tokyo", listOf("Tokyo"), "Asia/Tokyo", PhotoCredit.AI),
    )

    @Volatile private var loaded: List<Entry>? = null
    @Volatile private var index: Map<String, List<Entry>> = emptyMap()
    private val resIds = HashMap<String, Int>()
    /** Anything but a-z, 0-9 and _ in a key, for its drawable's name (made once, not per lookup). */
    private val NON_ALNUM = Regex("[^a-z0-9_]")

    /** Every built-in photo's entry (default scenes too): the manifest's, then any of the original four it leaves out. */
    val entries: List<Entry>
        get() {
            loaded?.let { return it }
            synchronized(this) {
                loaded?.let { return it }
                val fromManifest = parse(DataFiles.text("skylines.json"))
                val keys = fromManifest.map { it.key }.toSet()
                val all = fromManifest + fallback.filter { it.key !in keys }
                val map = HashMap<String, MutableList<Entry>>()
                // A default scene is never matched by name (nor by its key); a photo goes by its key only when it has no names.
                for (e in all) if (e.scene == null) for (n in e.names.ifEmpty { listOf(e.key) }) {
                    val k = norm(n)
                    if (k.isNotEmpty()) map.getOrPut(k) { mutableListOf() }.let { if (e !in it) it.add(e) }
                }
                index = map
                // Read again later if the data files weren't ready yet.
                if (DataFiles.ready) loaded = all
                return all
            }
        }

    /** Entry keys a v3 file's entries are looked for under first (then any other array-valued key, by name). */
    private val ENTRY_KEYS = listOf("entries", "cities", "skylines", "photos")

    /**
     * The entries of a manifest: v1/v2 are a bare array; v3 is an object ("version": 3) with the entries under
     * one array-valued key ([ENTRY_KEYS] first, else the first other key, by name, holding an array of objects).
     */
    private fun readEntries(text: String): JSONArray? {
        val trimmed = text.trimStart()
        if (trimmed.startsWith("[")) return JSONArray(trimmed)
        val o = JSONObject(trimmed)
        val others = o.keys().asSequence().filter { it !in ENTRY_KEYS && it != "version" }.sorted().toList()
        for (k in ENTRY_KEYS + others) {
            val a = o.optJSONArray(k) ?: continue
            if ((0 until a.length()).any { a.optJSONObject(it)?.optString("key")?.isNotBlank() == true }) return a
        }
        return null
    }

    /** A string field, "" when it's missing or JSON null (optString would give "null"). */
    private fun str(o: JSONObject, name: String): String = if (o.isNull(name)) "" else o.optString(name).trim()

    /** A credit object: an AI plate's has no licenseUrl and an empty source, which Photo Credits shows without a link. */
    private fun creditOf(c: JSONObject): PhotoCredit =
        PhotoCredit(str(c, "author"), str(c, "license"), str(c, "licenseUrl").ifBlank { null }, str(c, "source"))

    private fun parse(text: String?): List<Entry> {
        if (text.isNullOrBlank()) return emptyList()
        return runCatching {
            val array = readEntries(text) ?: return@runCatching emptyList<Entry>()
            (0 until array.length()).mapNotNull { i ->
                val o = array.optJSONObject(i) ?: return@mapNotNull null
                val key = o.optString("key").trim()
                if (key.isEmpty()) return@mapNotNull null
                val names = o.optJSONArray("names")?.let { a -> (0 until a.length()).map { a.optString(it) }.filter { it.isNotBlank() } } ?: emptyList()
                val credit = o.optJSONObject("credit")?.let { creditOf(it) }
                // v2: "night": {file, credit, focus} or null (v1 has no "night"); v3 adds "focusX" (and optionally "top") there too.
                val night = o.optJSONObject("night")
                val nightCredit = night?.optJSONObject("credit")?.let { creditOf(it) }
                Entry(key, names, str(o, "zone").ifBlank { null }, credit, nightCredit,
                    focus = PhotoFocus.read(o), nightFocus = night?.let { PhotoFocus.read(it) },
                    focusX = PhotoFocus.readX(o), nightFocusX = night?.let { PhotoFocus.readX(it) },
                    top = PhotoFocus.readTop(o), nightTop = night?.let { PhotoFocus.readTop(it) },
                    scene = str(o, "scene").ifBlank { null })
            }
        }.getOrDefault(emptyList())
    }

    /**
     * A name as built-in photos are matched (step 1): case and accents ignored, spaces at the ends dropped
     * ("Ha Noi" and "Hà Nội", "MÜNCHEN" and "München" alike), as iOS and the Mac fold it: full case folding
     * ([caseFold]), then decomposed and the combining marks taken off (scripts/photo-index.py's fold()).
     */
    fun norm(name: String): String {
        val decomposed = java.text.Normalizer.normalize(caseFold(name), java.text.Normalizer.Form.NFD)
        val out = StringBuilder(decomposed.length)
        var i = 0
        while (i < decomposed.length) {
            val cp = decomposed.codePointAt(i)
            i += Character.charCount(cp)
            if (Character.getType(cp) != Character.NON_SPACING_MARK.toInt()) out.appendCodePoint(cp)
        }
        return out.toString().trim()
    }

    /**
     * Unicode full case folding (Python's str.casefold, Swift's .caseInsensitive folding), which Kotlin lacks: each
     * character upper-cased, then lower-cased ("ß" and "ẞ" -> "ss", "ς" -> "σ", "ﬁ" -> "fi"), except dotless "ı",
     * which folding keeps.
     */
    private fun caseFold(s: String): String {
        val out = StringBuilder(s.length)
        var i = 0
        while (i < s.length) {
            val cp = s.codePointAt(i)
            i += Character.charCount(cp)
            when (cp) {
                0x131 -> out.appendCodePoint(cp)
                0x1E9E -> out.append("ss")
                else -> out.append(String(Character.toChars(cp)).uppercase(Locale.ROOT).lowercase(Locale.ROOT))
            }
        }
        return out.toString()
    }

    /** The drawable for a key ("skyline_<key>", or "skyline_<key>_night" with [night]), or 0 if it isn't in this build. */
    fun resId(context: Context, key: String, night: Boolean = false): Int = testResId?.invoke(key, night) ?: synchronized(resIds) {
        resIds.getOrPut(if (night) "$key|night" else key) {
            val name = "skyline_" + key.lowercase(Locale.ROOT).replace(NON_ALNUM, "_") + if (night) "_night" else ""
            context.resources.getIdentifier(name, "drawable", context.packageName)
        }
    }

    /** Unit tests only: a drawable id for a key (0: not in this build) in place of the resources (the JVM has none). */
    @Volatile internal var testResId: ((key: String, night: Boolean) -> Int)? = null

    /** Two fixed dates (winter and summer) on which zones are compared. */
    private val zoneCheckDates = listOf(Instant.parse("2026-01-15T12:00:00Z"), Instant.parse("2026-07-15T12:00:00Z"))

    /** Whether two zones are the same, or keep the same time all year (an old name for the same zone); a zone this
     *  device doesn't know never fits another (as on iOS and the Mac). */
    fun sameZone(a: String, b: String): Boolean {
        if (a == b) return true
        return runCatching {
            val ra = ZoneId.of(a).rules
            val rb = ZoneId.of(b).rules
            zoneCheckDates.all { ra.getOffset(it) == rb.getOffset(it) }
        }.getOrDefault(false)
    }

    /** The built-in photo for a city matched by its name or alias ([norm]: case and accents ignored) in this zone, if there is one. */
    fun photo(context: Context, city: String, zoneId: String): Photo? {
        if (entries.isEmpty()) return null
        val candidates = index[norm(city)]
        val match = candidates?.let { c ->
            c.firstOrNull { it.zone == null || it.zone == zoneId }
                ?: c.firstOrNull { it.zone != null && sameZone(it.zone, zoneId) }
        } ?: return null
        return photoFor(context, match)
    }

    /** The built-in photo (not a default scene) with this key, or null when there's none in this build. */
    fun photoForKey(context: Context, key: String): Photo? =
        entries.firstOrNull { it.key == key && it.scene == null }?.let { photoFor(context, it) }

    /** The built-in default scene "scene<name>" ("scenecoast"), or null when it isn't in this build. */
    fun scenePhoto(context: Context, scene: String): Photo? =
        entries.firstOrNull { it.key == "scene$scene" && it.scene != null }?.let { photoFor(context, it) }

    /**
     * Which picture a card shows, the same on every platform (scripts/photo-index.py):
     *  1. a built-in photo matched by the city's name ([photo]);
     *  2. plates-remote.json's "towns": a member town of the same name near the card ([lat], [lon]), or, without
     *     coordinates, the only such town in the card's country;
     *  3. its "metros": the nearest metro centre in the card's country that covers the card's coordinates;
     *  (the card's country: [countryCode], else its zone's, WorkWeek.countryByZone; its coordinates: [lat] and [lon]
     *  together, finite and in range, else none at all: a lone latitude counts for nothing)
     *  4. the key from 2 or 3 counts only when it's built in (that photo) or a hosted plate (downloaded; its default
     *     scene comes with it, for until it's on the phone); otherwise the next step;
     *  5. the default scene for the card's zone and latitude.
     * Reads the manifest and the index the first time: call off the main thread.
     */
    fun resolve(context: Context, city: String, zoneId: String, countryCode: String?, lat: Double?, lon: Double?): Resolved {
        photo(context, city, zoneId)?.let { return Resolved(it) }
        val cc = (countryCode?.trim()?.takeIf { it.isNotEmpty() } ?: WorkWeek.countryByZone[zoneId])
            ?.uppercase(Locale.ROOT)?.takeIf { it.isNotEmpty() }
        val hasCoordinates = lat != null && lon != null && lat.isFinite() && lon.isFinite() &&
            Math.abs(lat) <= 90 && Math.abs(lon) <= 180
        val la = if (hasCoordinates) lat else null
        val lo = if (hasCoordinates) lon else null
        val keys = listOfNotNull(RemotePlates.townKey(city, la, lo, cc), RemotePlates.metroKey(la, lo, cc))
        val scene = RemotePlates.scene(zoneId, la)?.let { scenePhoto(context, it) }
        for (key in keys) {
            photoForKey(context, key)?.let { return Resolved(it) }
            RemotePlates.plate(key)?.let { return Resolved(scene, it) }
        }
        return Resolved(scene)
    }

    /** An entry's photo, or null when its drawable isn't in this build. */
    private fun photoFor(context: Context, match: Entry): Photo? {
        val id = resId(context, match.key)
        return if (id != 0) Photo(match.key, id, resId(context, match.key, night = true),
            focus = match.focus ?: PhotoFocus.DEFAULT, nightFocus = match.nightFocus ?: PhotoFocus.DEFAULT,
            focusX = match.focusX ?: PhotoFocus.DEFAULT_X, nightFocusX = match.nightFocusX ?: PhotoFocus.DEFAULT_X,
            plate = match.focusX != null, nightPlate = match.nightFocusX != null,
            top = match.top, nightTop = match.nightTop) else null
    }

    /** The built-in city photos in this build (not the default scenes), with their credits (Photo Credits): each day photo, then its night one. */
    fun credited(context: Context): List<Pair<String, PhotoCredit?>> =
        entries.filter { it.scene == null && resId(context, it.key) != 0 }.flatMap { e ->
            val name = e.names.firstOrNull() ?: e.key
            listOfNotNull(name to e.credit, if (resId(context, e.key, night = true) != 0) "$name at night" to e.nightCredit else null)
        }
}

/**
 * Which photo more cities show (Resources/Data/plates-remote.json, version 2, written by scripts/photo-index.py, whose
 * docstring is the contract): {"version": 2, "base": URL, "plates": [{key, name, cc, zone, focus, focusX, top,
 * night: {focus, focusX, top}}], "metros": [{key, cc, lat, lon, r}], "towns": {key: [name, lat, lon, name, lat, lon, ...]},
 * "scenes": [{scene, zones | prefix | maxAbsLat}]}. A key from towns or metros names a built-in photo (skylines.json) or a
 * hosted plate in "plates", downloaded (CityPhotos, under Download City Photos) from base + key + "-day.jpg" and
 * "-night.jpg" and placed by its focus, focusX and top exactly as a built-in AI plate. See SkylineManifest.resolve.
 */
object RemotePlates {
    /** A hosted plate; the night values are the night entry's, else (missing) the day's. */
    data class Plate(val key: String, val name: String,
        val focus: Float, val focusX: Float?, val top: Float?,
        val nightFocus: Float, val nightFocusX: Float?, val nightTop: Float?)

    /** A metro centre: [r] km around it, in country [cc]. */
    private class Metro(val key: String, val cc: String, val lat: Double, val lon: Double, val r: Double)

    /** A member town of a metro ([key]). */
    private class Town(val key: String, val lat: Double, val lon: Double)

    /** A default scene rule: by zone list, zone prefix or latitude (|lat| at most [maxAbsLat]); none of them: any card. */
    private class SceneRule(val scene: String, val zones: Set<String>?, val prefix: String?, val maxAbsLat: Double?)

    /** How near (km) a town of the same name must be to the card's coordinates. */
    private const val TOWN_KM = 25.0

    private class Index(val base: String?, val plates: Map<String, Plate>, val metros: List<Metro>,
        val ccByKey: Map<String, String>, val towns: Map<String, List<Town>>, val scenes: List<SceneRule>)

    @Volatile private var loaded: Index? = null

    private fun index(): Index {
        loaded?.let { return it }
        synchronized(this) {
            loaded?.let { return it }
            val idx = parse(DataFiles.text("plates-remote.json"))
            // Read again later if the data files weren't ready yet.
            if (DataFiles.ready) loaded = idx
            return idx
        }
    }

    private fun str(o: JSONObject, name: String): String = if (o.isNull(name)) "" else o.optString(name).trim()

    /** A finite number field, or null. */
    private fun num(o: JSONObject, name: String): Double? = o.optDouble(name, Double.NaN).takeIf { it.isFinite() }

    /**
     * A town or city name for matching towns: case, accents and punctuation ignored (SkylineManifest.norm, then
     * letters and digits only, as iOS, the Mac and scripts/photo-index.py's norm: "Saint-Étienne" -> "saintetienne",
     * "Weißensee" -> "weissensee"). "" for a name with nothing left.
     */
    fun fold(name: String): String {
        val n = SkylineManifest.norm(name)
        val out = StringBuilder(n.length)
        var i = 0
        while (i < n.length) {
            val cp = n.codePointAt(i)
            i += Character.charCount(cp)
            val t = Character.getType(cp)
            if (Character.isLetter(cp) || t == Character.DECIMAL_DIGIT_NUMBER.toInt() ||
                t == Character.LETTER_NUMBER.toInt() || t == Character.OTHER_NUMBER.toInt()) out.appendCodePoint(cp)
        }
        return out.toString()
    }

    private fun parse(text: String?): Index {
        val empty = Index(null, emptyMap(), emptyList(), emptyMap(), emptyMap(), emptyList())
        if (text.isNullOrBlank()) return empty
        return runCatching {
            val o = JSONObject(text.trimStart())
            if (o.optInt("version") != 2) return@runCatching empty
            // Only an https base (anything else: no downloads; towns, metros and scenes still work).
            val base = str(o, "base").takeIf { it.startsWith("https://") }?.let { if (it.endsWith("/")) it else "$it/" }
            val plates = HashMap<String, Plate>()
            o.optJSONArray("plates")?.let { list ->
                for (i in 0 until list.length()) {
                    val c = list.optJSONObject(i) ?: continue
                    val key = str(c, "key")
                    // The key goes into a URL and a file name: letters, digits and hyphens only.
                    if (key.isEmpty() || !key.all { it in 'a'..'z' || it in '0'..'9' || it == '-' }) continue
                    val night = c.optJSONObject("night")
                    val focus = PhotoFocus.read(c) ?: PhotoFocus.DEFAULT
                    val focusX = PhotoFocus.readX(c)
                    val top = PhotoFocus.readTop(c)
                    plates[key] = Plate(key, str(c, "name").ifBlank { key }, focus, focusX, top,
                        night?.let { PhotoFocus.read(it) } ?: focus, night?.let { PhotoFocus.readX(it) } ?: focusX,
                        night?.let { PhotoFocus.readTop(it) } ?: top)
                }
            }
            val metros = ArrayList<Metro>()
            o.optJSONArray("metros")?.let { list ->
                for (i in 0 until list.length()) {
                    val m = list.optJSONObject(i) ?: continue
                    val key = str(m, "key")
                    val cc = str(m, "cc").uppercase(Locale.ROOT)
                    val lat = num(m, "lat") ?: continue
                    val lon = num(m, "lon") ?: continue
                    if (key.isEmpty() || cc.isEmpty()) continue
                    metros.add(Metro(key, cc, lat, lon, num(m, "r") ?: 0.0))
                }
            }
            val towns = HashMap<String, MutableList<Town>>()
            o.optJSONObject("towns")?.let { t ->
                for (key in t.keys()) {
                    val a = t.optJSONArray(key) ?: continue
                    var i = 0
                    while (i + 2 < a.length()) {
                        val name = fold(a.optString(i))
                        val lat = a.optDouble(i + 1, Double.NaN)
                        val lon = a.optDouble(i + 2, Double.NaN)
                        if (name.isNotEmpty() && lat.isFinite() && lon.isFinite()) towns.getOrPut(name) { mutableListOf() }.add(Town(key, lat, lon))
                        i += 3
                    }
                }
            }
            val scenes = ArrayList<SceneRule>()
            o.optJSONArray("scenes")?.let { list ->
                for (i in 0 until list.length()) {
                    val s = list.optJSONObject(i) ?: continue
                    val scene = str(s, "scene").takeIf { it.isNotEmpty() } ?: continue
                    val zones = s.optJSONArray("zones")?.let { z -> (0 until z.length()).map { z.optString(it).trim() }.filter { it.isNotEmpty() }.toSet() }
                    scenes.add(SceneRule(scene, zones, str(s, "prefix").ifBlank { null }, num(s, "maxAbsLat")))
                }
            }
            Index(base, plates, metros, metros.associate { it.key to it.cc }, towns, scenes)
        }.getOrDefault(empty)
    }

    /** The great-circle distance in km. */
    private fun km(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
        val p1 = Math.toRadians(lat1)
        val p2 = Math.toRadians(lat2)
        val dp = p2 - p1
        val dl = Math.toRadians(lon2 - lon1)
        val h = Math.sin(dp / 2).let { it * it } + Math.cos(p1) * Math.cos(p2) * Math.sin(dl / 2).let { it * it }
        return 6371.0 * 2 * Math.asin(Math.sqrt(h.coerceIn(0.0, 1.0)))
    }

    /**
     * Step 2, "towns": with coordinates, the key of the nearest member town of the same name ([fold]) within 25 km;
     * without, the key of a town of that name whose metro is in the card's country ([cc]), when it's the only one.
     */
    fun townKey(city: String, lat: Double?, lon: Double?, cc: String?): String? {
        val name = fold(city)
        if (name.isEmpty()) return null
        val idx = index()
        val list = idx.towns[name] ?: return null
        if (lat != null && lon != null) {
            return list.map { it to km(lat, lon, it.lat, it.lon) }.filter { it.second <= TOWN_KM }.minByOrNull { it.second }?.first?.key
        }
        if (cc == null) return null
        val keys = list.filter { idx.ccByKey[it.key] == cc }.map { it.key }.distinct()
        return keys.singleOrNull()
    }

    /** Step 3, "metros": the key of the nearest metro centre in the card's country ([cc]) whose radius covers the card. */
    fun metroKey(lat: Double?, lon: Double?, cc: String?): String? {
        if (lat == null || lon == null || cc == null) return null
        return index().metros.asSequence().filter { it.cc == cc }.map { it to km(lat, lon, it.lat, it.lon) }
            .filter { it.second <= it.first.r }.minByOrNull { it.second }?.first?.key
    }

    /**
     * Step 5, "scenes": the first rule whose zones hold the card's zone, or whose prefix starts it, or (with a latitude)
     * whose maxAbsLat is at least |[lat]|; a rule without a condition takes any card. Its scene's name ("coast"), or null
     * when the index has none.
     */
    fun scene(zoneId: String, lat: Double?): String? = index().scenes.firstOrNull { r ->
        when {
            r.zones != null -> zoneId in r.zones
            r.prefix != null -> zoneId.startsWith(r.prefix)
            r.maxAbsLat != null -> lat != null && r.maxAbsLat >= Math.abs(lat)
            else -> true
        }
    }?.scene

    /** A hosted plate by its key, or null when this build's index doesn't list it. */
    fun plate(key: String): Plate? = index().plates[key]

    /** The day image's URL, or null without a usable base. */
    fun dayUrl(p: Plate): String? = index().base?.let { it + p.key + "-day.jpg" }

    /** The night image's URL, or null without a usable base. */
    fun nightUrl(p: Plate): String? = index().base?.let { it + p.key + "-night.jpg" }
}

/**
 * Where a photo sits in a card or a widget (the v3 plates are 3:1, the old photos about 2:1): scaled just enough to
 * cover (aspect-fill), then moved across so the photo's landmark (its "focusX", [landmark], a fraction of its width;
 * [DEFAULT_X], the centre, without one) lands on the frame's target x (a row's clear gap between its words and its
 * hour tiles; the middle of a small single-city widget), clamped so the photo still covers (no empty edge). Only when
 * that clamp keeps the landmark off the target is it zoomed, at most [MAX_ZOOM] times the cover scale, just enough
 * to reach it. Down: moved so the point [focus] of the way down the photo (the skyline, from the manifest; [DEFAULT]
 * without one) is at the middle of the height; then, when the manifest gives the landmark's tip ("top", 0..1 down the
 * photo), moved down as far as needed for the tip to sit at least [TIP_MARGIN] of the height below the frame's top edge;
 * then clamped so it still covers (scripts/plate-fit.py geometry()).
 */
object PhotoFocus {
    /** Where the skyline is when the manifest doesn't say (downloaded photos, old manifests). */
    const val DEFAULT = 0.62f
    /** Where the landmark is when the manifest doesn't say (downloaded photos, v1/v2 manifests): the centre. */
    const val DEFAULT_X = 0.5f
    /** Where across a small single-city widget an AI plate's landmark goes: the clear right-hand column. */
    const val SQUARE_TARGET_X = 0.78f
    /** The least room (a fraction of the frame's height) between the frame's top edge and the landmark's tip. */
    const val TIP_MARGIN = 0.08f
    private const val MAX_ZOOM = 1.15f
    /** How far past cover a phone card may zoom to make its landmark fill the card. */
    private const val MAX_FILL_ZOOM = 1.6f
    /** How much of a card's height an AI plate's landmark (tip to skyline) fills. */
    const val CARD_FILL = 0.55f

    /** An object's "focus" (0..1), or null when it has none. */
    fun read(o: JSONObject): Float? = number(o, "focus")

    /** An object's "focusX" (0..1, v3), or null when it has none. */
    fun readX(o: JSONObject): Float? = number(o, "focusX")

    /** An object's "top" (0..1, the landmark's tip down the photo), or null when it has none. */
    fun readTop(o: JSONObject): Float? = number(o, "top")

    /** A number field (0..1), or null when it's missing, JSON null or not a number. */
    fun number(o: JSONObject, name: String): Float? {
        val v = o.optDouble(name, Double.NaN)
        return if (v.isNaN()) null else v.toFloat().coerceIn(0f, 1f)
    }

    /** [a] clamped between 0 and [b] (whichever way round: [b] is the room left, negative when it overflows). */
    private fun clampTo(a: Float, b: Float): Float = a.coerceIn(minOf(0f, b), maxOf(0f, b))

    /**
     * The photo ([iw] by [ih]) drawn in a [w] by [h] box: its scale and its top-left offset in the box
     * (floatArrayOf(scale, offX, offY)). [targetX]: where across the box (px) the landmark goes; null for the
     * box's middle. [landmark]: the landmark's place across the photo (0..1). [tip]: the landmark's tip, 0..1 down the
     * photo (the manifest's "top"; null for no tip rule).
     */
    fun place(iw: Float, ih: Float, w: Float, h: Float, focus: Float, targetX: Float? = null, landmark: Float = DEFAULT_X,
        tip: Float? = null, fill: Float? = null): FloatArray {
        if (iw <= 0f || ih <= 0f) return floatArrayOf(1f, 0f, 0f)
        val cover = maxOf(w / iw, h / ih)
        val t = (targetX ?: (w / 2f)).coerceIn(0f, w)
        val l = landmark.coerceIn(0f, 1f)
        // The drawn width at which the landmark can sit at t with the photo still covering: wide enough on the left
        // (t <= l * dw) and on the right (w - t <= (1 - l) * dw). A landmark at the photo's very edge can't move inward
        // by zooming, so that side asks nothing. Never past MAX_ZOOM times the cover scale.
        val needLeft = if (l > 0.001f) t / l else 0f
        val needRight = if (l < 0.999f) (w - t) / (1f - l) else 0f
        var s = (maxOf(needLeft, needRight) / iw).coerceIn(cover, cover * MAX_ZOOM)
        // Phone cards ([fill], a fraction of the box's height): zoom in until the landmark, from its tip down to the
        // skyline band, spans that much of the card, up to MAX_FILL_ZOOM times cover (a plate is as wide as a card,
        // so otherwise its open sky fills the card and the city sits small behind the tiles).
        if (fill != null && tip != null && focus > tip) {
            val wanted = h * fill / ((focus.coerceIn(0f, 1f) - tip.coerceIn(0f, 1f)) * ih)
            s = maxOf(s, minOf(wanted, cover * MAX_FILL_ZOOM))
        }
        val dw = iw * s
        val dh = ih * s
        return floatArrayOf(s, left(dw, w, t, l), top(dh, h, focus, tip))
    }

    /** The left of a photo drawn [dw] wide in a box [w] wide: its point [landmark] of the way across at [targetX], still covering. */
    fun left(dw: Float, w: Float, targetX: Float, landmark: Float): Float =
        clampTo(targetX - landmark.coerceIn(0f, 1f) * dw, w - dw)

    /**
     * The top of a photo drawn [dh] high in a box [h] high: its point [focus] of the way down at the middle; then, with a
     * [tip] (0..1 down the photo), no higher than keeps the tip [TIP_MARGIN] of [h] below the top edge; still covering.
     */
    fun top(dh: Float, h: Float, focus: Float, tip: Float? = null): Float {
        var y = h / 2f - focus.coerceIn(0f, 1f) * dh
        if (tip != null) y = maxOf(y, TIP_MARGIN * h - tip.coerceIn(0f, 1f) * dh)
        return clampTo(y, h - dh)
    }
}

/**
 * Hosted AI plates (RemotePlates), for cities whose photo isn't built in: a plate's day and night images, fetched once in
 * the background (only under Download City Photos) and kept on the phone in filesDir/city-plates as <key>-day.jpg and
 * <key>-night.jpg, with <key>.json (written last: the plate is complete). Only the images' URLs are requested: no
 * cookies, no app headers, no HTTP cache. A plate that isn't there yet is asked for again at most once in 30 days.
 * Until a plate is on the phone (or with the setting off), the card shows its default scene.
 */
object CityPhotos {
    private const val RETRY_MS = 30L * 24 * 3600 * 1000
    private const val MAX_BYTES = 8 * 1024 * 1024
    private const val DIR = "city-plates"
    /** Where earlier versions kept downloaded photos (Wikimedia photos and plates by city): cleared once ([cleanUp]). */
    private const val OLD_DIR = "city-photos"
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    /** One download at a time, gently. */
    private val mutex = Mutex()
    /** Asked for this run (so a card redrawn many times asks once). */
    private val asked = HashSet<String>()
    /** Decoded plates by key (the night one by "<key>-night"): state, so a card redraws when its photo arrives. */
    private val bitmaps = mutableStateMapOf<String, ImageBitmap>()
    /** Plates that were taken to be on the phone but couldn't be read this run (state: their cards show the default scene). */
    private val unreadable = mutableStateMapOf<String, Boolean>()
    /**
     * Screenshot mode (set by the app at launch): nothing is read, fetched or exported for the widgets, so the
     * first frame never waits on disk or network and the widgets aren't redrawn with demo cities.
     */
    @Volatile var demo = false
    /** Bumped when a plate is saved, so Photo Credits reads the list again. */
    var saved by mutableIntStateOf(0)
        private set

    data class Downloaded(val city: String, val credit: PhotoCredit)

    private const val NIGHT = "-night"

    /** The day plate for this key, once it's on the phone and read (a state read: callers redraw when it arrives). */
    fun bitmap(key: String): ImageBitmap? = bitmaps[key]

    /** The night plate for this key, once it's on the phone and read (a state read), or null (yet). */
    fun nightBitmap(key: String): ImageBitmap? = bitmaps[key + NIGHT]

    /** Whether this plate couldn't be read from the phone this run (a state read): its card shows the default scene. */
    fun failed(key: String): Boolean = unreadable[key] == true

    /** A plate on the phone that can't be read: its card falls back to the scene, and the next launch downloads it again. */
    private fun markUnreadable(context: Context, key: String) {
        unreadable[key] = true
        runCatching { File(dir(context), "$key.json").delete() }
    }

    private fun dir(context: Context): File = File(context.filesDir, DIR).apply { mkdirs() }

    /** The downloaded day plate for this key, if it's on the phone (for the widgets' copies). */
    fun file(context: Context, key: String): File? = File(dir(context), "$key-day.jpg").takeIf { it.exists() }

    /** The downloaded night plate for this key, if it's on the phone (for the widgets' copies). */
    fun nightFile(context: Context, key: String): File? = File(dir(context), "$key$NIGHT.jpg").takeIf { it.exists() }

    /** Whether this plate is on the phone, day and night, and complete. Reads files: call off the main thread. */
    fun onDisk(context: Context, key: String): Boolean =
        file(context, key) != null && nightFile(context, key) != null &&
            runCatching { JSONObject(File(dir(context), "$key.json").readText()).optBoolean("ok") }.getOrDefault(false)

    /**
     * Removes what earlier versions downloaded (Wikimedia photos, their night photos and records), once: the old folder
     * goes. A hosted plate saved there (its record names the plate) is kept: moved here first. Call at launch.
     */
    fun cleanUp(context: Context) {
        if (demo) return
        val app = context.applicationContext
        scope.launch {
            mutex.withLock {
                val old = File(app.filesDir, OLD_DIR)
                if (!old.exists()) return@withLock
                runCatching {
                    old.listFiles { f -> f.name.endsWith(".json") && !f.name.endsWith("$NIGHT.json") }?.forEach { meta ->
                        val o = runCatching { JSONObject(meta.readText()) }.getOrNull() ?: return@forEach
                        val key = o.optString("plate").trim()
                        if (!o.optBoolean("ok") || key.isEmpty() || !key.all { it in 'a'..'z' || it in '0'..'9' || it == '-' }) return@forEach
                        if (onDisk(app, key)) return@forEach
                        val slug = meta.name.removeSuffix(".json")
                        val day = File(old, "$slug.jpg")
                        val night = File(old, "$slug$NIGHT.jpg")
                        if (!day.exists() || !night.exists()) return@forEach
                        val folder = dir(app)
                        if (night.renameTo(File(folder, "$key$NIGHT.jpg")) && day.renameTo(File(folder, "$key-day.jpg"))) {
                            File(folder, "$key.json").writeText(record(key, RemotePlates.plate(key)?.name ?: o.optString("city")).toString())
                        }
                    }
                }
                old.deleteRecursively()
                saved++
                // The widgets' copies of the old photos go on their next export.
                MeridianWidgets.updateAll(app)
            }
        }
    }

    /**
     * Shows a hosted plate if it's on the phone; otherwise fetches it in the background (unless a try in the last 30
     * days found it missing). Call only with Download City Photos on. Never blocks; safe offline. The night plate is
     * read only when [night] (it's night there), so a card never decodes both.
     */
    fun request(context: Context, plate: RemotePlates.Plate, night: Boolean = false) {
        if (demo) return
        val key = plate.key
        if (bitmaps.containsKey(key) && (!night || bitmaps.containsKey(key + NIGHT))) return
        synchronized(asked) { if (!asked.add("$key|$night")) return }
        val app = context.applicationContext
        scope.launch {
            try {
                if (!onDisk(app, key)) mutex.withLock {
                    // (Another card, or the clean-up, may have put it in place meanwhile.)
                    if (!onDisk(app, key) && plateDue(app, key)) fetchPlate(app, plate)
                }
                if (!onDisk(app, key)) {
                    // (Not there, or gone since the card looked: the default scene.)
                    if (!bitmaps.containsKey(key)) unreadable[key] = true
                    return@launch
                }
                if (!bitmaps.containsKey(key)) {
                    val day = file(app, key)?.let { decode(it) }
                    if (day == null) { markUnreadable(app, key); return@launch }
                    bitmaps[key] = day
                }
                if (night && !bitmaps.containsKey(key + NIGHT)) {
                    // A night plate that can't be read: the day plate stays; the next launch downloads both again.
                    val nightPlate = nightFile(app, key)?.let { decode(it) }
                    if (nightPlate == null) {
                        runCatching { File(dir(app), "$key.json").delete() }
                    } else {
                        bitmaps[key + NIGHT] = nightPlate
                    }
                }
            } catch (e: IOException) {
                // Offline or a server hiccup: not marked as tried on disk, so the next launch tries again (asked keeps it out until then).
                if (!bitmaps.containsKey(key)) unreadable[key] = true
            } catch (e: Exception) {
                // Anything unexpected: the default scene.
                if (!bitmaps.containsKey(key)) unreadable[key] = true
            }
        }
    }

    private fun decode(file: File): ImageBitmap? = runCatching {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, bounds)
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= 1000) sample *= 2
        BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply { inSampleSize = sample })?.asImageBitmap()
    }.getOrNull()

    /** The marker of a hosted plate that wasn't there (<key>.tried: when), so it's asked again only after 30 days. */
    private fun plateTried(context: Context, key: String): File = File(dir(context), "$key.tried")

    /** Whether this plate may be asked for: never found missing, or not in the last 30 days. */
    private fun plateDue(context: Context, key: String): Boolean {
        val at = runCatching { plateTried(context, key).readText().trim().toLong() }.getOrNull() ?: return true
        return System.currentTimeMillis() - at >= RETRY_MS
    }

    /** Whether these bytes decode as an image. */
    private fun decodable(bytes: ByteArray): Boolean {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        return bounds.outWidth > 0 && bounds.outHeight > 0
    }

    /** Writes [bytes] as [name] (through a .part file). False if the file can't be put in place. */
    private fun save(context: Context, name: String, bytes: ByteArray): Boolean {
        val folder = dir(context)
        val tmp = File(folder, "$name.part")
        tmp.writeBytes(bytes)
        if (!tmp.renameTo(File(folder, name))) { tmp.delete(); return false }
        return true
    }

    /** A plate's record (<key>.json): complete, its name and when it was fetched. */
    private fun record(key: String, name: String): JSONObject =
        JSONObject().put("ok", true).put("plate", key).put("name", name).put("fetchedAt", System.currentTimeMillis())

    /**
     * Downloads a hosted plate, day and night, and saves both. Only the image URLs are requested. When an image isn't
     * there (or isn't an image) the plate is asked for again only after 30 days; a network error throws (not marked).
     */
    private fun fetchPlate(context: Context, plate: RemotePlates.Plate) {
        val dayUrl = RemotePlates.dayUrl(plate) ?: return
        val nightUrl = RemotePlates.nightUrl(plate) ?: return
        // Day, then night (only with a day).
        val day = getBytes(dayUrl)?.takeIf { decodable(it) }
        val night = if (day == null) null else getBytes(nightUrl)?.takeIf { decodable(it) }
        if (day == null || night == null) {
            runCatching { plateTried(context, plate.key).writeText(System.currentTimeMillis().toString()) }
            return
        }
        if (!save(context, plate.key + NIGHT + ".jpg", night)) return
        if (!save(context, plate.key + "-day.jpg", day)) return
        // The record last: it marks the plate as complete.
        File(dir(context), "${plate.key}.json").writeText(record(plate.key, plate.name).toString())
        plateTried(context, plate.key).delete()
        saved++
        // The widgets show it too: their copies are made, then they redraw.
        if (!demo) MeridianWidgets.updateAll(context)
    }

    /**
     * A GET with nothing but the URL: no cookies (none are set up in this app), no app headers (the User-Agent is a
     * fixed "Meridian", nothing about the phone), no HTTP cache;
     * redirects followed (same protocol only).
     */
    private fun open(url: String): HttpURLConnection {
        val c = URL(url).openConnection() as HttpURLConnection
        c.connectTimeout = 10_000
        c.readTimeout = 15_000
        c.instanceFollowRedirects = true
        c.useCaches = false
        // A fixed agent in place of the system's (which names the phone's model and build): no header is added.
        c.setRequestProperty("User-Agent", "Meridian")
        return c
    }

    /** The response's bytes; null for one that isn't there (or too big); throws on a network or server error. */
    private fun getBytes(url: String): ByteArray? {
        val c = open(url)
        try {
            val code = c.responseCode
            if (code == 429 || code >= 500) throw IOException("HTTP $code")
            if (code !in 200..299) return null
            val out = java.io.ByteArrayOutputStream()
            c.inputStream.use { input ->
                val buffer = ByteArray(16 * 1024)
                while (true) {
                    val n = input.read(buffer)
                    if (n < 0) break
                    out.write(buffer, 0, n)
                    if (out.size() > MAX_BYTES) return null
                }
            }
            return out.toByteArray()
        } finally {
            c.disconnect()
        }
    }

    /** The plates downloaded so far, day and night, with their credit (Photo Credits). Reads files: call off the main thread. */
    fun downloaded(context: Context): List<Downloaded> {
        val files = dir(context).listFiles { f -> f.name.endsWith(".json") } ?: return emptyList()
        return files.mapNotNull { f ->
            runCatching {
                val key = f.name.removeSuffix(".json")
                if (!onDisk(context, key)) return@runCatching null
                val name = JSONObject(f.readText()).optString("name").trim().ifEmpty { RemotePlates.plate(key)?.name ?: key }
                name
            }.getOrNull()
        }.sortedBy { it.lowercase(Locale.ROOT) }.flatMap { listOf(Downloaded(it, PhotoCredit.AI), Downloaded("$it at night", PhotoCredit.AI)) }
    }
}

/**
 * The home screen widgets' photos: small copies (about 480 px wide, JPEG quality 60) of each listed
 * city's photo, built in or a downloaded hosted plate, in filesDir/widget-skylines/<key>.jpg, and of its night photo
 * where it has one, <key>-night.jpg, with which city uses which (map.json: card id -> key, crop and
 * where each photo's skyline is, and whether there's a night copy). Made by the app whenever the list changes or a downloaded
 * photo arrives (MeridianWidgets.updateAll does this before it redraws), so a widget only ever decodes
 * a small file and never touches the network.
 */
object WidgetPhotos {
    private const val DIR = "widget-skylines"
    private const val MAP = "map.json"
    private const val MAX_WIDTH = 480
    private const val QUALITY = 60

    /**
     * A card's photo: [key] names the copy; [resId] (built in) or [plateKey] (a downloaded hosted plate) is where it came from.
     * [night]: the city has a night photo too (copied as <key>-night.jpg; built in from [nightResId]).
     * [plate] / [nightPlate]: the manifest gave that photo a focusX (the small widget's landmark goes to
     * PhotoFocus.SQUARE_TARGET_X); [top] / [nightTop]: its landmark's tip, 0..1 down the photo (null: no tip rule).
     */
    data class Ref(val key: String, val focus: Float, val resId: Int = 0, val plateKey: String? = null,
        val nightResId: Int = 0, val night: Boolean = false, val nightFocus: Float = PhotoFocus.DEFAULT,
        val focusX: Float = PhotoFocus.DEFAULT_X, val nightFocusX: Float = PhotoFocus.DEFAULT_X,
        val plate: Boolean = false, val nightPlate: Boolean = false,
        val top: Float? = null, val nightTop: Float? = null)

    fun dir(context: Context): File = File(context.filesDir, DIR).apply { mkdirs() }

    /** The city a card's photo is for: a person's city, or the city you're in for My Location. */
    fun city(context: Context, place: Place): String =
        if (place.isMyLocation) MyLocation.city(Store.prefs(context)) ?: place.name else place.name

    /**
     * The photo for a card, as the app's card shows it (SkylineManifest.resolve): a built-in photo (the city's own, a
     * metro's, or its default scene), or a hosted plate once it's on the phone (and Download City Photos is on), placed
     * by its index entry exactly as a built-in AI plate (its night photo by the night entry). Null for none (a drawn sky).
     */
    fun ref(context: Context, place: Place): Ref? {
        val city = city(context, place)
        val resolved = SkylineManifest.resolve(context, city, place.zoneId, place.country, place.latitude, place.longitude)
        val download = Store.prefs(context).getBoolean("downloadCityPhotos", true)
        resolved.hosted?.takeIf { download && CityPhotos.onDisk(context, it.key) }?.let {
            return Ref("pl-${it.key}", it.focus, plateKey = it.key, night = true, nightFocus = it.nightFocus,
                focusX = it.focusX ?: PhotoFocus.DEFAULT_X, nightFocusX = it.nightFocusX ?: PhotoFocus.DEFAULT_X,
                plate = it.focusX != null, nightPlate = it.nightFocusX != null, top = it.top, nightTop = it.nightTop)
        }
        return resolved.photo?.let {
            Ref(it.key, it.focus, resId = it.resId, nightResId = it.nightResId, night = it.nightResId != 0, nightFocus = it.nightFocus,
                focusX = it.focusX, nightFocusX = it.nightFocusX, plate = it.plate, nightPlate = it.nightPlate,
                top = it.top, nightTop = it.nightTop)
        }
    }

    /** Each card's photo, by card id, without writing anything (the app's widget previews). */
    fun refs(context: Context, places: List<Place>): Map<String, Ref> =
        places.mapNotNull { p -> ref(context, p)?.let { p.id to it } }.toMap()

    /**
     * Makes the small copies for these cards (only those missing, or older than a newer download or app update), writes
     * map.json, and removes copies no card uses. Returns each card's photo. Reads and writes files: call
     * off the main thread.
     */
    @Synchronized
    fun export(context: Context, places: List<Place>): Map<String, Ref> {
        val folder = dir(context)
        val refs = refs(context, places)
        val installed = runCatching { context.packageManager.getPackageInfo(context.packageName, 0).lastUpdateTime }.getOrDefault(0L)
        /** Writes <name>.jpg from a drawable or a downloaded file, unless the copy is already as new. */
        fun copy(name: String, resId: Int, source: File?) {
            val out = File(folder, "$name.jpg")
            val newer = source?.lastModified() ?: if (resId != 0) installed else 0L
            if (out.exists() && newer <= out.lastModified()) return
            runCatching {
                val bitmap = when {
                    resId != 0 -> decodeResource(context, resId, MAX_WIDTH)
                    source != null -> decodeFile(source, MAX_WIDTH)
                    else -> null
                } ?: return@runCatching
                val scaled = if (bitmap.width > MAX_WIDTH) {
                    Bitmap.createScaledBitmap(bitmap, MAX_WIDTH, (bitmap.height * MAX_WIDTH / bitmap.width).coerceAtLeast(1), true)
                } else bitmap
                val tmp = File(folder, "$name.jpg.part")
                tmp.outputStream().use { scaled.compress(Bitmap.CompressFormat.JPEG, QUALITY, it) }
                if (!tmp.renameTo(out)) tmp.delete()
                if (scaled !== bitmap) scaled.recycle()
                bitmap.recycle()
            }
        }
        for (ref in refs.values.distinctBy { it.key }) {
            // The day photo (<key>.jpg), then the night one where there is one (<key>-night.jpg).
            copy(ref.key, ref.resId, ref.plateKey?.let { CityPhotos.file(context, it) })
            if (ref.night) copy(ref.key + "-night", ref.nightResId, ref.plateKey?.let { CityPhotos.nightFile(context, it) })
        }
        runCatching {
            val map = JSONObject()
            refs.forEach { (id, r) ->
                val e = JSONObject().put("key", r.key).put("focus", r.focus.toDouble())
                    .put("nightFocus", r.nightFocus.toDouble()).put("night", r.night)
                    .put("focusX", r.focusX.toDouble()).put("nightFocusX", r.nightFocusX.toDouble())
                    .put("plate", r.plate).put("nightPlate", r.nightPlate)
                // The tips only where the manifest has them (missing: no tip rule).
                r.top?.let { e.put("top", it.toDouble()) }
                r.nightTop?.let { e.put("nightTop", it.toDouble()) }
                map.put(id, e)
            }
            val tmp = File(folder, "$MAP.part")
            tmp.writeText(map.toString())
            if (!tmp.renameTo(File(folder, MAP))) tmp.delete()
        }
        val used = refs.values.flatMap { listOfNotNull(it.key + ".jpg", if (it.night) it.key + "-night.jpg" else null) }.toSet()
        folder.listFiles { f -> f.name.endsWith(".jpg") && f.name !in used }?.forEach { it.delete() }
        return refs
    }

    /** The cards' photos as the app last wrote them (map.json), by card id. */
    fun saved(context: Context): Map<String, Ref> = runCatching {
        val o = JSONObject(File(dir(context), MAP).readText())
        o.keys().asSequence().mapNotNull { id ->
            val e = o.optJSONObject(id) ?: return@mapNotNull null
            val key = e.optString("key").ifBlank { return@mapNotNull null }
            id to Ref(key, PhotoFocus.read(e) ?: PhotoFocus.DEFAULT, night = e.optBoolean("night"),
                nightFocus = e.optDouble("nightFocus", PhotoFocus.DEFAULT.toDouble()).toFloat(),
                // A map.json from before v3 has no focusX: the centre, as before.
                focusX = PhotoFocus.readX(e) ?: PhotoFocus.DEFAULT_X,
                nightFocusX = e.optDouble("nightFocusX", PhotoFocus.DEFAULT_X.toDouble()).toFloat().coerceIn(0f, 1f),
                // Older map.json files have neither: no plate target and no tip rule, as before.
                plate = e.optBoolean("plate"), nightPlate = e.optBoolean("nightPlate"),
                top = PhotoFocus.readTop(e), nightTop = PhotoFocus.number(e, "nightTop"))
        }.toMap()
    }.getOrDefault(emptyMap())

    /**
     * A card's photo for a widget, at most [maxWidth] px wide: its small copy, else (before the copy is
     * made, or in the app's previews) the original, downsampled. Null for none.
     */
    fun load(context: Context, ref: Ref, maxWidth: Int = 600): Bitmap? = runCatching {
        val copy = File(dir(context), ref.key + ".jpg")
        if (copy.exists()) decodeFile(copy, maxWidth)?.let { return@runCatching it }
        if (ref.resId != 0) decodeResource(context, ref.resId, maxWidth)?.let { return@runCatching it }
        ref.plateKey?.let { CityPhotos.file(context, it) }?.let { decodeFile(it, maxWidth) }
    }.getOrNull()

    /**
     * A card's night photo for a widget, at most [maxWidth] px wide: its small copy (<key>-night.jpg), else
     * the original night photo, downsampled. Null when the city has none: the widget then shades the day photo.
     */
    fun loadNight(context: Context, ref: Ref, maxWidth: Int = 600): Bitmap? = runCatching {
        val copy = File(dir(context), ref.key + "-night.jpg")
        if (copy.exists()) decodeFile(copy, maxWidth)?.let { return@runCatching it }
        if (ref.nightResId != 0) decodeResource(context, ref.nightResId, maxWidth)?.let { return@runCatching it }
        ref.plateKey?.let { CityPhotos.nightFile(context, it) }?.let { decodeFile(it, maxWidth) }
    }.getOrNull()

    /** The power-of-two sample size that keeps the decoded width at or above [maxWidth] but near it. */
    private fun sample(width: Int, maxWidth: Int): Int {
        var s = 1
        while (width / (s * 2) >= maxWidth) s *= 2
        return s
    }

    private fun decodeFile(file: File, maxWidth: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(file.path, bounds)
        if (bounds.outWidth <= 0) return null
        return BitmapFactory.decodeFile(file.path, BitmapFactory.Options().apply { inSampleSize = sample(bounds.outWidth, maxWidth) })
    }

    private fun decodeResource(context: Context, resId: Int, maxWidth: Int): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeResource(context.resources, resId, bounds)
        if (bounds.outWidth <= 0) return null
        return BitmapFactory.decodeResource(context.resources, resId, BitmapFactory.Options().apply { inSampleSize = sample(bounds.outWidth, maxWidth) })
    }
}
