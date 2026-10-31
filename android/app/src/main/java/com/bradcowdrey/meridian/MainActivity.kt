package com.bradcowdrey.meridian

import android.Manifest
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import java.time.Instant
import kotlin.math.roundToInt

/** bradcowdrey.com colours, shared with the widgets. */
object Palette {
    val bg = Color(0xFF1A1816)
    val tile = Color(0xFF23201D)
    val border = Color(0xFF3A3530)
    val primary = Color.White
    val secondary = Color(0xFFE0D8D0)
    val muted = Color(0xFFB0A898)
    val faint = Color(0xFF807870)
    val cream = Color(0xFFFFF1E5)
    val crimson = Color(0xFF990F3D)
    const val WEBSITE = "https://bradcowdrey.com"
    const val APP_PAGE = "https://bradcowdrey.com/meridian"
    const val LEGAL = "https://bradcowdrey.com/legal"
    const val SOURCE = "https://github.com/bradleycowdrey/meridian"
    const val SHARE_MESSAGE = "Meridian: every time zone at a glance. Free, by Bradley Cowdrey."
}

class MainActivity : ComponentActivity() {
    private var store: Store? = null

    /** Back in the app (maybe after travelling): refresh My Location. */
    override fun onResume() {
        super.onResume()
        store?.takeIf { it.termsAccepted }?.let { it.updateMyLocation(); it.locate() }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(SystemBarStyle.dark(android.graphics.Color.TRANSPARENT), SystemBarStyle.dark(android.graphics.Color.TRANSPARENT))
        // Screenshot mode (CI): --ez screenshots true --es screen main|travel|add|edit|settings|widgets|terms
        val demo = intent.getBooleanExtra("screenshots", false)
        val screen = intent.getStringExtra("screen") ?: "main"
        val store = Store(applicationContext, demo = demo && screen != "terms")
        this.store = store
        setContent {
            MaterialTheme(colorScheme = darkColorScheme(
                background = Palette.bg, surface = Palette.bg, primary = Palette.cream, onPrimary = Palette.bg,
                surfaceContainer = Palette.tile, surfaceContainerHigh = Palette.tile, onSurface = Palette.primary,
                onSurfaceVariant = Palette.muted, outlineVariant = Palette.border,
            )) {
                Surface(color = Palette.bg, modifier = Modifier.fillMaxSize()) {
                    if (!store.termsAccepted) TermsScreen { store.acceptTerms() }
                    else App(store, if (demo) screen else "main")
                }
            }
        }
    }
}

