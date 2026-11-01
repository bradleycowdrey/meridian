package com.bradcowdrey.meridian

import android.Manifest
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.semantics.stateDescription
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
import kotlinx.coroutines.launch
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.runtime.snapshotFlow
import androidx.compose.foundation.gestures.snapping.SnapPosition
import androidx.compose.foundation.gestures.snapping.rememberSnapFlingBehavior
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
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
    const val MAC_DOWNLOAD = "https://github.com/bradleycowdrey/meridian/releases/latest/download/Meridian.dmg"
    const val ISSUES = "https://github.com/bradleycowdrey/meridian/issues"
    /** What Share says, as Two Degrees does: the app, what it does here, who made it. */
    const val SHARE_MESSAGE = "Meridian: every time zone at a glance, on your Android phone and its home screen. Free, by Bradley Cowdrey."
    /** Copy a Message to Send: ready to paste into a chat, with where to get it. */
    const val MESSAGE_TO_SEND = "$SHARE_MESSAGE\n\nGet it for Android, iPhone or Mac: $APP_PAGE"
}

class MainActivity : ComponentActivity() {
    private var store: Store? = null

    /** Back in the app (maybe after travelling): refresh My Location. */
    override fun onResume() {
        super.onResume()
        store?.checkTerms()
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
                    if (!store.termsAccepted) TermsScreen(changed = Terms.changed(Store.prefs(applicationContext))) { store.acceptTerms() }
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
        "add" -> MainScreen(store, initialQuery = "san") { route = it }
        "edit" -> MainScreen(store, initialEditing = true) { route = it }
        "settings" -> SettingsScreen(store) { route = "main" }
        "date" -> DateJumpScreen(store) { route = "main" }
        "widgets" -> WidgetShowcase(store)
        else -> MainScreen(store) { route = it }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun MainScreen(store: Store, initialQuery: String = "", initialEditing: Boolean = false, open: (String) -> Unit) {
    val context = LocalContext.current
    // Search to add a city, right above the cards; Edit List (⋯) to reorder and remove in place.
    var query by remember { mutableStateOf(initialQuery) }
    var editing by remember { mutableStateOf(initialEditing) }
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

    fun share(title: String, subject: String, text: String) = context.startActivity(Intent.createChooser(
        Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_SUBJECT, subject).putExtra(Intent.EXTRA_TEXT, text), title))
    var shareMenu by remember { mutableStateOf(false) }

    Scaffold(
        containerColor = Palette.bg,
        topBar = {
            Column {
                CenterAlignedTopAppBar(
                    title = { Text("Meridian", fontWeight = FontWeight.SemiBold) },
                    navigationIcon = {
                        if (editing) TextButton(onClick = { editing = false }) { Text("Done", color = Palette.cream, fontWeight = FontWeight.SemiBold) }
                        // Share, as in Cowdrey.MD: Meridian or this moment, or copy a link or a ready-to-send message.
                        else Box {
                            IconButton(onClick = { shareMenu = true }) { Icon(Icons.Filled.Share, contentDescription = "Share") }
                            DropdownMenu(expanded = shareMenu, onDismissRequest = { shareMenu = false }) {
                                DropdownMenuItem(text = { Text("Share Meridian…") }, onClick = {
                                    shareMenu = false; share("Share Meridian", "Meridian", "${Palette.SHARE_MESSAGE} ${Palette.APP_PAGE}")
                                })
                                DropdownMenuItem(text = { Text("Share This Moment…") }, enabled = store.places.isNotEmpty(), onClick = {
                                    shareMenu = false; share("Share This Moment", "Times for ${TimeMath.fullMoment(store.moment, store.home, store.use24h)}", store.momentText)
                                })
                                HorizontalDivider()
                                DropdownMenuItem(text = { Text("Copy Link") }, onClick = {
                                    shareMenu = false; clipboard.setText(AnnotatedString(Palette.APP_PAGE)); copied = true
                                })
                                DropdownMenuItem(text = { Text("Copy a Message to Send") }, onClick = {
                                    shareMenu = false; clipboard.setText(AnnotatedString(Palette.MESSAGE_TO_SEND)); copied = true
                                })
                            }
                        }
                    },
                    actions = {
                        Box {
                            IconButton(onClick = { menu = true }) { Icon(Icons.Filled.MoreVert, "More") }
                            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                                DropdownMenuItem(text = { Text("Edit List") }, enabled = store.places.isNotEmpty(),
                                    onClick = { menu = false; query = ""; editing = true })
                                HorizontalDivider()
                                DropdownMenuItem(text = { Text("Go to a Time…") }, onClick = { menu = false; open("date") })
                                DropdownMenuItem(text = { Text("Copy This Moment") }, enabled = store.places.isNotEmpty(), onClick = {
                                    menu = false; clipboard.setText(AnnotatedString(store.momentText)); copied = true
                                })
                                HorizontalDivider()
                                DropdownMenuItem(text = { Text("24-Hour Time") }, onClick = { store.updateUse24h(!store.use24h) },
                                    trailingIcon = { Checkbox(checked = store.use24h, onCheckedChange = { store.updateUse24h(it) }) })
                                DropdownMenuItem(text = { Text("Settings") }, onClick = { menu = false; open("settings") })
                                HorizontalDivider()
                                DropdownMenuItem(text = { Text("Get Meridian for Mac") }, onClick = {
                                    menu = false; context.startActivity(Intent(Intent.ACTION_VIEW, android.net.Uri.parse(Palette.MAC_DOWNLOAD)))
                                })
                                DropdownMenuItem(text = { Text("Terms & Privacy") }, onClick = {
                                    menu = false; context.startActivity(Intent(Intent.ACTION_VIEW, android.net.Uri.parse(Palette.LEGAL)))
                                })
                                DropdownMenuItem(text = { Text("Report an Issue") }, onClick = {
                                    menu = false; context.startActivity(Intent(Intent.ACTION_VIEW, android.net.Uri.parse(Palette.ISSUES)))
                                })
                            }
                        }
                    },
                    colors = TopAppBarDefaults.centerAlignedTopAppBarColors(containerColor = Palette.bg,
                        titleContentColor = Palette.primary, navigationIconContentColor = Palette.cream, actionIconContentColor = Palette.cream),
                )
                Box(Modifier.fillMaxWidth().height(3.dp).background(Palette.crimson))
                if (!editing) CitySearchField(query) { query = it }
            }
        },
    ) { padding ->
        if (query.isNotBlank()) {
            SearchResults(store, query, Modifier.padding(padding)) { query = "" }
            return@Scaffold
        }
        LazyColumn(Modifier.fillMaxSize().padding(padding)) {
            stickyHeader {
                MomentHeader(store, copied, editing) { open("date") }
            }
            if (store.places.isEmpty()) item {
                Column(Modifier.fillMaxWidth().padding(vertical = 48.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("No cities yet", fontWeight = FontWeight.SemiBold)
                    Spacer(Modifier.height(10.dp))
                    Text("Search above to add one: a city, an airport code like SFO, or a time zone like PST.",
                        fontSize = 14.sp, color = Palette.muted, textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 32.dp))
                }
            }
            items(store.places, key = { it.id }) { place ->
                var actions by remember { mutableStateOf(false) }
                var work by remember { mutableStateOf(false) }
                // Each city is a card: 16 dp from the screen edges, 12 dp between cards, 16 dp
                // corners (Material 3's large shape) and a hairline edge. Tap or touch and hold a
                // card for its own actions; dragging its day bar still moves every city's time.
                Box(Modifier.padding(horizontal = 16.dp, vertical = 6.dp).clip(RoundedCornerShape(16.dp)).background(Palette.tile)
                    .border(0.5.dp, Palette.border, RoundedCornerShape(16.dp))) {
                    if (editing) EditRow(store, place)
                    else CityRow(store, place, Modifier.combinedClickable(onClickLabel = "Actions for ${place.name}", onClick = { actions = true }, onLongClick = { actions = true }))
                    DropdownMenu(expanded = actions, onDismissRequest = { actions = false }) {
                        DropdownMenuItem(text = { Text("Copy Time") }, onClick = {
                            actions = false
                            clipboard.setText(AnnotatedString("${place.name}: ${TimeMath.fullMoment(store.moment, place.zone, store.use24h)}"))
                            copied = true
                        })
                        DropdownMenuItem(text = { Text("Working Days & Hours") }, onClick = { actions = false; work = true })
                        if (!place.isMyLocation) DropdownMenuItem(text = { Text("Rename") }, onClick = { actions = false; renaming = place })
                        DropdownMenuItem(text = { Text("Remove", color = Color(0xFFFF6B6B)) }, onClick = { actions = false; store.remove(place) })
                    }
                    if (work) WorkHoursDialog(store, place) { work = false }
                }
            }
            item { Footer() }
        }
    }
    renaming?.let { place -> RenameDialog(place, onDone = { name -> if (name != null) store.rename(place, name); renaming = null }) }
}

