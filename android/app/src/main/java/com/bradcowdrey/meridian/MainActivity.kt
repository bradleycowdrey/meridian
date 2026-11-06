package com.bradcowdrey.meridian

import android.Manifest
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.semantics.stateDescription
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
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
import androidx.compose.ui.focus.focusRequester
import androidx.compose.material.icons.filled.Edit
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Search
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Share
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.onLongClick
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.BaselineShift
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import java.time.Instant
import kotlin.math.roundToInt

/** bradcowdrey.com colours, shared with the widgets, and the Two Degrees tones the app uses inside. */
object Palette {
    val bg = Color(0xFF1A1816)
    val tile = Color(0xFF23201D)
    val border = Color(0xFF3A3530)
    val primary = Color.White
    val secondary = Color(0xFFE0D8D0)
    val muted = Color(0xFFB0A898)
    val faint = Color(0xFF807870)
    /** Widgets, the app icon and the Terms button only. */
    val cream = Color(0xFFFFF1E5)
    /** Widgets and the app icon only: never inside the app. */
    val crimson = Color(0xFF990F3D)
    val black = Color.Black
    val notice = Color(0xFFF2A65A)
    val destructive = Color(0xFFE5484D)
    /** Cards on the flat sheets. Two Degrees uses black 20% over its sky; our sheets are flat, so white. */
    val cardFill = Color(0x14FFFFFF)
    val cardBorder = Color(0x1FFFFFFF)
    val chipOff = Color(0x1FFFFFFF)
    /** The Two Degrees bottom bar. */
    val barBg = Color(0x99101216)
    /** The Two Degrees search field. */
    val searchBg = Color(0xFF1E1E22)
    val sun = Color(0xFFF4B860)
    val moon = Color(0xFFE9DCC8)
    val pickerAccent = Color(0xFF3D74B0)
    val switchOn = Color(0xFF30D158)
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

/** White at a level of the opacity ladder (strong 0.9 … rowFill 0.07). */
fun white(alpha: Float) = Color.White.copy(alpha = alpha)

/** The current text style with tabular figures, so times don't jiggle as they change. */
val tnum: TextStyle
    @Composable get() = LocalTextStyle.current.copy(fontFeatureSettings = "tnum")

/** "9:41" with a small raised "AM" after it, as Two Degrees sets its readings. No suffix in 24-hour time. */
fun clockText(digits: String, suffix: String?): AnnotatedString = buildAnnotatedString {
    withStyle(SpanStyle(fontFeatureSettings = "tnum")) { append(digits) }
    if (suffix != null) {
        withStyle(SpanStyle(fontSize = 0.42.em, baselineShift = BaselineShift(0.5f), fontWeight = FontWeight.Medium)) {
            append(TimeMath.THIN + suffix)
        }
    }
}

/** A section on a sheet, as Two Degrees' cards: a small uppercase caption with its icon, then the content. */
@Composable
fun GlassCard(
    title: String?,
    icon: ImageVector?,
    modifier: Modifier = Modifier,
    padding: Dp = 14.dp,
    spacing: Dp = 10.dp,
    content: @Composable ColumnScope.() -> Unit,
) {
    val shape = RoundedCornerShape(16.dp)
    Column(modifier.fillMaxWidth().clip(shape).background(Palette.cardFill).border(1.dp, Palette.cardBorder, shape).padding(padding),
        verticalArrangement = Arrangement.spacedBy(spacing)) {
        if (title != null) {
            Row(Modifier.semantics { heading() }, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                if (icon != null) Icon(icon, contentDescription = null, tint = white(0.6f), modifier = Modifier.size(14.dp))
                Text(title.uppercase(), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = white(0.6f), maxLines = 1)
            }
        }
        content()
    }
}

/** A capsule chip: white with black text when it's the one chosen, faint white otherwise. No strokes. */
@Composable
fun PillChip(
    title: String,
    on: Boolean,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    description: String? = null,
    selectable: Boolean = true,
    onClick: () -> Unit,
) {
    val fg = if (on) Palette.black else Palette.primary
    Row(modifier.minimumInteractiveComponentSize().heightIn(min = 32.dp).clip(RoundedCornerShape(50))
        .background(if (on) Palette.primary else Palette.chipOff)
        .clickable(onClick = onClick)
        .semantics { if (selectable) selected = on; if (description != null) contentDescription = description }
        .padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
        if (icon != null) {
            Icon(icon, contentDescription = null, tint = fg, modifier = Modifier.size(16.dp))
            Spacer(Modifier.width(4.dp))
        }
        Text(title, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = fg, maxLines = 1, softWrap = false)
    }
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
        // Screenshot mode (CI): --ez screenshots true --es screen main|travel|add|edit|settings|date|find|widgets|terms
        val demo = intent.getBooleanExtra("screenshots", false)
        val screen = intent.getStringExtra("screen") ?: "main"
        val store = Store(applicationContext, demo = demo && screen != "terms")
        this.store = store
        setContent {
            MaterialTheme(colorScheme = darkColorScheme(
                // White highlights inside the app, as in Two Degrees (crimson stays on the widgets and icon).
                background = Palette.bg, surface = Palette.bg, primary = Color.White, onPrimary = Color.Black,
                surfaceContainer = Palette.tile, surfaceContainerHigh = Palette.tile, onSurface = Palette.primary,
                onSurfaceVariant = Palette.muted, outlineVariant = Palette.cardBorder,
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
            shape = RoundedCornerShape(16.dp),
        )
    }
    BackHandler(enabled = route != "main") { route = "main" }
    when (route) {
        "add" -> MainScreen(store, initialQuery = "san") { route = it }
        "edit" -> MainScreen(store, initialEditing = true) { route = it }
        "settings" -> SettingsScreen(store) { route = "main" }
        "date" -> DateJumpScreen(store) { route = "main" }
        "find" -> FindTimeScreen(store) { route = "main" }
        "widgets" -> WidgetShowcase(store)
        else -> MainScreen(store) { route = it }
    }
}

@Composable
fun MainScreen(store: Store, initialQuery: String = "", initialEditing: Boolean = false, open: (String) -> Unit) {
    val context = LocalContext.current
    // + in the top bar shows the search field until a city is added or ✓; the pencil turns on Edit
    // List (reorder and remove in place) until ✓.
    var query by remember { mutableStateOf(initialQuery) }
    var adding by remember { mutableStateOf(initialQuery.isNotEmpty()) }
    var editing by remember { mutableStateOf(initialEditing) }
    fun closeSearch() { query = ""; adding = false }
    val clipboard = LocalClipboardManager.current
    val haptics = LocalHapticFeedback.current
    var menu by remember { mutableStateOf(false) }
    var copied by remember { mutableStateOf(false) }
    var renaming by remember { mutableStateOf<Place?>(null) }
    var personFor by remember { mutableStateOf<Place?>(null) }
    var groupsFor by remember { mutableStateOf<Place?>(null) }

    LaunchedEffect(store.userMoves) {
        if (store.userMoves > 0) haptics.performHapticFeedback(
            if (store.onTheHour) HapticFeedbackType.LongPress else HapticFeedbackType.TextHandleMove)
    }
    LaunchedEffect(copied) { if (copied) { delay(1800); copied = false } }

    // Off the main thread: the first search reads the 34,000-city list, which takes a moment.
    val searched by produceState<Pair<String, List<CityEntry>>?>(null, query) {
        if (query.isNotBlank()) value = query to kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) { CityDirectory.search(query) }
    }
    // Search on the keyboard: add the first result not already on the list.
    fun submit() {
        val found = searched ?: return
        if (found.first != query || !store.canAdd) return
        found.second.firstOrNull { !store.contains(it) }?.let { store.add(it); closeSearch() }
    }

    fun share(title: String, subject: String, text: String) = context.startActivity(Intent.createChooser(
        Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_SUBJECT, subject).putExtra(Intent.EXTRA_TEXT, text), title))
    var shareMenu by remember { mutableStateOf(false) }
    // The ruler and the hour buttons, in a bar at the bottom as in Two Degrees.
    val showBar = !adding && !editing && store.places.isNotEmpty()

