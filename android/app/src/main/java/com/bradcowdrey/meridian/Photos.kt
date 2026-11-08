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
import java.net.URLEncoder
import java.time.Instant
import java.time.ZoneId
import java.util.Locale

/** Who took a photo, under which licence, and where it came from. */
data class PhotoCredit(val author: String, val license: String, val licenseUrl: String?, val source: String)

/**
 * The skyline photos built into the app: Resources/Data/skylines.json (written by the photo pipeline:
 * key, names and aliases, time zone, file, credit, and from v2 `night`: {file, credit} or null), each a
 * drawable "skyline_<key>" (the day photo) and, where there is one, "skyline_<key>_night". Until the
 * manifest lands (or for a key it leaves out) the four original photos still work. A v1 manifest (no
 * `night`) still reads: a night drawable is found by its name alone.
 */
object SkylineManifest {
    data class Entry(val key: String, val names: List<String>, val zone: String?, val credit: PhotoCredit?, val nightCredit: PhotoCredit? = null)

    /** A built-in photo for a card: its key (for how it's cropped), its day drawable, and its night one (0 for none). */
    data class Photo(val key: String, val resId: Int, val nightResId: Int = 0)

    private val fallback = listOf(
        Entry("sanfrancisco", listOf("San Francisco"), "America/Los_Angeles",
            PhotoCredit("", "", null, "https://commons.wikimedia.org/wiki/File:San_Francisco_skyline_from_Coit_Tower.jpg")),
        Entry("newyork", listOf("New York", "New York City", "Manhattan"), "America/New_York",
            PhotoCredit("", "", null, "https://commons.wikimedia.org/wiki/File:Manhattan_from_Weehawken,_NJ.jpg")),
        Entry("london", listOf("London"), "Europe/London",
            PhotoCredit("", "", null, "https://commons.wikimedia.org/wiki/File:London_Skyline_(125508655).jpeg")),
        Entry("tokyo", listOf("Tokyo"), "Asia/Tokyo",
            PhotoCredit("", "", null, "https://commons.wikimedia.org/wiki/File:Skyscrapers_of_Shinjuku_2009_January.jpg")),
    )

    @Volatile private var loaded: List<Entry>? = null
    @Volatile private var index: Map<String, List<Entry>> = emptyMap()
    private val resIds = HashMap<String, Int>()

    /** Every built-in photo's entry: the manifest's, then any of the original four it leaves out. */
    val entries: List<Entry>
        get() {
            loaded?.let { return it }
            synchronized(this) {
                loaded?.let { return it }
                val fromManifest = parse(DataFiles.text("skylines.json"))
                val keys = fromManifest.map { it.key }.toSet()
                val all = fromManifest + fallback.filter { it.key !in keys }
                val map = HashMap<String, MutableList<Entry>>()
                for (e in all) for (n in e.names + e.key) {
                    val k = norm(n)
                    if (k.isNotEmpty()) map.getOrPut(k) { mutableListOf() }.let { if (e !in it) it.add(e) }
                }
                index = map
                // Read again later if the data files weren't ready yet.
                if (DataFiles.ready) loaded = all
                return all
            }
        }

    private fun parse(text: String?): List<Entry> {
        if (text.isNullOrBlank()) return emptyList()
        return runCatching {
            val array = JSONArray(text)
            (0 until array.length()).mapNotNull { i ->
                val o = array.optJSONObject(i) ?: return@mapNotNull null
                val key = o.optString("key").trim()
                if (key.isEmpty()) return@mapNotNull null
                val names = o.optJSONArray("names")?.let { a -> (0 until a.length()).map { a.optString(it) }.filter { it.isNotBlank() } } ?: emptyList()
                val credit = o.optJSONObject("credit")?.let { c ->
                    PhotoCredit(c.optString("author"), c.optString("license"), c.optString("licenseUrl").ifBlank { null }, c.optString("source"))
                }
                // v2: "night": {file, credit} or null (v1 has no "night").
                val nightCredit = o.optJSONObject("night")?.optJSONObject("credit")?.let { c ->
                    PhotoCredit(c.optString("author"), c.optString("license"), c.optString("licenseUrl").ifBlank { null }, c.optString("source"))
                }
                Entry(key, names, o.optString("zone").ifBlank { null }, credit, nightCredit)
            }
        }.getOrDefault(emptyList())
    }

