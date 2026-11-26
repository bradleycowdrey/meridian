package com.bradcowdrey.meridian

import android.content.ContextWrapper
import org.json.JSONArray
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import java.io.File

/**
 * SkylineManifest.resolve (the real resolver, fed through DataFiles.testSource and SkylineManifest.testResId) against
 * the photo contract in scripts/photo-index.py's docstring, which iOS and the Mac follow too.
 *
 * [contractCases]: a few hand-checked cases on the bundled data (Resources/Data).
 * [goldenCases]: every case of a golden file made by a reference resolver (cases.json: {"skylines", "index_published",
 * "index_unpublished", "cases": [{id, name, zone, cc, lat, lon, expected_published, expected_unpublished}]}), named by
 * the MERIDIAN_CONFORMANCE_CASES environment variable; skipped without it. Writes the cases whose key differs to
 * android-mismatches.json beside it, and fails if there are any.
 */
class PhotoConformanceTest {
    private val data = listOf(File("../../Resources/Data"), File("../Resources/Data"), File("Resources/Data"))
        .firstOrNull { File(it, "plates-remote.json").exists() }
    private val context = object : ContextWrapper(null) {}

    private fun optD(o: JSONObject, k: String): Double? = if (o.isNull(k)) null else o.optDouble(k, Double.NaN).takeIf { it.isFinite() }
    private fun optS(o: JSONObject, k: String): String? = if (o.isNull(k)) null else o.optString(k)

    /** Forgets the index read so far, so the next resolve reads [DataFiles.testSource]'s. */
    private fun resetRemotePlates() {
        val f = RemotePlates::class.java.getDeclaredField("loaded")
        f.isAccessible = true
        f.set(null, null)
    }

    /** Serves these two files as the data files; every built-in key in [skylines] counts as having a drawable. */
    private fun use(skylines: String, index: String) {
        val keys = HashSet<String>()
        JSONObject(skylines).getJSONArray("cities").let { a -> for (i in 0 until a.length()) keys.add(a.getJSONObject(i).getString("key")) }
        SkylineManifest.testResId = { key, night -> if (key in keys) (if (night) 2 else 1) else 0 }
        DataFiles.testSource = { name ->
            when (name) {
                "skylines.json" -> skylines
                "plates-remote.json" -> index
                else -> null
            }
        }
        resetRemotePlates()
    }

    @Before fun clear() = resetRemotePlates()

    @After fun restore() {
        DataFiles.testSource = null
        SkylineManifest.testResId = null
        resetRemotePlates()
    }

    private fun key(name: String, zone: String, cc: String?, lat: Double?, lon: Double?): String? =
        SkylineManifest.resolve(context, name, zone, cc, lat, lon).let { it.hosted?.key ?: it.photo?.key }

    @Test
    fun contractCases() {
        val dir = data
        assumeTrue("no Resources/Data", dir != null)
        use(File(dir, "skylines.json").readText(), File(dir, "plates-remote.json").readText())
        // 1: accents and case ignored; the key alone is no name; an unknown or different zone doesn't fit.
        assertEquals("hanoi", key("Ha Noi", "Asia/Ho_Chi_Minh", "VN", null, null))
        assertEquals("munich", key("MÜNCHEN", "Europe/Berlin", "DE", null, null))
        assertEquals("mumbai", key("Mumbai", "Asia/Calcutta", "IN", null, null))
        assertEquals("sceneriver", key("London", "Not/AZone", null, null, null))
        // 2: towns within 25 km; without coordinates the one town of that name in the country (the card's, else the zone's).
        assertEquals("denver", key("Littleton", "America/Denver", "US", 39.61, -105.02))
        assertEquals("denver", key("Littleton", "America/Denver", "US", null, null))
        assertEquals("denver", key("Littleton", "America/Denver", null, null, null))
        assertEquals("berlin", key("Weissensee", "Europe/Berlin", "DE", 52.55, 13.47))
        // 3: metros, in the zone's country when the card has none.
        assertEquals("denver", key("Meridian Test Hamlet", "America/Denver", null, 39.58, -105.11))
        // 5: scenes; a lone latitude (or one out of range) is no coordinates.
        assertEquals("scenecoast", key("Beach Village", "Asia/Manila", "PH", 10.0, 123.0))
        assertEquals("sceneriver", key("Beach Village", "Asia/Manila", "PH", 10.0, null))
        assertEquals("sceneriver", key("Beach Village", "Asia/Manila", "PH", 10.0, 200.0))
    }

    @Test
    fun goldenCases() {
        val path = System.getenv("MERIDIAN_CONFORMANCE_CASES")
        assumeTrue("MERIDIAN_CONFORMANCE_CASES not set", path != null && File(path).exists())
        val casesFile = File(path!!)
        val doc = JSONObject(casesFile.readText())
        val skylines = File(doc.getString("skylines")).readText()
        val cases = doc.getJSONArray("cases")
        val out = JSONObject().put("cases", cases.length())
        var total = 0
        for (which in listOf("published", "unpublished")) {
            use(skylines, File(doc.getString("index_$which")).readText())
            val mismatches = JSONArray()
            for (i in 0 until cases.length()) {
                val c = cases.getJSONObject(i)
                val got = key(c.getString("name"), c.getString("zone"), optS(c, "cc"), optD(c, "lat"), optD(c, "lon"))
                val want = optS(c, "expected_$which")
                if (got != want) {
                    mismatches.put(JSONObject().put("id", c.getInt("id")).put("name", c.getString("name")).put("zone", c.getString("zone"))
                        .put("cc", c.opt("cc")).put("lat", c.opt("lat")).put("lon", c.opt("lon")).put("src", c.optString("src"))
                        .put("note", c.opt("note")).put("expected", want ?: JSONObject.NULL).put("step", c.opt("step_$which"))
                        .put("android", got ?: JSONObject.NULL))
                }
            }
            out.put(which, JSONObject().put("mismatches", mismatches.length()).put("list", mismatches))
            println("$which: ${cases.length()} cases, ${mismatches.length()} mismatches")
            total += mismatches.length()
        }
        File(casesFile.parentFile, "android-mismatches.json").writeText(out.toString(1))
        assertEquals("cases whose key differs from the reference (android-mismatches.json)", 0, total)
    }
}