    Scaffold(
        containerColor = Palette.black,
        topBar = {
            Column(Modifier.fillMaxWidth().background(Palette.black).statusBarsPadding()) {
                Row(Modifier.fillMaxWidth().height(48.dp).padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
                    // Share, as in Cowdrey.MD: Meridian or this moment, or copy a link or a ready-to-send message.
                    Box {
                        IconButton(onClick = { shareMenu = true }) { Icon(Icons.Filled.Share, contentDescription = "Share", tint = Palette.primary) }
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
                    Spacer(Modifier.weight(1f))
                    ListControls(adding = adding, editing = editing, canAdd = store.canAdd, canEdit = store.places.isNotEmpty(),
                        onAdd = { if (adding) closeSearch() else { editing = false; adding = true } },
                        onEdit = { if (adding) closeSearch(); editing = !editing })
                    Box {
                        IconButton(onClick = { menu = true }) { Icon(Icons.Filled.MoreVert, "More", tint = Palette.primary) }
                        DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                            DropdownMenuItem(text = { Text("Edit List") }, enabled = store.places.isNotEmpty(), onClick = {
                                menu = false; if (adding) closeSearch(); editing = true
                            })
                            DropdownMenuItem(text = { Text("Find a Time…") }, enabled = store.places.isNotEmpty(), onClick = { menu = false; open("find") })
                            DropdownMenuItem(text = { Text("Go to a Time…") }, onClick = { menu = false; open("date") })
                            DropdownMenuItem(text = { Text("Copy This Moment") }, enabled = store.places.isNotEmpty(), onClick = {
                                menu = false; clipboard.setText(AnnotatedString(store.momentText)); copied = true
                            })
                            HorizontalDivider()
                            DropdownMenuItem(text = { Text("24-Hour Time") }, onClick = { store.updateUse24h(!store.use24h) },
                                trailingIcon = { Checkbox(checked = store.use24h, onCheckedChange = { store.updateUse24h(it) },
                                    colors = CheckboxDefaults.colors(checkedColor = Palette.primary, checkmarkColor = Palette.black, uncheckedColor = white(0.6f))) })
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
                }
                Text("Meridian", fontSize = 32.sp, lineHeight = 38.sp, fontWeight = FontWeight.SemiBold, color = Palette.primary, maxLines = 1,
                    modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 4.dp).semantics { heading() })
                if (adding) CitySearchField(query, focus = !store.demo, onSearch = { submit() }) { query = it }
                else Spacer(Modifier.height(4.dp))
            }
        },
        bottomBar = {
            if (showBar) {
                Column(Modifier.fillMaxWidth().background(Palette.barBg).navigationBarsPadding()) {
                    HorizontalDivider(thickness = 0.5.dp, color = white(0.15f))
                    Box(Modifier.padding(top = 8.dp, bottom = 4.dp)) { TimeShifter(store) }
                }
            }
        },
    ) { padding ->
        Box(Modifier.fillMaxSize()) {
            if (adding) {
                if (query.isNotBlank()) SearchResults(store, query, searched, Modifier.padding(padding)) { closeSearch() }
                else Text("Type a city, an airport code like SFO, a time zone like PST, or an offset like UTC+5:30.",
                    fontSize = 15.sp, color = white(0.6f), modifier = Modifier.padding(padding).padding(16.dp))
            } else {
                // Everyone or one group, and clocks about to change, above the cards (not in Edit List,
                // which shows every card so removing and moving follow the full list).
                val groups = store.groups
                val changes = if (editing) emptyList() else store.clockChanges
                // The cards scroll under the translucent bottom bar, as in Two Degrees.
                LazyColumn(Modifier.fillMaxSize(), contentPadding = padding) {
                    if (!editing && groups.isNotEmpty()) item(key = "group-filter") {
                        GroupFilter(store, groups)
                    }
                    items(changes, key = { "clock-" + it.key }) { change ->
                        ClockNotice(change, store.use24h) { store.dismiss(change) }
                    }
                    if (store.places.isEmpty()) item {
                        Column(Modifier.fillMaxWidth().padding(vertical = 40.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                            Text("No cities yet", fontSize = 20.sp, fontWeight = FontWeight.Medium, color = Palette.primary)
                            Spacer(Modifier.height(8.dp))
                            Text("Tap + at the top to add one: a city, an airport code like SFO, or a time zone like PST.",
                                fontSize = 15.sp, color = white(0.6f), textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 32.dp))
                        }
                    }
                    items(if (editing) store.places else store.visiblePlaces, key = { it.id }) { place ->
                        var actions by remember { mutableStateOf(false) }
                        var work by remember { mutableStateOf(false) }
                        // Each city is a card on its own sky (Two Degrees' sky for day, twilight or night
                        // there), top to bottom: 16 dp from the screen edges, 10 dp between cards, 16 dp
                        // corners. Touch and hold a card for its own actions (a tap does nothing, so
                        // scrolling never opens them by accident); dragging its day bar still moves every
                        // city's time.
                        val (skyTop, skyBottom) = Sky.colors(Sky.phase(place, store.moment))
                        val top by animateColorAsState(skyTop, tween(600), label = "sky top")
                        val bottom by animateColorAsState(skyBottom, tween(600), label = "sky bottom")
                        val shape = RoundedCornerShape(16.dp)
                        Box(Modifier.padding(horizontal = 16.dp, vertical = 5.dp).fillMaxWidth().clip(shape)
                            .background(Brush.verticalGradient(listOf(top, bottom)))
                            .then(if (store.isHere(place)) Modifier.border(1.5.dp, white(0.5f), shape) else Modifier)) {
                            if (editing) EditRow(store, place)
                            else {
                                CityRow(store, place, Modifier
                                    .pointerInput(place.id) {
                                        detectTapGestures(onLongPress = {
                                            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                                            actions = true
                                        })
                                    }
                                    .semantics { onLongClick(label = "Actions for ${place.title}") { actions = true; true } })
                            }
                            DropdownMenu(expanded = actions, onDismissRequest = { actions = false }) {
                                DropdownMenuItem(text = { Text("Copy Time") }, onClick = {
                                    actions = false
                                    clipboard.setText(AnnotatedString("${place.fullName}: ${TimeMath.fullMoment(store.moment, place.zone, store.use24h)}"))
                                    copied = true
                                })
                                DropdownMenuItem(text = { Text("Working Days & Hours") }, onClick = { actions = false; work = true })
                                DropdownMenuItem(text = { Text("Add a Person Here") }, enabled = store.canAdd, onClick = { actions = false; personFor = place })
                                DropdownMenuItem(text = { Text("Groups") }, onClick = { actions = false; groupsFor = place })
                                if (!place.isMyLocation || place.person != null) DropdownMenuItem(text = { Text("Rename") }, onClick = { actions = false; renaming = place })
                                DropdownMenuItem(text = { Text("Remove", color = Palette.destructive) }, onClick = { actions = false; store.remove(place) })
                            }
                            if (work) WorkHoursDialog(store, place) { work = false }
                        }
                    }
                    item { Footer() }
                }
            }
            // "Copied": 8 dp above the bottom bar, or at the bottom when the bar is hidden.
            if (copied) CopiedPill(Modifier.align(Alignment.BottomCenter).padding(bottom = padding.calculateBottomPadding() + 8.dp))
        }
    }
    renaming?.let { place -> RenameDialog(place, onDone = { name -> if (name != null) store.rename(place, name); renaming = null }) }
    personFor?.let { place ->
        val city = if (place.isMyLocation) store.hereCity ?: "My Location" else place.name
        AddPersonDialog(city) { name -> if (name != null) store.addPerson(name, place); personFor = null }
    }
    groupsFor?.let { place -> GroupsDialog(store, place) { groupsFor = null } }
}

/** "✓ Copied", briefly, after copying. */
@Composable
private fun CopiedPill(modifier: Modifier) {
    Row(modifier.clip(RoundedCornerShape(50)).background(Palette.tile).padding(horizontal = 12.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Icon(Icons.Filled.Check, contentDescription = null, tint = Palette.primary, modifier = Modifier.size(14.dp))
        Spacer(Modifier.width(6.dp))
        Text("Copied", fontSize = 13.sp, fontWeight = FontWeight.Medium, color = Palette.primary)
    }
}

/** Everyone, or one group: chips above the cards. */
@Composable
fun GroupFilter(store: Store, groups: List<String>) {
    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        PillChip("Everyone", store.groupFilter == null) { store.updateGroupFilter(null) }
        groups.forEach { group -> PillChip(group, store.groupFilter == group) { store.updateGroupFilter(group) } }
    }
}

/** A city's clocks change soon: when, and how far it will be from you afterwards. Closed with ×. */
@Composable
fun ClockNotice(change: ClockChange, use24h: Boolean, onClose: () -> Unit) {
    val shape = RoundedCornerShape(16.dp)
    val headline = change.headline(use24h)
    val detail = change.detail
    Row(Modifier.padding(horizontal = 16.dp, vertical = 5.dp).fillMaxWidth().clip(shape)
        .background(Palette.notice.copy(alpha = 0.22f)).border(1.dp, Palette.notice.copy(alpha = 0.7f), shape)
        .padding(start = 14.dp, top = 14.dp, bottom = 14.dp, end = 4.dp)
        .semantics(mergeDescendants = true) { contentDescription = listOfNotNull(headline, detail).joinToString(" ") },
        verticalAlignment = Alignment.Top) {
        Icon(Icons.Filled.Refresh, contentDescription = null, tint = Palette.notice, modifier = Modifier.padding(top = 2.dp).size(18.dp))
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(headline, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = Palette.primary)
            if (detail != null) {
                Spacer(Modifier.height(3.dp))
                Text(detail, fontSize = 13.sp, color = white(0.75f))
            }
        }
        IconButton(onClick = onClose, modifier = Modifier.size(44.dp)) {
            Icon(Icons.Filled.Close, contentDescription = "Close", tint = white(0.6f), modifier = Modifier.size(20.dp))
        }
    }
}