    fun norm(name: String): String = name.trim().lowercase(Locale.ROOT)

    /** The drawable for a key ("skyline_<key>", or "skyline_<key>_night" with [night]), or 0 if it isn't in this build. */
    fun resId(context: Context, key: String, night: Boolean = false): Int = synchronized(resIds) {
        resIds.getOrPut(if (night) "$key|night" else key) {
            val name = "skyline_" + key.lowercase(Locale.ROOT).replace(Regex("[^a-z0-9_]"), "_") + if (night) "_night" else ""
            context.resources.getIdentifier(name, "drawable", context.packageName)
        }
    }

    /** Two fixed dates (winter and summer) on which zones are compared. */
    private val zoneCheckDates = listOf(Instant.parse("2026-01-15T12:00:00Z"), Instant.parse("2026-07-15T12:00:00Z"))

    /** Whether two zones are the same, or keep the same time all year (an old name for the same zone). */
    private fun sameZone(a: String, b: String): Boolean {
        if (a == b) return true
        return runCatching {
            val ra = ZoneId.of(a).rules
            val rb = ZoneId.of(b).rules
            zoneCheckDates.all { ra.getOffset(it) == rb.getOffset(it) }
        }.getOrDefault(false)
    }

    /** The built-in photo for a city (by name or alias, ignoring case) in this zone, if there is one. */
    fun photo(context: Context, city: String, zoneId: String): Photo? {
        if (entries.isEmpty()) return null
        val candidates = index[norm(city)] ?: return null
        val match = candidates.firstOrNull { it.zone == null || it.zone == zoneId }
            ?: candidates.firstOrNull { it.zone != null && sameZone(it.zone, zoneId) }
            ?: return null
        val id = resId(context, match.key)
        return if (id != 0) Photo(match.key, id, resId(context, match.key, night = true)) else null
    }

    /** The built-in photos in this build, with their credits (Photo Credits): each day photo, then its night one. */
    fun credited(context: Context): List<Pair<String, PhotoCredit?>> =
        entries.filter { resId(context, it.key) != 0 }.flatMap { e ->
            val name = e.names.firstOrNull() ?: e.key
            listOfNotNull(name to e.credit, if (resId(context, e.key, night = true) != 0) "$name at night" to e.nightCredit else null)
        }
}

/**
 * Photos for cities without a built-in one: from the city's Wikipedia page's lead image, on Wikimedia
 * Commons, only if it's free to use (CC0, public domain, CC BY, CC BY-SA). Fetched once in the
 * background (never more than once in 30 days), then kept on the phone with its credit. Only the
 * city's name is sent. Until a photo is ready (or with none), the card shows its drawn skyline.
 * Once a city has its day photo, one night photo is looked for too (a Commons search for
 * "<city> skyline night": free licence, the title names the city, and dark when measured), kept the
 * same way as <slug>-night.jpg; with none, the card darkens the day photo at night as before.
 */
object CityPhotos {
    private const val USER_AGENT = "Meridian/2.0 (https://bradcowdrey.com/meridian)"
    private const val RETRY_MS = 30L * 24 * 3600 * 1000
    private const val MAX_BYTES = 8 * 1024 * 1024
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    /** One download at a time, gently. */
    private val mutex = Mutex()
    /** Asked for this run (so a card redrawn many times asks once). */
    private val asked = HashSet<String>()
    /** Decoded photos by slug: state, so a card redraws when its photo arrives. */
    private val bitmaps = mutableStateMapOf<String, ImageBitmap>()
    /** Bumped when a photo is saved, so Photo Credits reads the list again. */
    var saved by mutableIntStateOf(0)
        private set

    data class Downloaded(val city: String, val credit: PhotoCredit)

