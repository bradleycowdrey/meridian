package com.bradcowdrey.meridian

import android.Manifest
import android.content.Context
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.location.Geocoder
import android.location.Location
import android.location.LocationListener
import android.location.LocationManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.time.ZoneId
import java.util.Locale

/**
 * The "My Location" row: the city you're in, kept current when you travel (same as the Mac and
 * iPhone apps). Its time zone always comes from the phone's clock, so it's right even offline or
 * without location permission; Location only gives it its city name. Location is looked up at
 * launch and when the app comes back, never tracked, and only the city name is kept, on the phone.
 */
object MyLocation {
    const val ID = "my-location"
    private const val ADOPTED = "myLocation.adoptedName"

    /** The phone's zone, named after its city ("America/Los_Angeles" -> "Los Angeles"). */
    val zoneName: String get() = ZoneId.systemDefault().id.substringAfterLast('/').replace("_", " ")

    /** The last city found, while the phone is still in the same time zone. */
    fun city(prefs: SharedPreferences): String? =
        if (prefs.getString("myLocation.zone", null) == ZoneId.systemDefault().id) prefs.getString("myLocation.city", null) else null

    /**
     * Adds or updates the row. The first time, a city already in the list in this time zone
     * becomes the row (keeping its place in the order) instead of being shown twice.
     */
    fun apply(places: List<Place>, prefs: SharedPreferences): List<Place> {
        val zone = ZoneId.systemDefault().id
        val city = city(prefs)
        val list = places.toMutableList()
        val mine = list.indexOfFirst { it.isMyLocation }
        val sameZone = list.indexOfFirst { it.zoneId == zone }
        when {
            mine >= 0 -> {
                val moved = list[mine].zoneId != zone
                list[mine] = list[mine].copy(zoneId = zone, name = city ?: if (moved) zoneName else list[mine].name)
            }
            sameZone >= 0 -> {
                prefs.edit().putString(ADOPTED, list[sameZone].name).apply()
                list[sameZone] = list[sameZone].copy(id = ID, name = city ?: list[sameZone].name)
            }
            else -> {
                prefs.edit().remove(ADOPTED).apply()
                list.add(0, Place(city ?: zoneName, zone, ID))
            }
        }
        return list
    }

    /** Takes the row out (the setting was turned off). A city the row took over goes back to normal. */
    fun remove(places: List<Place>, prefs: SharedPreferences): List<Place> {
        val i = places.indexOfFirst { it.isMyLocation }
        if (i < 0) return places
        val adopted = prefs.getString(ADOPTED, null)
        prefs.edit().remove(ADOPTED).apply()
        val list = places.toMutableList()
        if (adopted != null) list[i] = list[i].copy(id = java.util.UUID.randomUUID().toString(), name = adopted) else list.removeAt(i)
        return list
    }

    /** The user deleted the row itself: it goes, whatever it took over. */
    fun forget(prefs: SharedPreferences) = prefs.edit().remove(ADOPTED).apply()

    fun permitted(context: Context) =
        context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

    /** Finds the city name (city-level accuracy) and calls [found] on the main thread when it has one. */
    fun locate(context: Context, found: () -> Unit) {
        if (!permitted(context)) return
        val manager = context.getSystemService(LocationManager::class.java) ?: return
        val last = listOf(LocationManager.NETWORK_PROVIDER, LocationManager.PASSIVE_PROVIDER, LocationManager.GPS_PROVIDER)
            .mapNotNull { runCatching { manager.getLastKnownLocation(it) }.getOrNull() }
            .maxByOrNull { it.time }
        // A fix from the last hour is good enough to name a city; otherwise ask for a fresh one.
        if (last != null && System.currentTimeMillis() - last.time < 3_600_000) { name(context, last, found); return }
        val provider = listOf(LocationManager.NETWORK_PROVIDER, LocationManager.GPS_PROVIDER).firstOrNull { manager.isProviderEnabled(it) }
        if (provider == null) { last?.let { name(context, it, found) }; return }
        runCatching {
            if (Build.VERSION.SDK_INT >= 30) {
                manager.getCurrentLocation(provider, null, context.mainExecutor) { (it ?: last)?.let { l -> name(context, l, found) } }
            } else {
                @Suppress("DEPRECATION")
                manager.requestSingleUpdate(provider, LocationListener { name(context, it, found) }, Looper.getMainLooper())
            }
        }
    }

    private fun name(context: Context, location: Location, found: () -> Unit) {
        if (!Geocoder.isPresent()) return
        val prefs = Store.prefs(context)
        val zone = ZoneId.systemDefault().id
        Thread {
            @Suppress("DEPRECATION")
            val address = runCatching { Geocoder(context, Locale.getDefault()).getFromLocation(location.latitude, location.longitude, 1)?.firstOrNull() }.getOrNull()
            val city = address?.locality ?: address?.subAdminArea ?: address?.adminArea ?: return@Thread
            prefs.edit().putString("myLocation.city", city).putString("myLocation.zone", zone).apply()
            Handler(Looper.getMainLooper()).post(found)
        }.start()
    }
}
