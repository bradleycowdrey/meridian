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

    /** The first-launch question, the same on Mac, iPhone and Android. */
    const val QUESTION_TITLE = "Use your location?"
    const val QUESTION_MESSAGE = "Meridian can add the city you're in to your list, and keep it current when you travel. Recommended.\n\n" +
        "Your location is only used to name the city, and Meridian keeps just that name, on your phone. You can change this in Settings."
    private const val ADOPTED = "myLocation.adoptedName"

    /** The phone's zone, named after its city ("America/Los_Angeles" -> "Los Angeles"). */
    val zoneName: String get() = ZoneId.systemDefault().id.substringAfterLast('/').replace("_", " ")

    /** The last city found, while the phone is still in the same time zone. */
    fun city(prefs: SharedPreferences): String? =
        if (prefs.getString("myLocation.zone", null) == ZoneId.systemDefault().id) prefs.getString("myLocation.city", null) else null

    private const val HOST = "myLocation.hostID"

    /** The card standing in for My Location (you already have a card in this time zone), so nothing shows twice. */
    fun hostId(prefs: SharedPreferences): String? = prefs.getString(HOST, null)

    /**
     * Shows where you are without showing anything twice. A card already in this time zone stands
     * for it (marked My Location); otherwise there's a My Location card at the top, named after the
     * city you're in, which follows you when you travel and folds back into your own card when you return.
     */
    fun apply(places: List<Place>, prefs: SharedPreferences): List<Place> {
        val zone = ZoneId.systemDefault().id
        val city = city(prefs)
        val list = restoreAdopted(places, prefs).toMutableList()
        val host = list.firstOrNull { !it.isMyLocation && it.person == null && it.zoneId == zone }
        if (host != null) {
            list.removeAll { it.isMyLocation }
            prefs.edit().putString(HOST, host.id).apply()
            return list
        }
        prefs.edit().remove(HOST).apply()
        val mine = list.indexOfFirst { it.isMyLocation }
        if (mine >= 0) {
            val moved = list[mine].zoneId != zone
            list[mine] = list[mine].copy(zoneId = zone, name = city ?: if (moved) zoneName else list[mine].name)
        } else {
            list.add(0, Place(city ?: zoneName, zone, ID))
        }
        return list
    }

    /** Takes My Location out (the setting was turned off): the card goes; a card standing in for it is just a city again. */
    fun remove(places: List<Place>, prefs: SharedPreferences): List<Place> {
        prefs.edit().remove(HOST).apply()
        return restoreAdopted(places, prefs).filter { !it.isMyLocation }
    }

    /** The user deleted the My Location card (or the card standing in for it). */
    fun forget(prefs: SharedPreferences) = prefs.edit().remove(ADOPTED).remove(HOST).apply()

    /** Before this version a city in your time zone was turned into the My Location card; give it back. */
    private fun restoreAdopted(places: List<Place>, prefs: SharedPreferences): List<Place> {
        val name = prefs.getString(ADOPTED, null) ?: return places
        prefs.edit().remove(ADOPTED).apply()
        return places.map { if (it.isMyLocation) it.copy(id = java.util.UUID.randomUUID().toString(), name = name) else it }
    }

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