    /** A file name for a city in a zone ("lisbon-1234567"). */
    fun slug(city: String, zoneId: String): String {
        val name = city.trim().lowercase(Locale.ROOT).replace(Regex("[^a-z0-9]+"), "-").trim('-').take(40).ifEmpty { "city" }
        return name + "-" + (city.trim().lowercase(Locale.ROOT) + "|" + zoneId).hashCode().toLong().and(0xFFFFFFFFL).toString(16)
    }

    /** A night photo's name, after its city's slug ("lisbon-1234567-night"; a slug ends in hex, so never another city's). */
    private const val NIGHT = "-night"
    /** The night photo's probe: Commons' 330 px thumbnail, measured before the full photo is fetched. */
    private const val PROBE_WIDTH = 330
    /** A night photo is dark: mean relative luminance of the probe at most this. */
    private const val NIGHT_MAX = 0.10
    /** At most this many candidates are measured per city, a second apart. */
    private const val MAX_PROBES = 4

    /** The photo for this slug, once it's on the phone and read (a state read: callers redraw when it arrives). */
    fun bitmap(slug: String): ImageBitmap? = bitmaps[slug]

    /** The night photo for this slug, once it's on the phone and read (a state read), or null for none (yet). */
    fun nightBitmap(slug: String): ImageBitmap? = bitmaps[slug + NIGHT]

    private fun dir(context: Context): File = File(context.filesDir, "city-photos").apply { mkdirs() }

    /** The downloaded photo for this slug, if it's on the phone (for the widgets' copies). */
    fun file(context: Context, slug: String): File? = File(dir(context), "$slug.jpg").takeIf { it.exists() }

    /** The downloaded night photo for this slug, if it's on the phone (for the widgets' copies). */
    fun nightFile(context: Context, slug: String): File? = File(dir(context), "$slug$NIGHT.jpg").takeIf { it.exists() }

    /**
     * Shows a city's photo if it's on the phone; otherwise, when [download] is on, fetches it in the
     * background (unless a try in the last 30 days found none). Never blocks; safe offline.
     */
    fun request(context: Context, city: String, zoneId: String, countryCode: String?, download: Boolean) {
        val slug = slug(city, zoneId)
        if (bitmaps.containsKey(slug) && bitmaps.containsKey(slug + NIGHT)) return
        val key = "$slug|$download"
        synchronized(asked) { if (!asked.add(key)) return }
        val app = context.applicationContext
        scope.launch {
            try {
                val image = File(dir(app), "$slug.jpg")
                val nightImage = File(dir(app), "$slug$NIGHT.jpg")
                if (image.exists() && !bitmaps.containsKey(slug)) decode(image)?.let { bitmaps[slug] = it }
                if (nightImage.exists() && !bitmaps.containsKey(slug + NIGHT)) decode(nightImage)?.let { bitmaps[slug + NIGHT] = it }
                if (!download) return@launch
                mutex.withLock {
                    if (!image.exists()) {
                        val old = runCatching { JSONObject(File(dir(app), "$slug.json").readText()) }.getOrNull()
                        if (old != null && System.currentTimeMillis() - old.optLong("fetchedAt") < RETRY_MS) return@withLock
                        fetch(app, slug, city, countryCode)
                    }
                    // A night photo only for a city with a day one, and only one try in 30 days.
                    if (!image.exists() || nightImage.exists()) return@withLock
                    val oldNight = runCatching { JSONObject(File(dir(app), "$slug$NIGHT.json").readText()) }.getOrNull()
                    if (oldNight != null && System.currentTimeMillis() - oldNight.optLong("fetchedAt") < RETRY_MS) return@withLock
                    fetchNight(app, slug, city)
                }
            } catch (e: IOException) {
                // Offline or a server hiccup: not marked as tried on disk, so the next launch tries again (asked keeps it out until then).
            } catch (e: Exception) {
                // Anything unexpected: the drawn skyline stays.
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

    /** Marks a city as having no usable photo (or night photo, for "<slug>-night"), so it isn't asked again for 30 days. */
    private fun markNone(context: Context, name: String, city: String) {
        runCatching {
            File(dir(context), "$name.json").writeText(JSONObject().put("city", city).put("ok", false)
                .put("night", name.endsWith(NIGHT)).put("fetchedAt", System.currentTimeMillis()).toString())
        }
    }

    /** Lower case, without accents, spaces for underscores: for checking a file's title names the city. */
    private fun fold(text: String): String =
        java.text.Normalizer.normalize(text, java.text.Normalizer.Form.NFD).replace(Regex("\\p{M}+"), "")
            .replace('_', ' ').lowercase(Locale.ROOT).replace(Regex("\\s+"), " ").trim()

    /** The mean relative luminance of a JPEG (decoded near [PROBE_WIDTH] px wide), or null if it won't decode. */
    private fun meanLuminance(bytes: ByteArray): Double? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
        if (bounds.outWidth <= 0 || bounds.outHeight <= 0) return null
        var sample = 1
        while (bounds.outWidth / (sample * 2) >= PROBE_WIDTH) sample *= 2
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sample }) ?: return null
        try {
            val w = bitmap.width
            val h = bitmap.height
            val row = IntArray(w)
            fun lin(c: Int): Double { val v = c / 255.0; return if (v <= 0.04045) v / 12.92 else Math.pow((v + 0.055) / 1.055, 2.4) }
            var sum = 0.0
            var n = 0
            for (y in 0 until h step 2) {
                bitmap.getPixels(row, 0, w, 0, y, w, 1)
                for (x in 0 until w step 2) {
                    val c = row[x]
                    sum += 0.2126 * lin((c shr 16) and 0xFF) + 0.7152 * lin((c shr 8) and 0xFF) + 0.0722 * lin(c and 0xFF)
                    n++
                }
            }
            return if (n > 0) sum / n else null
        } finally {
            bitmap.recycle()
        }
    }