/** A small "NOW" (or "IN 4 HR 20 MIN") over the date and time, a Now button when away, the meeting planner line. */
@Composable
fun MomentHeader(store: Store, copied: Boolean, editing: Boolean = false, pickDate: () -> Unit) {
    var typing by remember { mutableStateOf(false) }
    if (typing) TypeOffsetDialog(onDone = { minutes -> typing = false; minutes?.let { store.shift(it) } })
    Column(Modifier.fillMaxWidth().background(Palette.bg).padding(start = 16.dp, end = 16.dp, top = 14.dp, bottom = 12.dp)) {
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
            // Type an offset ("+3", "-1.5", "-2:30").
            if (store.places.isNotEmpty() && !editing) {
                Box(Modifier.width(48.dp).height(32.dp).clip(RoundedCornerShape(50)).background(Palette.tile)
                    .border(0.5.dp, Palette.border, RoundedCornerShape(50)).clickable { typing = true },
                    contentAlignment = Alignment.Center) {
                    Text("123", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Palette.secondary)
                }
            }
        }
        // The Now chip below brings you back (no second Now up here); in Edit List the controls step aside.
        if (store.places.isNotEmpty() && !editing) {
            Spacer(Modifier.height(10.dp))
            TimeShifter(store)
        }
    }
}

