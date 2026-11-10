package com.bradcowdrey.meridian

import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Edit Widget, as the iPhone's: "Use Meridian's cities" (on by default), or, with it off, the widget's own cities,
 * found with the app's city search (every city, airport code and time zone). Saved per widget in Store.prefs
 * (MeridianWidgets.followKey and citiesKey); the widget is placed with the app's cities and can be edited later
 * (widgetFeatures reconfigurable|configuration_optional).
 */
class WidgetConfigActivity : ComponentActivity() {
    // Activity-level so onStop can save them however the screen is left (Back, Home or recents).
    private var id = AppWidgetManager.INVALID_APPWIDGET_ID
    private val follow = mutableStateOf(true)
    private val chosen = mutableStateListOf<MeridianWidgets.Chosen>()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        id = intent?.extras?.getInt(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            ?: AppWidgetManager.INVALID_APPWIDGET_ID
        if (id == AppWidgetManager.INVALID_APPWIDGET_ID) { finish(); return }
        // The app's cities are a whole setup, so leaving at any point keeps the widget (as the iPhone places it).
        setResult(RESULT_OK, Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id))
        enableEdgeToEdge(SystemBarStyle.dark(android.graphics.Color.TRANSPARENT), SystemBarStyle.dark(android.graphics.Color.TRANSPARENT))
        DataFiles.init(applicationContext)
        // Android 8 to 11 skip onUpdate for a widget with a configuration screen: draw it now.
        MeridianWidgets.updateAll(applicationContext)
        val prefs = Store.prefs(applicationContext)
        val places = Store.loadPlaces(applicationContext) ?: emptyList()
        // How many cities the widget shows: one (small), two (medium) or five (large).
        val limit = when (AppWidgetManager.getInstance(this).getAppWidgetInfo(id)?.provider?.className) {
            SmallWidget::class.java.name -> MeridianWidgets.Size.SMALL.cities
            MediumWidget::class.java.name -> MeridianWidgets.Size.MEDIUM.cities
            else -> MeridianWidgets.Size.LARGE.cities
        }
        follow.value = prefs.getBoolean(MeridianWidgets.followKey(id), true)
        chosen.clear()
        chosen.addAll(MeridianWidgets.loadChosen(prefs, id))
        setContent {
            MaterialTheme(colorScheme = darkColorScheme(
                background = Palette.bg, surface = Palette.bg, primary = Color.White, onPrimary = Color.Black,
                surfaceContainer = Palette.tile, surfaceContainerHigh = Palette.tile, onSurface = Palette.primary,
                onSurfaceVariant = Palette.muted, outlineVariant = Palette.cardBorder,
            )) {
                // Saved in onStop, which runs whichever way the screen is left.
                BackHandler { finish() }
                Screen("Edit Widget", onBack = { finish() }) { padding ->
                    WidgetCities(padding, places, limit, follow.value, { follow.value = it }, chosen)
                }
            }
        }
    }

    override fun onStop() {
        super.onStop()
        if (id == AppWidgetManager.INVALID_APPWIDGET_ID) return
        MeridianWidgets.saveChosen(Store.prefs(applicationContext), id, follow.value, chosen.toList())
        MeridianWidgets.updateAll(applicationContext)
    }
}

@Composable
private fun WidgetCities(
    padding: PaddingValues, places: List<Place>, limit: Int, follow: Boolean, setFollow: (Boolean) -> Unit,
    chosen: MutableList<MeridianWidgets.Chosen>,
) {
    var query by remember { mutableStateOf("") }
    // Off the main thread: the first search reads the city list, which takes a moment.
    val searched by produceState<Pair<String, List<CityEntry>>?>(null, query) {
        if (query.isNotBlank()) value = query to kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) { CityDirectory.search(query) }
    }
    fun has(e: CityEntry) = chosen.any { it.name == e.name && it.zoneId == e.zoneId }
    val full = chosen.size >= limit
    LazyColumn(Modifier.fillMaxSize().padding(padding).imePadding()) {
        item {
            Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                Text("Use Meridian's cities", Modifier.weight(1f), color = Palette.primary)
                Switch(follow, setFollow, colors = SwitchDefaults.colors(checkedTrackColor = Palette.switchOn, checkedThumbColor = Color.White,
                    checkedBorderColor = Palette.switchOn, uncheckedTrackColor = white(0.15f), uncheckedThumbColor = white(0.6f),
                    uncheckedBorderColor = white(0.55f)))
            }
            Text(
                if (follow) (if (limit == 1) "This widget shows the first city on your list." else "This widget shows the first $limit cities on your list.")
                else "This widget shows the cities below, in this order (up to " + cityCount(limit) + "). With none chosen, it shows your list.",
                fontSize = 13.sp, lineHeight = 18.sp, color = white(0.6f), modifier = Modifier.padding(horizontal = 16.dp, vertical = 4.dp))
        }
        if (!follow) {
            itemsIndexed(chosen.toList(), key = { _, c -> "chosen|${c.name}|${c.zoneId}" }) { i, c ->
                val onList = places.any { it.name == c.name && it.zoneId == c.zoneId }
                Row(Modifier.fillMaxWidth().padding(start = 16.dp, end = 4.dp, top = 4.dp, bottom = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(c.name, fontSize = 17.sp, color = Palette.primary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(if (onList) "On your list" else WorkWeek.countryName(c.zoneId) ?: c.zoneId.replace("_", " "),
                            fontSize = 14.sp, color = white(0.6f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    if (i > 0) IconButton(onClick = { chosen.add(i - 1, chosen.removeAt(i)) }) {
                        Icon(Icons.Filled.KeyboardArrowUp, "Move ${c.name} up", tint = Palette.primary)
                    }
                    IconButton(onClick = { chosen.removeAt(i) }) { Icon(Icons.Filled.Close, "Remove ${c.name}", tint = Palette.primary) }
                }
                HorizontalDivider(Modifier.padding(horizontal = 16.dp), color = white(0.1f))
            }
            item { CitySearchField(query, focus = false) { query = it } }
            if (full) item {
                Text("This widget shows up to " + cityCount(limit) + ". Remove one to add another.",
                    fontSize = 15.sp, color = white(0.6f), modifier = Modifier.padding(16.dp))
            }
            val results = searched?.takeIf { it.first == query && query.isNotBlank() }?.second.orEmpty()
            if (query.isNotBlank() && searched?.first == query && results.isEmpty()) item {
                Text("No places match “$query”. Try a city, an airport code like SFO, a time zone like PST, or UTC+5:30.",
                    fontSize = 15.sp, color = white(0.6f), modifier = Modifier.padding(16.dp))
            }
            items(results, key = { "result|" + it.id }) { entry ->
                val have = has(entry)
                Row(Modifier.fillMaxWidth().clickable(enabled = !have && !full, onClickLabel = "Add") {
                    chosen.add(MeridianWidgets.Chosen(entry.name, entry.zoneId, entry.countryCode, entry.latitude, entry.longitude))
                    query = ""
                }.padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text(entry.name, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = Palette.primary,
                            maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Text(if (entry.countryCode != null) entry.region else WorkWeek.countryName(entry.zoneId) ?: entry.region.replace("_", " "),
                            fontSize = 14.sp, color = white(0.6f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                    if (have) {
                        Spacer(Modifier.width(12.dp))
                        Icon(Icons.Filled.Check, contentDescription = "Already chosen", tint = white(0.6f))
                    }
                }
                HorizontalDivider(Modifier.padding(horizontal = 16.dp), color = white(0.1f))
            }
        }
    }
}