    /**
     * Looks for one night photo of a city on Commons ("<city> skyline night"): a free-licence JPEG, in
     * landscape, at least 800 px wide, whose title names the city, and dark when measured (mean luminance
     * of its 330 px thumbnail at most 0.10). Saved at about 960 px as <slug>-night.jpg, with its credit.
     */
    private suspend fun fetchNight(context: Context, slug: String, city: String) {
        val name = slug + NIGHT
        val api = "https://commons.wikimedia.org/w/api.php?action=query&format=json&generator=search&gsrnamespace=6&gsrlimit=10" +
            "&gsrsearch=" + URLEncoder.encode("$city skyline night", "UTF-8") +
            "&prop=imageinfo&iiprop=" + URLEncoder.encode("url|size|extmetadata", "UTF-8") + "&iiurlwidth=$PROBE_WIDTH"
        val pages = getJson(api)?.optJSONObject("query")?.optJSONObject("pages")
        if (pages == null) { markNone(context, name, city); return }
        val candidates = pages.keys().asSequence().mapNotNull { pages.optJSONObject(it) }
            .sortedBy { it.optInt("index", Int.MAX_VALUE) }.toList()
        val wanted = fold(city)
        val commons = "https://upload.wikimedia.org/wikipedia/commons/"
        var probes = 0
        for (page in candidates) {
            if (probes >= MAX_PROBES) break
            val file = page.optString("title").removePrefix("File:")
            val lower = file.lowercase(Locale.ROOT)
            if (!(lower.endsWith(".jpg") || lower.endsWith(".jpeg"))) continue
            if (wanted.isEmpty() || !fold(file).contains(wanted)) continue
            val info = page.optJSONArray("imageinfo")?.optJSONObject(0) ?: continue
            val credit = info.optJSONObject("extmetadata")?.let { creditFrom(file, it) } ?: continue
            val width = info.optInt("width")
            val height = info.optInt("height")
            if (width < 800 || width <= height) continue
            val thumb = info.optString("thumburl").takeIf { it.startsWith(commons) } ?: continue
            if (probes > 0) kotlinx.coroutines.delay(1000)
            probes++
            val probe = getBytes(thumb) ?: continue
            val lum = meanLuminance(probe) ?: continue
            if (lum > NIGHT_MAX) continue
            val url = when {
                width <= 960 -> info.optString("url")
                Regex("/\\d+px-").containsMatchIn(thumb) -> thumb.replace(Regex("/\\d+px-"), "/960px-")
                else -> null
            }?.takeIf { it.startsWith(commons) } ?: continue
            kotlinx.coroutines.delay(1000)
            val bytes = getBytes(url) ?: continue
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) continue
            val folder = dir(context)
            val tmp = File(folder, "$name.jpg.part")
            tmp.writeBytes(bytes)
            val image = File(folder, "$name.jpg")
            if (!tmp.renameTo(image)) { tmp.delete(); return }
            File(folder, "$name.json").writeText(JSONObject().put("city", city).put("ok", true).put("night", true)
                .put("fetchedAt", System.currentTimeMillis())
                .put("author", credit.author).put("license", credit.license)
                .put("licenseUrl", credit.licenseUrl ?: "").put("source", credit.source).toString())
            decode(image)?.let { bitmaps[name] = it }
            saved++
            MeridianWidgets.updateAll(context)
            return
        }
        markNone(context, name, city)
    }

    private fun fetch(context: Context, slug: String, city: String, countryCode: String?) {
        val country = countryCode?.takeIf { it.length == 2 }?.let { Locale("", it.uppercase(Locale.ROOT)).getDisplayCountry(Locale.ENGLISH) }
            ?.takeIf { it.isNotBlank() && !it.equals(countryCode, ignoreCase = true) }
        val titles = listOfNotNull(country?.let { "$city, $it" }, city).distinct()
        for (title in titles) {
            val summary = getJson("https://en.wikipedia.org/api/rest_v1/page/summary/" + encodeTitle(title)) ?: continue
            if (summary.optString("type") == "disambiguation") continue
            val url = imageUrl(summary) ?: continue
            val file = commonsFile(url) ?: continue
            if (!file.lowercase(Locale.ROOT).let { it.endsWith(".jpg") || it.endsWith(".jpeg") }) continue
            val credit = credit(file) ?: continue
            val bytes = getBytes(url) ?: continue
            val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
            BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
            if (bounds.outWidth <= 0 || bounds.outHeight <= 0) continue
            val folder = dir(context)
            val tmp = File(folder, "$slug.jpg.part")
            tmp.writeBytes(bytes)
            val image = File(folder, "$slug.jpg")
            if (!tmp.renameTo(image)) { tmp.delete(); return }
            File(folder, "$slug.json").writeText(JSONObject().put("city", city).put("ok", true)
                .put("fetchedAt", System.currentTimeMillis())
                .put("author", credit.author).put("license", credit.license)
                .put("licenseUrl", credit.licenseUrl ?: "").put("source", credit.source).toString())
            decode(image)?.let { bitmaps[slug] = it }
            saved++
            // The widgets show it too: their small copy is made, then they redraw.
            MeridianWidgets.updateAll(context)
            return
        }
        markNone(context, slug, city)
    }

    private fun encodeTitle(title: String): String =
        URLEncoder.encode(title.trim().replace(' ', '_'), "UTF-8").replace("+", "%20")

    /**
     * The lead image at about 1000 px: Wikimedia's thumbnail at 960 px (a width it serves), or the
     * original when that's no wider. Only images on Commons (not English Wikipedia's own uploads).
     */
    private fun imageUrl(summary: JSONObject): String? {
        val thumb = summary.optJSONObject("thumbnail")?.optString("source")?.takeIf { it.isNotBlank() }
        val original = summary.optJSONObject("originalimage")
        val originalUrl = original?.optString("source")?.takeIf { it.isNotBlank() }
        val originalWidth = original?.optInt("width") ?: 0
        val url = when {
            originalUrl != null && originalWidth in 1..960 -> originalUrl
            thumb != null && Regex("/\\d+px-").containsMatchIn(thumb) -> thumb.replace(Regex("/\\d+px-"), "/960px-")
            originalUrl != null && originalWidth in 1..1280 -> originalUrl
            else -> null
        } ?: return null
        return url.takeIf { it.startsWith("https://upload.wikimedia.org/wikipedia/commons/") }
    }

    /** "Lisbon_skyline.jpg" from an upload.wikimedia.org URL (a thumbnail's or the original's). */
    private fun commonsFile(url: String): String? {
        val path = url.substringAfter("/wikipedia/commons/", "").substringBefore('?')
        if (path.isEmpty()) return null
        val parts = path.split('/')
        val raw = if (parts.firstOrNull() == "thumb") parts.getOrNull(3) else parts.getOrNull(2)
        return raw?.takeIf { it.isNotBlank() }?.let { android.net.Uri.decode(it) }
    }

    /** The file's author and licence on Commons, if it's free to use (else null). */
    private fun credit(file: String): PhotoCredit? {
        val api = "https://commons.wikimedia.org/w/api.php?action=query&titles=" + URLEncoder.encode("File:$file", "UTF-8") +
            "&prop=imageinfo&iiprop=extmetadata&format=json&origin=*"
        val json = getJson(api) ?: return null
        val pages = json.optJSONObject("query")?.optJSONObject("pages") ?: return null
        val keys = pages.keys()
        while (keys.hasNext()) {
            val page = pages.optJSONObject(keys.next()) ?: continue
            val meta = page.optJSONArray("imageinfo")?.optJSONObject(0)?.optJSONObject("extmetadata") ?: continue
            return creditFrom(file, meta)
        }
        return null
    }

    /** A file's credit from its Commons extmetadata, if it's free to use (else null). */
    private fun creditFrom(file: String, meta: JSONObject): PhotoCredit? {
        fun value(name: String) = meta.optJSONObject(name)?.optString("value")?.let { plain(it) } ?: ""
        val license = value("LicenseShortName")
        if (!freeLicense(license)) return null
        val author = value("Artist").ifBlank { "Unknown" }
        val licenseUrl = value("LicenseUrl").ifBlank { null }
        return PhotoCredit(author, license, licenseUrl, "https://commons.wikimedia.org/wiki/File:" + file.replace(' ', '_'))
    }

    /** CC0, public domain, CC BY or CC BY-SA (any version); not NC or ND. */
    fun freeLicense(name: String): Boolean {
        val s = name.trim().lowercase(Locale.ROOT)
        return s.startsWith("cc0") || s.startsWith("public domain") ||
            Regex("^cc[ -]by(-sa)?([ -][0-9][0-9a-z. ,-]*)?$").matches(s)
    }

    /** Text from Commons' HTML values (an author's link). */
    private fun plain(html: String): String =
        android.text.Html.fromHtml(html, android.text.Html.FROM_HTML_MODE_LEGACY).toString().replace(Regex("\\s+"), " ").trim()

    private fun open(url: String): HttpURLConnection {
        val c = URL(url).openConnection() as HttpURLConnection
        c.connectTimeout = 10_000
        c.readTimeout = 15_000
        c.instanceFollowRedirects = true
        c.setRequestProperty("User-Agent", USER_AGENT)
        c.setRequestProperty("Api-User-Agent", USER_AGENT)
        return c
    }

    /** The response as JSON; null for a page that isn't there (404) or isn't JSON; throws on a network or server error. */
    private fun getJson(url: String): JSONObject? {
        val c = open(url)
        c.setRequestProperty("Accept", "application/json")
        try {
            val code = c.responseCode
            if (code == 404 || code == 400) return null
            if (code == 429 || code >= 500) throw IOException("HTTP $code")
            if (code !in 200..299) return null
            val text = c.inputStream.bufferedReader(Charsets.UTF_8).use { it.readText() }
            return runCatching { JSONObject(text) }.getOrNull()
        } finally {
            c.disconnect()
        }
    }

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

    /** The photos downloaded so far, with their credits (Photo Credits). Reads files: call off the main thread. */
    fun downloaded(context: Context): List<Downloaded> {
        val files = dir(context).listFiles { f -> f.name.endsWith(".json") } ?: return emptyList()
        return files.mapNotNull { f ->
            runCatching {
                val o = JSONObject(f.readText())
                if (!o.optBoolean("ok")) return@runCatching null
                if (!File(f.parentFile, f.name.removeSuffix(".json") + ".jpg").exists()) return@runCatching null
                val city = o.optString("city").let { if (o.optBoolean("night")) "$it at night" else it }
                Downloaded(city, PhotoCredit(o.optString("author"), o.optString("license"),
                    o.optString("licenseUrl").ifBlank { null }, o.optString("source")))
            }.getOrNull()
        }.sortedBy { it.city.lowercase(Locale.ROOT) }
    }
}