/**
 * Moves every city through time from the header: a slider from 12 hours back to 12 ahead (in
 * quarter-hours, Now in the middle), one-tap −2/−1/Now/+1/+2 hours, and 123 to type an offset
 * ("+3", "-1.5", "-2:30"). The date picker goes further; the day bars still drag.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TimeShifter(store: Store) {
    Column {
        TimeRuler(store)
        Spacer(Modifier.height(8.dp))
        // −2 · −1 · Now · +1 · +2: Now in the middle, wider, and always easy to find: solid when
        // you've moved away (come back), outlined with the red dot when you're there.
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
            listOf(-2, -1, 0, 1, 2).forEach { preset ->
                if (preset == 0) {
                    Row(Modifier.weight(1.6f).height(44.dp).clip(RoundedCornerShape(50))
                        .background(if (store.isNow) Palette.tile else Palette.cream)
                        .border(1.5.dp, if (store.isNow) Palette.cream else Color.Transparent, RoundedCornerShape(50))
                        .clickable { store.backToNow() },
                        horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
                        if (store.isNow) { Box(Modifier.size(6.dp).clip(CircleShape).background(Palette.crimson)); Spacer(Modifier.width(6.dp)) }
                        Text("Now", fontSize = 17.sp, fontWeight = FontWeight.Bold, color = if (store.isNow) Palette.cream else Palette.bg)
                    }
                } else {
                    val on = store.offsetMinutes == preset * 60
                    Box(Modifier.weight(1f).height(34.dp).clip(RoundedCornerShape(50))
                        .background(if (on) Palette.secondary else Palette.tile)
                        .border(0.5.dp, if (on) Color.Transparent else Palette.border, RoundedCornerShape(50))
                        .clickable { store.shift(preset * 60) },
                        contentAlignment = Alignment.Center) {
                        Text("${if (preset > 0) "+" else "−"}${kotlin.math.abs(preset)} hr",
                            fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = if (on) Palette.bg else Palette.secondary)
                    }
                }
            }
        }
    }
}

/** "+3", "3", "-1.5", "−2:30", "+0:45 hr" -> minutes from now (up to a week either way). */
fun parseOffset(text: String): Int? {
    var t = text.lowercase().replace("−", "-").replace("hours", "").replace("hour", "").replace("hrs", "")
        .replace("hr", "").replace("h", "").replace(" ", "")
    var sign = 1
    if (t.startsWith("-")) { sign = -1; t = t.drop(1) } else if (t.startsWith("+")) t = t.drop(1)
    val minutes = if (":" in t) {
        val parts = t.split(":")
        if (parts.size != 2) return null
        val h = (parts[0].ifEmpty { "0" }).toDoubleOrNull() ?: return null
        val m = parts[1].toDoubleOrNull() ?: return null
        if (m >= 60) return null
        h * 60 + m
    } else (t.replace(",", ".").toDoubleOrNull() ?: return null) * 60
    if (minutes > 7 * 24 * 60) return null
    return sign * minutes.roundToInt()
}