@Composable
fun App(store: Store, initial: String) {
    var route by remember { mutableStateOf(if (initial == "travel") "main" else initial) }
    LaunchedEffect(Unit) {
        if (initial == "travel") store.jump(TimeMath.hourAnchor(store.now, store.home).plusSeconds(5 * 3600))
        while (true) { store.tick(); delay(1000) }
    }
    // My Location: ask for location permission once (after the terms), then name the city.
    val context = LocalContext.current
    val askLocation = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) store.locate()
    }
    LaunchedEffect(store.useMyLocation, store.locationChosen) {
        if (!store.useMyLocation || !store.locationChosen || store.demo) return@LaunchedEffect
        if (MyLocation.permitted(context)) store.locate()
        else if (!store.locationAsked) { store.markLocationAsked(); askLocation.launch(Manifest.permission.ACCESS_COARSE_LOCATION) }
    }
    // First launch, after the terms: use my location? Yes is the recommended answer.
    if (!store.locationChosen) {
        AlertDialog(
            onDismissRequest = {},
            title = { Text(MyLocation.QUESTION_TITLE) },
            text = { Text(MyLocation.QUESTION_MESSAGE) },
            confirmButton = { Button(onClick = { store.updateUseMyLocation(true) }) { Text("Use My Location") } },
            dismissButton = { TextButton(onClick = { store.updateUseMyLocation(false) }) { Text("Not Now") } },
            containerColor = Palette.tile,
        )
    }
    BackHandler(enabled = route != "main") { route = "main" }
    when (route) {
        "add" -> AddCityScreen(store) { route = "main" }
        "edit" -> EditCitiesScreen(store) { route = "main" }
        "settings" -> SettingsScreen(store) { route = "main" }
        "widgets" -> WidgetShowcase(store)
        else -> MainScreen(store) { route = it }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun MainScreen(store: Store, open: (String) -> Unit) {
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current
    val haptics = LocalHapticFeedback.current
    var menu by remember { mutableStateOf(false) }
    var copied by remember { mutableStateOf(false) }
    var renaming by remember { mutableStateOf<Place?>(null) }

    LaunchedEffect(store.userMoves) {
        if (store.userMoves > 0) haptics.performHapticFeedback(
            if (store.onTheHour) HapticFeedbackType.LongPress else HapticFeedbackType.TextHandleMove)
    }
    LaunchedEffect(copied) { if (copied) { delay(1800); copied = false } }

    fun share(text: String) = context.startActivity(Intent.createChooser(
        Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text), null))

    Scaffold(
        containerColor = Palette.bg,
        topBar = {
            Column {
                CenterAlignedTopAppBar(
                    title = { Text("Meridian", fontWeight = FontWeight.SemiBold) },
                    navigationIcon = {
                        IconButton(onClick = { share("${Palette.SHARE_MESSAGE} ${Palette.APP_PAGE}") }) {
                            Icon(Icons.Filled.Share, contentDescription = "Share Meridian")
                        }
                    },
                    actions = {
                        if (store.places.isNotEmpty()) TextButton(onClick = { open("edit") }) { Text("Edit", color = Palette.cream) }
                        IconButton(onClick = { open("add") }, enabled = store.canAdd) { Icon(Icons.Filled.Add, "Add City") }
                        Box {
                            IconButton(onClick = { menu = true }) { Icon(Icons.Filled.MoreVert, "More") }
                            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                                DropdownMenuItem(text = { Text("Go to Date…") }, onClick = { menu = false; pickDate(context, store) })
                                DropdownMenuItem(text = { Text("Copy This Moment") }, enabled = store.places.isNotEmpty(), onClick = {
                                    menu = false; clipboard.setText(AnnotatedString(store.momentText)); copied = true
                                })
                                DropdownMenuItem(text = { Text("Share This Moment") }, enabled = store.places.isNotEmpty(), onClick = {
                                    menu = false; share(store.momentText)
                                })
                                HorizontalDivider()
                                DropdownMenuItem(text = { Text("24-Hour Time") }, onClick = { store.updateUse24h(!store.use24h) },
                                    trailingIcon = { Checkbox(checked = store.use24h, onCheckedChange = { store.updateUse24h(it) }) })
                                DropdownMenuItem(text = { Text("Settings") }, onClick = { menu = false; open("settings") })
                            }
                        }
                    },
                    colors = TopAppBarDefaults.centerAlignedTopAppBarColors(containerColor = Palette.bg,
                        titleContentColor = Palette.primary, navigationIconContentColor = Palette.cream, actionIconContentColor = Palette.cream),
                )
                Box(Modifier.fillMaxWidth().height(3.dp).background(Palette.crimson))
            }
        },
    ) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding)) {
            stickyHeader {
                MomentHeader(store, copied) { pickDate(context, store) }
            }
            if (store.places.isEmpty()) item {
                Column(Modifier.fillMaxWidth().padding(vertical = 48.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("No cities yet", fontWeight = FontWeight.SemiBold)
                    Spacer(Modifier.height(10.dp))
                    Button(onClick = { open("add") }) { Text("Add a City") }
                }
            }
            items(store.places, key = { it.id }) { place ->
                var actions by remember { mutableStateOf(false) }
                Box {
                    CityRow(store, place, Modifier.combinedClickable(onClick = {}, onLongClick = { actions = true }))
                    DropdownMenu(expanded = actions, onDismissRequest = { actions = false }) {
                        DropdownMenuItem(text = { Text("Copy Time") }, onClick = {
                            actions = false
                            clipboard.setText(AnnotatedString("${place.name}: ${TimeMath.fullMoment(store.moment, place.zone, store.use24h)}"))
                            copied = true
                        })
                        if (!place.isMyLocation) DropdownMenuItem(text = { Text("Rename") }, onClick = { actions = false; renaming = place })
                        DropdownMenuItem(text = { Text("Remove", color = Color(0xFFFF6B6B)) }, onClick = { actions = false; store.remove(place) })
                    }
                }
                HorizontalDivider(Modifier.padding(horizontal = 20.dp), color = Palette.border, thickness = 0.5.dp)
            }
            item { Footer() }
        }
    }
    renaming?.let { place -> RenameDialog(place, onDone = { name -> if (name != null) store.rename(place, name); renaming = null }) }
}