/**
 * The home screen widgets' photos: small copies (about 480 px wide, JPEG quality 60) of each listed
 * city's photo, built in or downloaded, in filesDir/widget-skylines/<key>.jpg, and of its night photo
 * where it has one, <key>-night.jpg, with which city uses which (map.json: card id -> key, crop and
 * whether there's a night copy). Made by the app whenever the list changes or a downloaded
 * photo arrives (MeridianWidgets.updateAll does this before it redraws), so a widget only ever decodes
 * a small file and never touches the network.
 */
object WidgetPhotos {
    private const val DIR = "widget-skylines"
    private const val MAP = "map.json"
    private const val MAX_WIDTH = 480
    private const val QUALITY = 60

    /**
     * A card's photo: [key] names the copy; [resId] (built in) or [slug] (downloaded) is where it came from.
     * [night]: the city has a night photo too (copied as <key>-night.jpg; built in from [nightResId]).
     */
    data class Ref(val key: String, val biasY: Float, val resId: Int = 0, val slug: String? = null,
        val nightResId: Int = 0, val night: Boolean = false)

    fun dir(context: Context): File = File(context.filesDir, DIR).apply { mkdirs() }

    /** Where each built-in photo is cropped: a little above centre, so the tops of the towers stay in (as the cards). */
    fun biasY(key: String?): Float = when (key) {
        "sanfrancisco" -> -0.35f
        "london" -> -0.45f
        "newyork" -> -0.2f
        else -> -0.1f
    }