/**
 * Moves every city through time from the bottom bar: the ruler (quarter-hours, two days either way)
 * and one-tap −2/−1/Now/+1/+2 hours. The date picker goes further; the day bars still drag.
 */
@Composable
fun TimeShifter(store: Store) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        TimeRuler(store)
        // −2 · −1 · Now · +1 · +2: Now in the middle, wider. Exactly one is white: where you are.
        Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically) {
            listOf(-2, -1, 0, 1, 2).forEach { preset ->
                val on = if (preset == 0) store.isNow else store.offsetMinutes == preset * 60
                // A 34 dp capsule in a 44 dp row; the touch target reaches past the capsule.
                Box(Modifier.weight(if (preset == 0) 1.6f else 1f).height(44.dp), contentAlignment = Alignment.Center) {
                    val pill = Modifier.fillMaxWidth().heightIn(min = 34.dp).clip(RoundedCornerShape(50))
                        .background(if (on) Palette.primary else Palette.chipOff)
                    if (preset == 0) {
                        Box(pill.clickable(onClickLabel = "Back to now") { store.backToNow() }, contentAlignment = Alignment.Center) {
                            Text("Now", fontSize = 15.sp, fontWeight = FontWeight.Medium, color = if (on) Palette.black else Palette.primary,
                                maxLines = 1, softWrap = false)
                        }
                    } else {
                        Box(pill.clickable { store.shift(preset * 60) }
                            .semantics { contentDescription = "${kotlin.math.abs(preset)} ${if (kotlin.math.abs(preset) == 1) "hour" else "hours"} ${if (preset > 0) "from now" else "ago"}" },
                            contentAlignment = Alignment.Center) {
                            Text("${if (preset > 0) "+" else "−"}${kotlin.math.abs(preset)} hr", style = tnum,
                                fontSize = 15.sp, fontWeight = FontWeight.Medium, color = if (on) Palette.black else Palette.primary,
                                maxLines = 1, softWrap = false)
                        }
                    }
                }
            }
        }
    }
}