@Composable
private fun TypeOffsetDialog(onDone: (Int?) -> Unit) {
    var text by remember { mutableStateOf("") }
    var invalid by remember { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = { onDone(null) },
        containerColor = Palette.tile,
        title = { Text("Hours from now") },
        text = {
            Column {
                Text("Ahead with + or a plain number, back with −. Hours and minutes work too: 2:30.", fontSize = 13.sp, color = Palette.muted)
                Spacer(Modifier.height(12.dp))
                OutlinedTextField(text, { text = it; invalid = false }, singleLine = true, isError = invalid,
                    placeholder = { Text("+3, -1.5 or -2:30") },
                    supportingText = { if (invalid) Text("That isn't a number of hours") },
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Text, imeAction = ImeAction.Go),
                    keyboardActions = KeyboardActions(onGo = { parseOffset(text)?.let { onDone(it) } ?: run { invalid = true } }))
            }
        },
        confirmButton = { TextButton(onClick = { parseOffset(text)?.let { onDone(it) } ?: run { invalid = true } }) { Text("Go") } },
        dismissButton = { TextButton(onClick = { onDone(null) }) { Text("Cancel") } },
    )
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


/** One city: how it relates to you and its name on the left, its time large and light on the right; then its day bar. */
@Composable
fun CityRow(store: Store, place: Place, modifier: Modifier = Modifier) {
    val moment = store.moment
    val (clock, suffix) = TimeMath.clock(moment, place.zone, store.use24h)
    val shift = TimeMath.dayShift(moment, place.zone, store.home)
    val utc = TimeMath.offsetLabel(TimeMath.offsetSeconds(place.zone, moment))
    // "Off hours", "Weekend" or "Day off" when the city isn't at work.
    val off = if (store.showWorkHours) WorkWeek.offLabel(place, moment, store.workStart, store.workEnd) else null
    // "My Location" on the card for where you are; with the city you're in when this card is
    // another city in the same time zone ("My Location · Boulder" on Denver).
    val here = if (!store.isHere(place)) null
        else store.hereCity?.takeIf { !place.isMyLocation && it != place.name }?.let { "My Location · $it" } ?: "My Location"
    val detail = (TimeMath.relative(moment, place.zone, store.home)
        ?: if (place.zone.id == store.home.id) "Your time" else "Same time") + " · " + utc
    Column(modifier.fillMaxWidth().padding(16.dp)
        .semantics(mergeDescendants = true) { contentDescription = "${place.name}${here?.let { ", $it" } ?: ""}, ${TimeMath.time(moment, place.zone, store.use24h)}, $detail${off?.let { ", ${it.lowercase()}" } ?: ""}" }) {
        Row(verticalAlignment = Alignment.Bottom) {
            Column(Modifier.weight(1f)) {
                Text(detail, fontSize = 13.sp, color = Palette.muted, maxLines = 1)
                Text(place.name, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                // Where you are, on this card rather than a second card for the same place.
                here?.let {
                    Row(Modifier.padding(top = 2.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.LocationOn, contentDescription = null, tint = Palette.cream, modifier = Modifier.size(13.dp))
                        Spacer(Modifier.width(3.dp))
                        Text(it, fontSize = 12.sp, color = Palette.cream)
                    }
                }
                // This city's own note, rather than a list of names in the header.
                if (off != null) OffNote(off, Modifier.padding(top = 2.dp))
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
                store.scrubToQuarterNear(base + minutes.toDouble())
            }
        }) {
        Box(Modifier.fillMaxWidth().height(18.dp), contentAlignment = Alignment.Center) {
            Canvas(Modifier.fillMaxWidth().height(8.dp).clip(RoundedCornerShape(50))) {
                val slices = (hoursShown * 4).toInt()
                val slice = size.width / slices
                for (i in 0 until slices) {
                    val at = start.plusSeconds(i * 900L + 450).atZone(place.zone)
                    val dim = store.showWorkHours && !store.isWorking(place, at.toInstant())
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
    Column(Modifier.fillMaxWidth().padding(16.dp)) {
        Text("Made by Bradley Cowdrey. Free. Forever. · bradcowdrey.com\u00A0↗", fontSize = 13.sp, color = Palette.muted,
            modifier = Modifier.clickable { open(Palette.WEBSITE) })
        Spacer(Modifier.height(6.dp))
        Text("Terms & Privacy", fontSize = 13.sp, color = Palette.muted, modifier = Modifier.clickable { open(Palette.LEGAL) })
        Spacer(Modifier.height(24.dp))
    }
}

/** The small pin after the My Location row's name. */
@Composable
fun MyLocationMark() {
    Icon(Icons.Filled.LocationOn, contentDescription = "My Location", tint = Palette.muted, modifier = Modifier.padding(start = 4.dp).size(16.dp))
}

/** The search field above the cards: type to add a city (results replace the cards). */
@Composable
fun CitySearchField(query: String, onChange: (String) -> Unit) {
    OutlinedTextField(query, onChange, singleLine = true,
        placeholder = { Text("Add a city, SFO, PST, UTC+5", color = Palette.faint) },
        leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null, tint = Palette.faint) },
        trailingIcon = { if (query.isNotEmpty()) IconButton(onClick = { onChange("") }) { Icon(Icons.Filled.Close, "Clear") } },
        shape = RoundedCornerShape(12.dp),
        colors = OutlinedTextFieldDefaults.colors(unfocusedContainerColor = Palette.tile, focusedContainerColor = Palette.tile,
            unfocusedBorderColor = Color.Transparent, focusedBorderColor = Palette.border),
        modifier = Modifier.fillMaxWidth().background(Palette.bg).padding(start = 16.dp, end = 16.dp, top = 10.dp, bottom = 4.dp))
}

/** Search results in place of the cards; tap one to add it. */
@Composable
fun SearchResults(store: Store, query: String, modifier: Modifier, added: () -> Unit) {
    val results = remember(query) { CityDirectory.search(query) }
    LazyColumn(modifier.fillMaxSize()) {
        if (!store.canAdd) item {
            Text("You can keep up to ${Store.MAX_PLACES} cities. Remove one to add another.", color = Palette.muted, modifier = Modifier.padding(16.dp))
        }
        if (results.isEmpty()) item {
            Text("No places match \u201c$query\u201d. Try a city, an airport code like SFO, a time zone like PST, or UTC+5:30.",
                color = Palette.muted, modifier = Modifier.padding(16.dp))
        }
        items(results, key = { it.name + it.zoneId }) { entry ->
            val have = store.contains(entry)
            val zone = runCatching { java.time.ZoneId.of(entry.zoneId) }.getOrNull()
            Row(Modifier.fillMaxWidth().clickable(enabled = !have && store.canAdd) { store.add(entry); added() }
                .padding(horizontal = 20.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(entry.name, fontWeight = FontWeight.SemiBold)
                    Text(WorkWeek.countryName(entry.zoneId) ?: entry.region.replace("_", " "), fontSize = 13.sp, color = Palette.muted)
                }
                if (zone != null) Column(horizontalAlignment = Alignment.End) {
                    Text(TimeMath.time(store.now, zone, store.use24h), color = Palette.secondary)
                    Text(TimeMath.offsetLabel(TimeMath.offsetSeconds(zone, store.now)), fontSize = 13.sp, color = Palette.muted)
                }
                Spacer(Modifier.width(12.dp))
                Icon(if (have) Icons.Filled.Check else Icons.Filled.Add, contentDescription = if (have) "Already added" else "Add",
                    tint = if (have) Palette.faint else Palette.cream)
            }
            HorizontalDivider(Modifier.padding(horizontal = 20.dp), color = Palette.border, thickness = 0.5.dp)
        }
    }
}

/** A card in Edit List: remove on the left, the city, move up and down on the right. */
@Composable
fun EditRow(store: Store, place: Place) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 8.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = { store.remove(place) }) {
            Box(Modifier.size(22.dp).clip(CircleShape).background(Color(0xFFE5484D)), contentAlignment = Alignment.Center) {
                Box(Modifier.width(10.dp).height(2.dp).background(Color.White))
            }
        }
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(place.name, fontSize = 18.sp, fontWeight = FontWeight.SemiBold, maxLines = 1)
                if (store.isHere(place)) MyLocationMark()
            }
            Text(TimeMath.time(store.now, place.zone, store.use24h), fontSize = 13.sp, color = Palette.muted)
        }
        IconButton(onClick = { store.move(place, -1) }, enabled = place != store.places.first()) { Icon(Icons.Filled.KeyboardArrowUp, "Move ${place.name} up") }
        IconButton(onClick = { store.move(place, 1) }, enabled = place != store.places.last()) { Icon(Icons.Filled.KeyboardArrowDown, "Move ${place.name} down") }
    }
}