    /** The city a card's photo is for: a person's city, or the city you're in for My Location. */
    fun city(context: Context, place: Place): String =
        if (place.isMyLocation) MyLocation.city(Store.prefs(context)) ?: place.name else place.name

    /** The photo for a card (built in, else downloaded and on the phone), or null for none (a drawn sky). */
    fun ref(context: Context, place: Place): Ref? {
        val city = city(context, place)
        SkylineManifest.photo(context, city, place.zoneId)?.let {
            return Ref(it.key, biasY(it.key), resId = it.resId, nightResId = it.nightResId, night = it.nightResId != 0)
        }
        val slug = CityPhotos.slug(city, place.zoneId)
        if (CityPhotos.file(context, slug) != null) return Ref("dl-$slug", biasY(null), slug = slug, night = CityPhotos.nightFile(context, slug) != null)
        return null
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
            copy(ref.key, ref.resId, ref.slug?.let { CityPhotos.file(context, it) })
            if (ref.night) copy(ref.key + "-night", ref.nightResId, ref.slug?.let { CityPhotos.nightFile(context, it) })
        }
        runCatching {
            val map = JSONObject()
            refs.forEach { (id, r) -> map.put(id, JSONObject().put("key", r.key).put("biasY", r.biasY.toDouble()).put("night", r.night)) }
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
            id to Ref(key, e.optDouble("biasY", -0.1).toFloat(), night = e.optBoolean("night"))
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
        ref.slug?.let { CityPhotos.file(context, it) }?.let { decodeFile(it, maxWidth) }
    }.getOrNull()

    /**
     * A card's night photo for a widget, at most [maxWidth] px wide: its small copy (<key>-night.jpg), else
     * the original night photo, downsampled. Null when the city has none: the widget then shades the day photo.
     */
    fun loadNight(context: Context, ref: Ref, maxWidth: Int = 600): Bitmap? = runCatching {
        val copy = File(dir(context), ref.key + "-night.jpg")
        if (copy.exists()) decodeFile(copy, maxWidth)?.let { return@runCatching it }
        if (ref.nightResId != 0) decodeResource(context, ref.nightResId, maxWidth)?.let { return@runCatching it }
        ref.slug?.let { CityPhotos.nightFile(context, it) }?.let { decodeFile(it, maxWidth) }
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