/** "Today", "Tomorrow", "Yesterday" or "Tue 9 Jun": the city's day at the moment shown, against your today. */
private fun dayLine(store: Store, place: Place, moment: Instant): String {
    val there = moment.atZone(place.zone).toLocalDate()
    val n = there.toEpochDay() - store.now.atZone(store.home).toLocalDate().toEpochDay()
    return when (n) {
        0L -> "Today"
        1L -> "Tomorrow"
        -1L -> "Yesterday"
        else -> there.format(java.time.format.DateTimeFormatter.ofPattern("EEE d MMM", java.util.Locale.ENGLISH))
    }
}

/**
 * One city, as a Two Degrees card: its name and how it relates to you on the left, its time large and
 * light on the right with its day beneath; work and the sun; then its day bar.
 */
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
        else store.hereCity?.takeIf { !place.isMyLocation && place.person == null && it != place.name }?.let { "My Location · $it" } ?: "My Location"
    // Your own city on another day (a date you went to) shows that date instead of "Your time".
    val otherDay = place.zone.id == store.home.id && moment.atZone(store.home).toLocalDate() != store.now.atZone(store.home).toLocalDate()
    val relation = TimeMath.relative(moment, place.zone, store.home)
        ?: if (otherDay) moment.atZone(store.home).format(java.time.format.DateTimeFormatter.ofPattern("EEE d MMM", java.util.Locale.ENGLISH))
        else if (place.zone.id == store.home.id) "Your time" else "Same time"
    // "My Location · UTC−7" on the card for where you are.
    // A person's card names their city first: "Lisbon · +8 hr · UTC+1".
    val city = if (place.person != null) "${place.name} · " else ""
    val detail = city + (here?.let { if (relation == "Your time" || relation == "Same time") it else "$it · $relation" } ?: relation) + " · " + utc
    // "Working", or "Off hours" / "Weekend" / "Day off" (when that setting is on).
    val work = if (store.showWorkHours) off ?: "Working" else null
    // "Sets 4:59 PM" while the sun is up there, "Rises 6:27 AM" while it's down.
    // At the city itself when the card knows where it is, else its time zone's city.
    val phase = Sun.phase(place, moment)
    val sun = when (val p = phase) {
        is Sun.Phase.Day -> "Sets ${TimeMath.time(p.sets, place.zone, store.use24h)}"
        is Sun.Phase.Night -> "Rises ${TimeMath.time(p.rises, place.zone, store.use24h)}"
        Sun.Phase.AllDay -> "Sun all day"
        Sun.Phase.AllNight -> "Polar night"
        null -> null
    }
    val sunUp = phase is Sun.Phase.Day || phase == Sun.Phase.AllDay
    val dayNote = when (shift) { 0 -> null; 1 -> "tomorrow there"; -1 -> "yesterday there"; else -> "${kotlin.math.abs(shift)} days ${if (shift > 0) "ahead" else "behind"}" }
    Column(modifier.fillMaxWidth().padding(14.dp)
        .semantics(mergeDescendants = true) {
            contentDescription = listOfNotNull(place.title, place.person?.let { place.name }, TimeMath.time(moment, place.zone, store.use24h), detail, dayNote, work, sun?.let { "sun ${it.lowercase()}" }).joinToString(", ")
        }) {
        Row(verticalAlignment = Alignment.Top) {
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    // Where you are, on this card rather than a second card for the same place.
                    if (here != null) {
                        Icon(Icons.Filled.LocationOn, contentDescription = null, tint = Palette.primary, modifier = Modifier.size(14.dp))
                        Spacer(Modifier.width(6.dp))
                    }
                    Text(place.title, fontSize = 22.sp, lineHeight = 28.sp, fontWeight = FontWeight.SemiBold, color = Palette.primary,
                        maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                Text(detail, style = tnum, fontSize = 14.sp, fontWeight = FontWeight.Medium, color = white(0.85f),
                    maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
            Spacer(Modifier.width(8.dp))
            // The time never truncates: it is measured first, and the name gives way.
            Column(horizontalAlignment = Alignment.End) {
                Text(clockText(clock, suffix), fontSize = 44.sp, lineHeight = 46.sp, fontWeight = FontWeight.Light,
                    color = Palette.primary, maxLines = 1, softWrap = false)
                Text(dayLine(store, place, moment), fontSize = 15.sp, fontWeight = FontWeight.Medium, color = white(0.8f), maxLines = 1)
            }
        }
        Spacer(Modifier.height(8.dp))
        // Work on the left, the sun on the right; always there, so every card is the same height.
        Row(Modifier.fillMaxWidth().heightIn(min = 20.dp), verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween) {
            if (work != null) {
                StatusNote(work, if (off == null) R.drawable.ic_briefcase else R.drawable.ic_moon,
                    if (off == null) white(0.85f) else Palette.moon, Modifier.weight(1f, fill = false))
                Spacer(Modifier.width(8.dp))
            } else Spacer(Modifier.width(0.dp))
            if (sun != null) StatusNote(sun, if (sunUp) R.drawable.ic_sun else R.drawable.ic_sunrise, Palette.sun)
        }
        Spacer(Modifier.height(10.dp))
        DayBar(store, place)
    }
}

/**
 * Twelve hours of a city's sky in one slim bar (six before the selected moment, six after), brighter
 * by day and dimmer outside working hours, a white tick at midnight, a white knob at the selected
 * moment, and the city's hours labelled underneath. Drag it to move through time; tap to go to that hour.
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
            Canvas(Modifier.fillMaxWidth().height(6.dp).clip(RoundedCornerShape(50))) {
                // Quarter-hour slices on whole pixels, edge to edge with no overlap, so no seams show.
                val slices = (hoursShown * 4).toInt()
                val w = size.width
                for (i in 0 until slices) {
                    val x0 = (i * w / slices).roundToInt()
                    val x1 = ((i + 1) * w / slices).roundToInt()
                    if (x1 <= x0) continue
                    val at = start.plusSeconds(i * 900L + 450).atZone(place.zone)
                    val dim = store.showWorkHours && !store.isWorking(place, at.toInstant())
                    val fill = Color(DayColor.at(at.hour + at.minute / 60.0))
                    val alpha = ((0.15f + 0.7f * fill.luminance()) * (if (dim) 0.5f else 1f)).coerceIn(0f, 1f)
                    drawRect(white(alpha), topLeft = Offset(x0.toFloat(), 0f), size = Size((x1 - x0).toFloat(), size.height))
                }
            }
            // Midnight, taller than the bar so it isn't clipped to it.
            Canvas(Modifier.fillMaxWidth().height(12.dp)) {
                val line = 1.5.dp.toPx()
                marks.filter { it.midnight }.forEach {
                    val x = it.fraction * size.width
                    drawRect(white(0.9f), topLeft = Offset(x - line / 2, 0f), size = Size(line, size.height))
                }
            }
            Box(Modifier.size(14.dp).clip(CircleShape).background(Palette.primary).border(1.5.dp, Palette.black.copy(alpha = 0.35f), CircleShape))
        }
        Spacer(Modifier.height(1.dp))
        Layout(content = {
            marks.forEach {
                Text(it.label, fontSize = 11.sp, lineHeight = 12.sp, fontWeight = if (it.midnight) FontWeight.SemiBold else FontWeight.Medium,
                    color = if (it.midnight) Palette.primary else white(0.6f), maxLines = 1)
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

/** The widgets' hour tiles: the sky colour kept visible at night (never darker than the border tone), and dimmed halfway to the background. */
fun tone(argb: Int, dim: Boolean): Int {
    var r = (argb shr 16) and 0xFF; var g = (argb shr 8) and 0xFF; var b = argb and 0xFF
    val lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
    if (lum < 0.2126 * 0x3A + 0.7152 * 0x35 + 0.0722 * 0x30) { r = 0x3A; g = 0x35; b = 0x30 }
    if (dim) { r = (r + 0x1A) / 2; g = (g + 0x18) / 2; b = (b + 0x16) / 2 }
    return (0xFF shl 24) or (r shl 16) or (g shl 8) or b
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
fun TypeOffsetDialog(onDone: (Int?) -> Unit) {
    var text by remember { mutableStateOf("") }
    var invalid by remember { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = { onDone(null) },
        containerColor = Palette.tile,
        shape = RoundedCornerShape(16.dp),
        title = { Text("Hours from now") },
        text = {
            Column {
                Text("Ahead with + or a plain number, back with −. Hours and minutes work too: 2:30.", fontSize = 13.sp, color = white(0.6f))
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


/** At the end of the list, as Two Degrees' footer: who made it, and the terms. */
@Composable
private fun Footer() {
    val context = LocalContext.current
    fun open(url: String) = context.startActivity(Intent(Intent.ACTION_VIEW, android.net.Uri.parse(url)))
    Column(Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 8.dp, bottom = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("Made by Bradley Cowdrey. Free. Forever. · bradcowdrey.com ↗", fontSize = 13.sp, color = white(0.6f),
            textAlign = TextAlign.Center, modifier = Modifier.clickable { open(Palette.WEBSITE) })
        Text("Terms & Privacy", fontSize = 13.sp, color = white(0.6f), modifier = Modifier.clickable { open(Palette.LEGAL) })
    }
}

/** The small pin after the My Location row's name. */
@Composable
fun MyLocationMark() {
    Icon(Icons.Filled.LocationOn, contentDescription = "My Location", tint = Palette.primary, modifier = Modifier.padding(start = 4.dp).size(12.dp))
}

/** The search field under the title, as in Two Degrees: type to add a city (results replace the cards). */
@Composable
fun CitySearchField(query: String, focus: Boolean = true, onSearch: () -> Unit = {}, onChange: (String) -> Unit) {
    val focusRequester = remember { androidx.compose.ui.focus.FocusRequester() }
    LaunchedEffect(Unit) { if (focus) runCatching { focusRequester.requestFocus() } }
    OutlinedTextField(query, onChange, singleLine = true,
        placeholder = { Text("City, SFO, PST, UTC+5", color = white(0.5f)) },
        leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null, tint = white(0.6f)) },
        trailingIcon = { if (query.isNotEmpty()) IconButton(onClick = { onChange("") }) { Icon(Icons.Filled.Close, "Clear", tint = Palette.primary) } },
        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Search),
        keyboardActions = KeyboardActions(onSearch = { onSearch() }),
        shape = RoundedCornerShape(12.dp),
        colors = OutlinedTextFieldDefaults.colors(unfocusedContainerColor = Palette.searchBg, focusedContainerColor = Palette.searchBg,
            unfocusedBorderColor = Color.Transparent, focusedBorderColor = Color.Transparent, cursorColor = Palette.primary),
        modifier = Modifier.fillMaxWidth().padding(start = 16.dp, end = 16.dp, top = 4.dp, bottom = 8.dp)
            .then(Modifier.focusRequester(focusRequester)))
}

/** Search results in place of the cards; tap one to add it. */
@Composable
fun SearchResults(store: Store, query: String, searched: Pair<String, List<CityEntry>>?, modifier: Modifier, added: () -> Unit) {
    val results = searched?.second.orEmpty()
    val ready = searched?.first == query
    LazyColumn(modifier.fillMaxSize()) {
        if (!store.canAdd) item {
            Text("You can keep up to ${Store.MAX_PLACES} cities. Remove one to add another.", fontSize = 15.sp, color = white(0.6f), modifier = Modifier.padding(16.dp))
        }
        if (!ready && results.isEmpty()) item {
            Text("Searching…", fontSize = 15.sp, color = white(0.6f), modifier = Modifier.padding(16.dp))
        }
        if (ready && results.isEmpty()) item {
            Text("No places match “$query”. Try a city, an airport code like SFO, a time zone like PST, or UTC+5:30.",
                fontSize = 15.sp, color = white(0.6f), modifier = Modifier.padding(16.dp))
        }
        items(results, key = { it.id }) { entry ->
            val have = store.contains(entry)
            val zone = runCatching { java.time.ZoneId.of(entry.zoneId) }.getOrNull()
            Row(Modifier.fillMaxWidth().clickable(enabled = !have && store.canAdd, onClickLabel = "Add") { store.add(entry); added() }
                .padding(horizontal = 16.dp, vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text(entry.name, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = Palette.primary,
                        maxLines = 1, overflow = TextOverflow.Ellipsis)
                    // "Colorado, United States" for a city from the world list; else the zone's country.
                    Text(if (entry.countryCode != null) entry.region else WorkWeek.countryName(entry.zoneId) ?: entry.region.replace("_", " "),
                        fontSize = 14.sp, color = white(0.6f), maxLines = 1, overflow = TextOverflow.Ellipsis)
                }
                if (zone != null) Column(horizontalAlignment = Alignment.End) {
                    Text(TimeMath.time(store.now, zone, store.use24h), style = tnum, fontSize = 17.sp, color = Palette.primary, maxLines = 1)
                    Text(TimeMath.offsetLabel(TimeMath.offsetSeconds(zone, store.now)), fontSize = 13.sp, color = white(0.6f), maxLines = 1)
                }
                if (have) {
                    Spacer(Modifier.width(12.dp))
                    Icon(Icons.Filled.Check, contentDescription = "Already added", tint = white(0.6f))
                }
            }
            HorizontalDivider(Modifier.padding(horizontal = 16.dp), color = white(0.1f))
        }
    }
}

/** A card in Edit List: remove on the left, the city, move up and down on the right. */
@Composable
fun EditRow(store: Store, place: Place) {
    Row(Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(horizontal = 4.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = { store.remove(place) }) {
            Box(Modifier.size(22.dp).clip(CircleShape).background(Palette.destructive), contentAlignment = Alignment.Center) {
                Box(Modifier.width(10.dp).height(2.dp).background(Color.White))
            }
        }
        Column(Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(place.title, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = Palette.primary,
                    maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                if (store.isHere(place)) MyLocationMark()
            }
            Text(TimeMath.time(store.now, place.zone, store.use24h), style = tnum, fontSize = 17.sp, color = Palette.primary, maxLines = 1)
        }
        IconButton(onClick = { store.move(place, -1) }, enabled = place != store.places.first()) {
            Icon(Icons.Filled.KeyboardArrowUp, "Move ${place.title} up", tint = if (place != store.places.first()) Palette.primary else white(0.35f))
        }
        IconButton(onClick = { store.move(place, 1) }, enabled = place != store.places.last()) {
            Icon(Icons.Filled.KeyboardArrowDown, "Move ${place.title} down", tint = if (place != store.places.last()) Palette.primary else white(0.35f))
        }
    }
}

/** A status on a card: a small tinted icon and its words ("Working", "Off hours", "Sets 4:59 PM"). */
@Composable
fun StatusNote(
    text: String,
    icon: Int,
    iconTint: Color,
    modifier: Modifier = Modifier,
    color: Color = white(0.85f),
    fontSize: TextUnit = 14.sp,
) {
    Row(modifier, verticalAlignment = Alignment.CenterVertically) {
        Icon(androidx.compose.ui.res.painterResource(icon), contentDescription = null, tint = iconTint, modifier = Modifier.size(13.dp))
        Spacer(Modifier.width(4.dp))
        Text(text, fontSize = fontSize, fontWeight = FontWeight.Medium, color = color, maxLines = 1, overflow = TextOverflow.Ellipsis)
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

    BoxWithConstraints(Modifier.fillMaxWidth().height(48.dp)) {
        val side = ((maxWidth - tick) / 2).coerceAtLeast(0.dp)
        LazyRow(state = listState, flingBehavior = fling, contentPadding = PaddingValues(horizontal = side),
            modifier = Modifier.fillMaxSize()
                // Fade the ends (a mask, so it works over the translucent bar).
                .graphicsLayer(compositingStrategy = CompositingStrategy.Offscreen)
                .drawWithContent {
                    drawContent()
                    drawRect(Brush.horizontalGradient(0f to Color.Transparent, 0.12f to Color.Black,
                        0.88f to Color.Black, 1f to Color.Transparent), blendMode = BlendMode.DstIn)
                }
                .semantics { stateDescription = if (store.isNow) "Now" else relative(store) }) {
            items(4 * span + 1) { k ->
                val index = base + k
                RulerTick(java.time.Instant.ofEpochSecond(index * 900L).atZone(store.home), store.use24h,
                    Modifier.width(tick).fillMaxHeight().clickable { scope.launch { listState.animateScrollToItem(k) } })
            }
        }
        // The fixed line: where you are in time.
        Box(Modifier.align(Alignment.TopCenter).padding(top = 16.dp).width(3.dp).height(30.dp)
            .clip(RoundedCornerShape(50)).background(Palette.primary))
    }
}

/** One quarter-hour on the ruler: a tall tick and its hour on the hour (the day at midnight), shorter ones between. */
@Composable
private fun RulerTick(at: java.time.ZonedDateTime, use24h: Boolean, modifier: Modifier) {
    val hour = at.hour; val minute = at.minute
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.height(14.dp).wrapContentWidth(unbounded = true), contentAlignment = Alignment.Center) {
            if (minute == 0) Text(
                if (hour == 0) at.dayOfWeek.getDisplayName(java.time.format.TextStyle.SHORT, java.util.Locale.ENGLISH).uppercase()
                else if (use24h) "%02d".format(hour) else "${if (hour % 12 == 0) 12 else hour % 12}${TimeMath.THIN}${if (hour < 12) "AM" else "PM"}",
                fontSize = 11.sp, lineHeight = 12.sp, maxLines = 1, softWrap = false,
                fontWeight = if (hour == 0) FontWeight.SemiBold else FontWeight.Medium,
                color = if (hour == 0) Palette.primary else white(0.6f))
        }
        Spacer(Modifier.height(2.dp))
        Box(Modifier.width(if (minute == 0) 1.5.dp else 1.dp)
            .height(if (minute == 0) 18.dp else if (minute == 30) 12.dp else 7.dp)
            .background(white(if (minute == 0) 0.6f else if (minute == 30) 0.35f else 0.25f)))
    }
}

/**
 * + and the pencil in one capsule, as in Two Degrees and Meridian for Mac: + shows the search
 * field, the pencil turns on Edit List; whichever is on shows ✓ to finish.
 */
@Composable
fun ListControls(adding: Boolean, editing: Boolean, canAdd: Boolean, canEdit: Boolean, onAdd: () -> Unit, onEdit: () -> Unit) {
    Row(Modifier.padding(end = 2.dp).clip(RoundedCornerShape(50)).background(Palette.chipOff).padding(2.dp),
        verticalAlignment = Alignment.CenterVertically) {
        ControlButton(if (adding) Icons.Filled.Check else Icons.Filled.Add, adding, if (adding) "Done adding" else "Add a city", canAdd || adding, onAdd)
        Box(Modifier.width(0.5.dp).height(14.dp).background(if (adding || editing) Color.Transparent else white(0.2f)))
        ControlButton(if (editing) Icons.Filled.Check else Icons.Filled.Edit, editing, if (editing) "Done editing" else "Edit list", canEdit || editing, onEdit)
    }
}

@Composable
private fun ControlButton(icon: ImageVector, on: Boolean, label: String, enabled: Boolean, onClick: () -> Unit) {
    Box(Modifier.width(38.dp).height(30.dp).clip(RoundedCornerShape(50)).background(if (on) Palette.primary else Color.Transparent)
        .clickable(enabled = enabled, onClickLabel = label, onClick = onClick), contentAlignment = Alignment.Center) {
        Icon(icon, contentDescription = label, modifier = Modifier.size(18.dp),
            tint = if (on) Palette.black else if (enabled) Palette.primary else white(0.35f))
    }
}

/**
 * The sky behind a card, from Two Degrees' table: clear day, partly cloudy day (for dawn and dusk,
 * within an hour of sunrise or sunset) or clear night, top to bottom.
 */
object Sky {
    enum class Phase { DAY, TWILIGHT, NIGHT }

    fun phase(place: Place, at: java.time.Instant): Phase {
        val twilight = 3600L
        return when (val p = Sun.phase(place, at)) {
            is Sun.Phase.Day -> if (p.sets.epochSecond - at.epochSecond < twilight) Phase.TWILIGHT else Phase.DAY
            is Sun.Phase.Night -> if (p.rises.epochSecond - at.epochSecond < twilight) Phase.TWILIGHT else Phase.NIGHT
            Sun.Phase.AllDay -> Phase.DAY
            Sun.Phase.AllNight -> Phase.NIGHT
            null -> if (at.atZone(place.zone).hour in 7..18) Phase.DAY else Phase.NIGHT
        }
    }

    /** Top and bottom of the gradient. */
    fun colors(phase: Phase): Pair<Color, Color> = when (phase) {
        Phase.DAY -> Color(0xFF3D74B0) to Color(0xFF1C3A5E)
        Phase.TWILIGHT -> Color(0xFF4F78A3) to Color(0xFF24384F)
        Phase.NIGHT -> Color(0xFF141E3C) to Color(0xFF0A0E1C)
    }
}