/** A small "NOW" (or "IN 4 HR 20 MIN") over the date and time, a Now button when away, the meeting planner line. */
@Composable
fun MomentHeader(store: Store, copied: Boolean, pickDate: () -> Unit) {
    Column(Modifier.fillMaxWidth().background(Palette.bg).padding(start = 20.dp, end = 20.dp, top = 14.dp, bottom = 12.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f).clickable(onClick = pickDate)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (store.isNow) { Box(Modifier.size(6.dp).clip(CircleShape).background(Palette.crimson)); Spacer(Modifier.width(6.dp)) }
                    Text(if (copied) "COPIED" else relative(store).uppercase(), fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
                        letterSpacing = 0.8.sp, color = if (store.isNow) Palette.muted else Palette.cream)
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(TimeMath.fullMoment(store.moment, store.home, store.use24h), fontSize = 20.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                    Icon(Icons.Filled.ArrowDropDown, contentDescription = "Choose a date and time", tint = Palette.faint)
                }
            }
            if (!store.isNow) {
                Button(onClick = { store.backToNow() }, colors = ButtonDefaults.buttonColors(containerColor = Palette.cream, contentColor = Palette.bg),
                    contentPadding = PaddingValues(horizontal = 18.dp), modifier = Modifier.height(34.dp)) { Text("Now", fontWeight = FontWeight.SemiBold) }
            }
        }
        if (!store.hasScrubbed && store.places.isNotEmpty()) {
            Spacer(Modifier.height(8.dp))
            Text("Drag any bar to change the time", fontSize = 13.sp, color = Palette.muted)
        }
        overlap(store)?.let { (allIn, text) ->
            Spacer(Modifier.height(10.dp))
            Row(Modifier.clip(RoundedCornerShape(50)).background(Palette.tile).padding(horizontal = 12.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Text(if (allIn) "✓" else "☾", color = if (allIn) Palette.cream else Palette.faint, fontSize = 13.sp)
                Spacer(Modifier.width(6.dp))
                Text(text, fontSize = 13.sp, color = Palette.secondary, maxLines = 1)
            }
        }
    }
}

private fun relative(store: Store): String {
    if (store.isNow) return "Now"
    val total = (((store.moment.epochSecond - store.now.epochSecond) / 300.0).roundToInt()) * 5
    if (total == 0) return "Now"
    val a = kotlin.math.abs(total)
    val span = listOfNotNull(
        (a / 1440).takeIf { it > 0 }?.let { "$it d" }, (a % 1440 / 60).takeIf { it > 0 }?.let { "$it hr" },
        (a % 60).takeIf { it > 0 }?.let { "$it min" },
    ).joinToString(" ")
    return if (total > 0) "In $span" else "$span ago"
}

private fun overlap(store: Store): Pair<Boolean, String>? {
    if (!store.showWorkHours || store.places.size < 2) return null
    val out = store.outsideWorkHours
    return when {
        out.isEmpty() -> true to "Working hours in every city"
        out.size == store.places.size -> false to "Outside working hours everywhere"
        else -> false to "Outside working hours: ${out.take(3).joinToString(", ") { it.name }}${if (out.size > 3) " +${out.size - 3}" else ""}"
    }
}