/** "Off hours", "Weekend" or "Day off", with a moon, as on the iPhone. */
@Composable
fun OffNote(text: String, modifier: Modifier = Modifier) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        Icon(androidx.compose.ui.res.painterResource(R.drawable.ic_moon), contentDescription = null, tint = Palette.muted, modifier = Modifier.size(12.dp))
        Spacer(Modifier.width(5.dp))
        Text(text, fontSize = 12.sp, color = Palette.muted)
    }
}

/**
 * The time ruler: the day as a strip of hours and quarter-hours under a fixed line, as in a
 * camera's zoom dial. Swipe or flick it and it settles on a quarter-hour of the clock (:00, :15,
 * :30, :45), ticking as it passes each one; tap an hour to go there. Two days either way.
 */
@Composable
fun TimeRuler(store: Store) {
    val tick = 14.dp
    val span = 4 * 48
    val nowIndex = Math.floorDiv(store.now.epochSecond, 900L).toInt()
    val selected = if (store.isNow) nowIndex else Math.round(store.moment.epochSecond / 900.0).toInt()
    // Fixed for this screen, so an item keeps its quarter-hour as the clock moves.
    val base = remember { nowIndex - span }
    val listState = rememberLazyListState(initialFirstVisibleItemIndex = (selected - base).coerceAtLeast(0))
    val fling = rememberSnapFlingBehavior(listState, SnapPosition.Center)
    val scope = rememberCoroutineScope()
    val tickPx = with(LocalDensity.current) { tick.toPx() }
    // True while the ruler is being moved to match the time (not by the user).
    val syncing = remember { java.util.concurrent.atomic.AtomicBoolean(false) }
    val centered by remember { derivedStateOf { base + listState.firstVisibleItemIndex + (listState.firstVisibleItemScrollOffset / tickPx).roundToInt() } }

    // The ruler moved: go to its quarter-hour (the one just begun is now).
    LaunchedEffect(Unit) {
        snapshotFlow { centered }.collect { index ->
            if (!listState.isScrollInProgress || syncing.get()) return@collect
            val current = if (store.isNow) Math.floorDiv(store.now.epochSecond, 900L).toInt() else Math.round(store.moment.epochSecond / 900.0).toInt()
            if (index == current) return@collect
            if (index == Math.floorDiv(store.now.epochSecond, 900L).toInt()) store.backToNow()
            else store.scrubToQuarter(java.time.Instant.ofEpochSecond(index * 900L))
        }
    }
    // The time moved some other way (Now, the buttons, a date): bring the ruler along.
    LaunchedEffect(selected) {
        if (!listState.isScrollInProgress && centered != selected) {
            syncing.set(true)
            try { listState.animateScrollToItem((selected - base).coerceIn(0, 4 * span)) } finally { syncing.set(false) }
        }
    }

    BoxWithConstraints(Modifier.fillMaxWidth().height(56.dp)) {
        val side = ((maxWidth - tick) / 2).coerceAtLeast(0.dp)
        LazyRow(state = listState, flingBehavior = fling, contentPadding = PaddingValues(horizontal = side),
            modifier = Modifier.fillMaxSize().semantics { stateDescription = if (store.isNow) "Now" else relative(store) }) {
            items(4 * span + 1) { k ->
                val index = base + k
                RulerTick(java.time.Instant.ofEpochSecond(index * 900L).atZone(store.home), store.use24h,
                    Modifier.width(tick).fillMaxHeight().clickable { scope.launch { listState.animateScrollToItem(k) } })
            }
        }
        // The fixed line: where you are in time.
        Box(Modifier.align(Alignment.TopCenter).padding(top = 22.dp).width(3.dp).height(34.dp)
            .clip(RoundedCornerShape(50)).background(Palette.cream))
        // Fade the ends.
        Box(Modifier.align(Alignment.CenterStart).width(40.dp).fillMaxHeight()
            .background(androidx.compose.ui.graphics.Brush.horizontalGradient(listOf(Palette.bg, Color.Transparent))))
        Box(Modifier.align(Alignment.CenterEnd).width(40.dp).fillMaxHeight()
            .background(androidx.compose.ui.graphics.Brush.horizontalGradient(listOf(Color.Transparent, Palette.bg))))
    }
}