/** One city: how it relates to you and its name on the left, its time large and light on the right; then its day bar. */
@Composable
fun CityRow(store: Store, place: Place, modifier: Modifier = Modifier) {
    val moment = store.moment
    val (clock, suffix) = TimeMath.clock(moment, place.zone, store.use24h)
    val shift = TimeMath.dayShift(moment, place.zone, store.home)
    val utc = TimeMath.offsetLabel(TimeMath.offsetSeconds(place.zone, moment))
    val detail = (TimeMath.relative(moment, place.zone, store.home)
        ?: if (place.zone.id == store.home.id) "Your time" else "Same time") + " · " + utc
    Column(modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 14.dp)
        .semantics(mergeDescendants = true) { contentDescription = "${place.name}${if (place.isMyLocation) ", My Location" else ""}, ${TimeMath.time(moment, place.zone, store.use24h)}, $detail" }) {
        Row(verticalAlignment = Alignment.Bottom) {
            Column(Modifier.weight(1f)) {
                Text(detail, fontSize = 13.sp, color = Palette.muted, maxLines = 1)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(place.name, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, maxLines = 1, modifier = Modifier.weight(1f, fill = false))
                    if (place.isMyLocation) MyLocationMark()
                }
            }
            Row(verticalAlignment = Alignment.Bottom) {
                Text(clock, fontSize = 40.sp, fontWeight = FontWeight.Light, lineHeight = 40.sp, modifier = Modifier.alignByBaseline())
                if (suffix != null) {
                    Spacer(Modifier.width(4.dp))
                    Text(suffix, fontSize = 20.sp, color = Palette.muted, modifier = Modifier.alignByBaseline())
                }
                if (shift != 0) {
                    Spacer(Modifier.width(6.dp))
                    Text(if (shift > 0) "+$shift d" else "−${-shift} d", fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = Palette.cream,
                        modifier = Modifier.alignByBaseline().clip(RoundedCornerShape(50)).background(Palette.border).padding(horizontal = 5.dp, vertical = 1.dp))
                }
            }
        }
        Spacer(Modifier.height(12.dp))
        DayBar(store, place)
    }
}

/**
 * Twelve hours of a city's sky in one slim bar (six before the selected moment, six after), dimmer
 * outside working hours, a crimson tick at midnight, a cream knob at the selected moment, and the
 * city's hours labelled underneath. Drag it to move through time; tap to go to that hour.
 */
@Composable
fun DayBar(store: Store, place: Place) {
    val hoursShown = 12.0
    val moment = store.moment
    val start = moment.minusSeconds((hoursShown / 2 * 3600).toLong())
    var width by remember { mutableFloatStateOf(1f) }
    val marks = marks(start, hoursShown, place, store)
    Column(Modifier.fillMaxWidth()
        .onSizeChanged { width = it.width.toFloat().coerceAtLeast(1f) }
        .pointerInput(place.id) {
            detectTapGestures { offset ->
                val tapped = start.plusSeconds((offset.x / width * hoursShown * 3600).toLong())
                store.jump(tapped.atZone(place.zone).withMinute(0).withSecond(0).withNano(0).toInstant())
            }
        }
        .pointerInput(place.id) {
            var base = 0
            var dx = 0f
            detectHorizontalDragGestures(
                onDragStart = { base = store.offsetMinutes; dx = 0f },
            ) { _, amount ->
                dx += amount
                val minutes = -dx / (width / hoursShown.toFloat()) * 60
                store.scrub(base + (minutes / 15).roundToInt() * 15)
            }
        }) {
        Box(Modifier.fillMaxWidth().height(18.dp), contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxWidth().height(8.dp).clip(RoundedCornerShape(50))) {
                val slices = (hoursShown * 4).toInt()
                val slice = size.width / slices
                for (i in 0 until slices) {
                    val at = start.plusSeconds(i * 900L + 450).atZone(place.zone)
                    val dim = store.showWorkHours && !store.isWorkHour(at.hour)
                    drawRect(Color(tone(DayColor.at(at.hour + at.minute / 60.0), dim)),
                        topLeft = Offset(i * slice, 0f), size = Size(slice + 1f, size.height))
                }
                marks.filter { it.midnight }.forEach {
                    val x = it.fraction * size.width
                    drawRect(Palette.crimson, topLeft = Offset(x - 1.5f, 0f), size = Size(3f, size.height))
                }
            }
            Box(Modifier.size(16.dp).shadow(2.dp, CircleShape).clip(CircleShape).background(Palette.cream).border(3.dp, Palette.bg, CircleShape))
        }
        Spacer(Modifier.height(4.dp))
        Layout(content = {
            marks.forEach {
                Text(it.label, fontSize = 11.sp, fontWeight = if (it.midnight) FontWeight.SemiBold else FontWeight.Normal,
                    color = if (it.midnight) Palette.cream else Palette.muted, maxLines = 1)
            }
        }, modifier = Modifier.fillMaxWidth()) { measurables, constraints ->
            val w = constraints.maxWidth
            val placeables = measurables.map { it.measure(Constraints()) }
            layout(w, placeables.maxOfOrNull { it.height } ?: 0) {
                placeables.forEachIndexed { i, p ->
                    val x = (marks[i].fraction * w - p.width / 2f).roundToInt().coerceIn(0, (w - p.width).coerceAtLeast(0))
                    p.placeRelative(x, 0)
                }
            }
        }
    }
}