/** One quarter-hour on the ruler: a tall tick and its hour on the hour (the day at midnight), shorter ones between. */
@Composable
private fun RulerTick(at: java.time.ZonedDateTime, use24h: Boolean, modifier: Modifier) {
    val hour = at.hour; val minute = at.minute
    Column(modifier.padding(top = 2.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.height(16.dp).wrapContentWidth(unbounded = true), contentAlignment = Alignment.Center) {
            if (minute == 0) Text(
                if (hour == 0) at.dayOfWeek.getDisplayName(java.time.format.TextStyle.SHORT, java.util.Locale.ENGLISH).uppercase()
                else if (use24h) "%02d".format(hour) else "${if (hour % 12 == 0) 12 else hour % 12}${TimeMath.THIN}${if (hour < 12) "AM" else "PM"}",
                fontSize = 11.sp, maxLines = 1, softWrap = false,
                fontWeight = if (hour == 0) FontWeight.Bold else FontWeight.Medium,
                color = if (hour == 0) Palette.cream else Palette.muted)
        }
        Spacer(Modifier.height(4.dp))
        Box(Modifier.width(if (minute == 0) 2.dp else 1.5.dp).height(if (minute == 0) 20.dp else if (minute == 30) 13.dp else 8.dp)
            .clip(RoundedCornerShape(50)).background(if (minute == 0) Palette.secondary else Palette.faint))
    }
}