private data class Mark(val fraction: Float, val label: String, val midnight: Boolean)

/** The city's hours divisible by three inside the bar (not at its very ends), and midnights. */
private fun marks(start: Instant, hoursShown: Double, place: Place, store: Store): List<Mark> {
    val end = start.plusSeconds((hoursShown * 3600).toLong())
    var at = start.atZone(place.zone).withMinute(0).withSecond(0).withNano(0).plusHours(1)
    val marks = mutableListOf<Mark>()
    while (at.toInstant() < end) {
        val fromStart = at.toEpochSecond() - start.epochSecond
        val toEnd = end.epochSecond - at.toEpochSecond()
        if (fromStart >= 1800 && toEnd >= 1800 && at.hour % 3 == 0) {
            val label = if (at.hour == 0) TimeMath.weekday(at.toInstant(), place.zone).uppercase() else TimeMath.hourLabel(at.hour, store.use24h)
            marks += Mark((fromStart / (hoursShown * 3600)).toFloat(), label, at.hour == 0)
        }
        at = at.plusHours(1)
    }
    return marks
}

/** The sky colour kept visible at night (never darker than the border tone), and dimmed halfway to the background. */
fun tone(argb: Int, dim: Boolean): Int {
    var r = (argb shr 16) and 0xFF; var g = (argb shr 8) and 0xFF; var b = argb and 0xFF
    val lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
    if (lum < 0.2126 * 0x3A + 0.7152 * 0x35 + 0.0722 * 0x30) { r = 0x3A; g = 0x35; b = 0x30 }
    if (dim) { r = (r + 0x1A) / 2; g = (g + 0x18) / 2; b = (b + 0x16) / 2 }
    return (0xFF shl 24) or (r shl 16) or (g shl 8) or b
}

@Composable
private fun Footer() {
    val context = LocalContext.current
    fun open(url: String) = context.startActivity(Intent(Intent.ACTION_VIEW, android.net.Uri.parse(url)))
    Column(Modifier.fillMaxWidth().padding(20.dp)) {
        Text("Made by Bradley Cowdrey. Free. Forever. · bradcowdrey.com ↗", fontSize = 13.sp, color = Palette.muted,
            modifier = Modifier.clickable { open(Palette.WEBSITE) })
        Spacer(Modifier.height(6.dp))
        Text("Terms & Privacy", fontSize = 13.sp, color = Palette.muted, modifier = Modifier.clickable { open(Palette.LEGAL) })
        Spacer(Modifier.height(24.dp))
    }
}

/** Pick a day, then a time (on your clock); every city follows. */
fun pickDate(context: android.content.Context, store: Store) {
    val current = store.moment.atZone(store.home)
    android.app.DatePickerDialog(context, android.R.style.Theme_DeviceDefault_Dialog, { _, y, m, d ->
        android.app.TimePickerDialog(context, android.R.style.Theme_DeviceDefault_Dialog, { _, h, min ->
            val picked = current.withYear(y).withMonth(m + 1).withDayOfMonth(d).withHour(h).withMinute(min).toInstant()
            store.jump(picked.plusSeconds(450))   // nearest quarter-hour
        }, current.hour, current.minute, store.use24h).show()
    }, current.year, current.monthValue - 1, current.dayOfMonth).show()
}

/** The small pin after the My Location row's name. */
@Composable
fun MyLocationMark() {
    Icon(Icons.Filled.LocationOn, contentDescription = "My Location", tint = Palette.muted, modifier = Modifier.padding(start = 4.dp).size(16.dp))
}
