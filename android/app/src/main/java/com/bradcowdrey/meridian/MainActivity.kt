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
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.role
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.animateScrollBy
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.ui.geometry.CornerRadius
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
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipRect
import androidx.compose.ui.graphics.drawscope.scale
import androidx.compose.ui.BiasAlignment
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
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
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
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import androidx.compose.foundation.Image
import androidx.compose.material.icons.filled.Star
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.ColorMatrix
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawStyle
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
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
    /** Widgets, the app icon, the Terms button and the "+1 d" badge (as on the Mac). */
    val cream = Color(0xFFFFF1E5)
    /** Widgets, the app icon and the midnight mark between hour tiles (as on the Mac). */
    val crimson = Color(0xFF990F3D)
    val black = Color.Black
    val notice = Color(0xFFF2A65A)
    val destructive = Color(0xFFE5484D)
    /** Cards on the flat sheets. Two Degrees uses black 20% over its sky; our sheets are flat, so white. */
    val cardFill = Color(0x14FFFFFF)
    val cardBorder = Color(0x1FFFFFFF)
    val chipOff = Color(0x1FFFFFFF)
    /** The Two Degrees bottom bar. */
    // Nearly opaque: Android has no blur behind a bar, so cards must not show through the ruler.
    val barBg = Color(0xFF0B0C0F)
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
    // Groups opened from Settings go back to Settings; everything else back to the cards.
    BackHandler(enabled = route != "main") { route = if (route == "settings/groups") "settings" else "main" }
    when {
        route == "groups" -> GroupsScreen(store, null) { route = "main" }
        route == "settings/groups" -> GroupsScreen(store, null) { route = "settings" }
        route == "newgroup" -> GroupsScreen(store, null, create = true) { route = "main" }
        route.startsWith("group:") -> GroupsScreen(store, route.removePrefix("group:")) { route = "main" }
        route == "add" -> MainScreen(store, initialQuery = "san") { route = it }
        route == "edit" -> MainScreen(store, initialEditing = true) { route = it }
        route == "settings" -> SettingsScreen(store, openGroups = { route = "settings/groups" }) { route = "main" }
        route == "date" -> DateJumpScreen(store) { route = "main" }
        route == "find" -> FindTimeScreen(store) { route = "main" }
        route == "widgets" -> WidgetShowcase(store)
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
    // The card whose groups are being picked (by id, so it follows edits).
    var groupPickerFor by remember { mutableStateOf<String?>(null) }
    // Said by TalkBack when the list goes back to All by itself.
    var announce by remember { mutableStateOf("") }
    // Cleared first so a second or later reset is a new announcement, not the same text again.
    LaunchedEffect(store.filterResets) { if (store.filterResets > 0) { announce = ""; delay(100); announce = "Showing all cities" } }

    LaunchedEffect(store.userMoves) {
        if (store.userMoves > 0) haptics.performHapticFeedback(
            if (store.onTheHour) HapticFeedbackType.LongPress else HapticFeedbackType.TextHandleMove)
    }
    LaunchedEffect(copied) { if (copied) { delay(1800); copied = false } }

    // Off the main thread: the first search reads the 34,000-city list, which takes a moment.
    val searched by produceState<Pair<String, List<CityEntry>>?>(null, query) {
        if (query.isNotBlank()) value = query to kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) { CityDirectory.search(query) }
    }
    // A city added while one group is showing: it joins that group (one of yours), or the list goes
    // back to All (a continent it isn't on), so the new card never vanishes.
    fun afterAdd(id: String?) {
        val filter = store.groupFilter ?: return
        if (filter !in store.chipGroups) return
        val place = store.places.firstOrNull { it.id == id } ?: return
        if (!store.isContinent(filter)) store.setGroups((place.groups ?: emptyList()) + filter, place)
        else if (filter !in store.groupsOf(place)) store.updateGroupFilter(null)
    }
    // Search on the keyboard: add the first result not already on the list.
    fun submit() {
        val found = searched ?: return
        if (found.first != query || !store.canAdd) return
        found.second.firstOrNull { !store.contains(it) }?.let { afterAdd(store.add(it)); closeSearch() }
    }

    fun share(title: String, subject: String, text: String) = context.startActivity(Intent.createChooser(
        Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_SUBJECT, subject).putExtra(Intent.EXTRA_TEXT, text), title))
    var shareMenu by remember { mutableStateOf(false) }
    // The ruler and Now, in a bar at the bottom as in Two Degrees; the groups and the hour columns
    // pinned at the top, over the tiles they label (as on the Mac).
    val showBar = !adding && !editing && store.places.isNotEmpty()
    val showGroupBar = showBar && (store.customGroups.isNotEmpty() || store.continentChipCount >= 2)
    val showHeader = showBar && store.visiblePlaces.isNotEmpty()
    val customFilter = store.groupFilter?.takeIf { it in store.chipGroups && !store.isContinent(it) }

    Scaffold(
        // The list sits on Meridian's own warm dark, as on the Mac.
        containerColor = Palette.bg,
        topBar = {
            Column(Modifier.fillMaxWidth().background(Palette.black).statusBarsPadding()) {
                Box(Modifier.fillMaxWidth().height(48.dp).padding(horizontal = 4.dp)) {
                    // Share, as in Cowdrey.MD: Meridian or this moment, or copy a link or a ready-to-send message.
                    Box(Modifier.align(Alignment.CenterStart)) {
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
                    // The title, small and centred between Share and the controls (never large).
                    // Kept clear of Share (48 dp) and the +/pencil capsule and More (≈131 dp) at any font size.
                    Text("Meridian", fontSize = (17f / maxOf(1f, LocalDensity.current.fontScale / 1.15f)).sp, fontWeight = FontWeight.SemiBold,
                        color = Palette.primary, maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.align(Alignment.Center).padding(horizontal = 132.dp).semantics { heading() })
                    Row(Modifier.align(Alignment.CenterEnd), verticalAlignment = Alignment.CenterVertically) {
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
                            DropdownMenuItem(text = { Text("Groups…") }, onClick = { menu = false; open("groups") })
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
                }
                if (adding) CitySearchField(query, focus = !store.demo, onSearch = { submit() }) { query = it }
                else if (showGroupBar || showHeader) {
                    Column(Modifier.fillMaxWidth().background(Palette.barBg)) {
                        if (showGroupBar) GroupBar(store, open)
                        if (showHeader) ColumnHeader(store)
                        HorizontalDivider(thickness = 0.5.dp, color = white(0.15f))
                    }
                }
            }
        },
        bottomBar = {
            if (showBar) {
                Column(Modifier.fillMaxWidth().background(Palette.barBg).navigationBarsPadding()) {
                    HorizontalDivider(thickness = 0.5.dp, color = white(0.15f))
                    TimeShifter(store) { open("date") }
                }
            }
        },
    ) { padding ->
        Box(Modifier.fillMaxSize()) {
            if (adding) {
                if (query.isNotBlank()) SearchResults(store, query, searched, Modifier.padding(padding)) { afterAdd(it); closeSearch() }
                else Text("Type a city, an airport code like SFO, a time zone like PST, or an offset like UTC+5:30." +
                    (customFilter?.let { " Adding to $it." } ?: ""),
                    fontSize = 15.sp, color = white(0.6f), modifier = Modifier.padding(padding).padding(16.dp))
            } else {
                // Clocks about to change above the cards. Edit List shows every card (not one group),
                // so removing and moving follow the full list.
                val changes = if (editing) emptyList() else store.clockChanges
                val rows = if (editing) store.places else store.visiblePlaces
                // Each notice's height, so a list of up to five cities can still fill exactly what's left.
                val noticeHeights = remember { mutableStateMapOf<String, Int>() }
                val density = LocalDensity.current
                BoxWithConstraints(Modifier.fillMaxSize()) {
                    // One to five cities share the height between the column labels and the bottom bar
                    // (no scrolling); six or more, or too little room (landscape), keep a fixed height and scroll.
                    val n = rows.size
                    val noticesPx = changes.sumOf { noticeHeights[it.key] ?: 0 }
                    // Whole px, as the layout rounds each padding, so the rows never overflow by a pixel or two.
                    val availPx = with(density) {
                        maxHeight.roundToPx() - padding.calculateTopPadding().roundToPx() - padding.calculateBottomPadding().roundToPx() -
                            noticesPx - 2 * Rows.edge.roundToPx() - (n - 1).coerceAtLeast(0) * Rows.gap.roundToPx()
                    }.toFloat()
                    val fittedHeight = if (!editing && n in 1..Rows.fitMax) with(density) { kotlin.math.floor(availPx / n).toInt().toDp() } else null
                    val fit = fittedHeight != null && fittedHeight >= Rows.minFit
                    val rowHeight = if (fit && fittedHeight != null) fittedHeight else Rows.scrollHeight
                // The cards scroll under the translucent bottom bar, as in Two Degrees.
                LazyColumn(Modifier.fillMaxSize(), contentPadding = padding) {
                    items(changes, key = { "clock-" + it.key }) { change ->
                        Box(Modifier.onSizeChanged { noticeHeights[change.key] = it.height }) {
                            ClockNotice(change, store.use24h) { store.dismiss(change) }
                        }
                    }
                    if (store.places.isEmpty()) item {
                        Column(Modifier.fillMaxWidth().padding(vertical = 40.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                            Text("No cities yet", fontSize = 20.sp, fontWeight = FontWeight.Medium, color = Palette.primary)
                            Spacer(Modifier.height(8.dp))
                            Text("Tap + at the top to add one: a city, an airport code like SFO, or a time zone like PST.",
                                fontSize = 15.sp, color = white(0.6f), textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 32.dp))
                        }
                    }
                    // A group with no cities: say so, with a way to fill it or to see everyone.
                    if (!editing && store.places.isNotEmpty() && store.visiblePlaces.isEmpty()) item(key = "empty-group") {
                        val group = store.groupFilter ?: ""
                        Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 40.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                            Text("No cities in $group yet.", fontSize = 15.sp, color = white(0.6f), textAlign = TextAlign.Center)
                            Spacer(Modifier.height(14.dp))
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                if (!store.isContinent(group)) CapsuleButton("Add Cities", filled = true) { open("group:$group") }
                                CapsuleButton("Show All", filled = false) { store.updateGroupFilter(null) }
                            }
                        }
                    }
                    itemsIndexed(rows, key = { _, place -> place.id }) { i, place ->
                        var actions by remember { mutableStateOf(false) }
                        // Touch and hold anywhere on the row, the hour tiles included (once, however it's held).
                        val openActions: () -> Unit = {
                            if (!actions) { haptics.performHapticFeedback(HapticFeedbackType.LongPress); actions = true }
                        }
                        var work by remember { mutableStateOf(false) }
                        // Every city is its own rounded card: its skyline across the top with its time on it,
                        // then its name, zone and status on the left and its five hour tiles on the right.
                        // Touch and hold a card for its own actions (a tap does nothing, so scrolling never
                        // opens them by accident); dragging its hour tiles still moves every city's time.
                        val first = i == 0
                        val last = i == rows.lastIndex
                        val shape = RoundedCornerShape(Rows.radius)
                        Box(Modifier.padding(start = Strip.margin, end = Strip.margin, top = if (first) Rows.edge else 0.dp,
                            bottom = if (last) Rows.edge else Rows.gap)
                            .fillMaxWidth().clip(shape).background(Palette.tile)) {
                            if (editing) EditRow(store, place)
                            else {
                                CityRow(store, place, height = rowHeight, modifier = Modifier
                                    .pointerInput(place.id) {
                                        detectTapGestures(onLongPress = { openActions() })
                                    }
                                    .semantics { onLongClick(label = "Actions for ${place.title}") { actions = true; true } },
                                    onLongPress = { openActions() })
                            }
                            DropdownMenu(expanded = actions, onDismissRequest = { actions = false }) {
                                DropdownMenuItem(text = { Text("Copy Time") }, onClick = {
                                    actions = false
                                    clipboard.setText(AnnotatedString("${place.fullName}: ${TimeMath.fullMoment(store.moment, place.zone, store.use24h)}"))
                                    copied = true
                                })
                                DropdownMenuItem(text = { Text("Working Days & Hours") }, onClick = { actions = false; work = true })
                                DropdownMenuItem(text = { Text("Add a Person Here") }, enabled = store.canAdd, onClick = { actions = false; personFor = place })
                                DropdownMenuItem(text = { Text("Groups…") }, onClick = { actions = false; groupPickerFor = place.id })
                                if (!place.isMyLocation || place.person != null) DropdownMenuItem(text = { Text("Rename") }, onClick = { actions = false; renaming = place })
                                DropdownMenuItem(text = { Text("Remove", color = Palette.destructive) }, onClick = { actions = false; store.remove(place) })
                            }
                            if (work) WorkHoursDialog(store, place) { work = false }
                        }
                    }
                    // The footer only where the list scrolls anyway (a list that fills the screen stays still).
                    if (!fit) item { Footer() }
                }
                }
            }
            // "Copied": 8 dp above the bottom bar, or at the bottom when the bar is hidden.
            if (copied) CopiedPill(Modifier.align(Alignment.BottomCenter).padding(bottom = padding.calculateBottomPadding() + 8.dp))
            // Polite announcements for TalkBack ("Showing all cities").
            Box(Modifier.size(1.dp).semantics { liveRegion = LiveRegionMode.Polite; contentDescription = announce })
        }
    }
    renaming?.let { place -> RenameDialog(place, onDone = { name -> if (name != null) store.rename(place, name); renaming = null }) }
    personFor?.let { place ->
        val city = if (place.isMyLocation) store.hereCity ?: "My Location" else place.name
        AddPersonDialog(city) { name -> if (name != null) store.addPerson(name, place); personFor = null }
    }
    groupPickerFor?.let { id -> GroupPickerDialog(store, id) { groupPickerFor = null } }
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

/** "no cities", "1 city", "5 cities". */
fun cityCount(n: Int): String = when (n) { 0 -> "no cities"; 1 -> "1 city"; else -> "$n cities" }

/** A small capsule button: white with black text, or faint white. */
@Composable
fun CapsuleButton(title: String, filled: Boolean, onClick: () -> Unit) {
    Box(Modifier.minimumInteractiveComponentSize().heightIn(min = 36.dp).clip(RoundedCornerShape(50))
        .background(if (filled) Palette.primary else white(0.12f)).clickable(onClick = onClick).padding(horizontal = 16.dp),
        contentAlignment = Alignment.Center) {
        Text(title, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = if (filled) Palette.black else Palette.primary,
            maxLines = 1, softWrap = false)
    }
}

/**
 * The groups, pinned above the cards: All, your groups in your order, the continents (when the list
 * spans two or more), then New Group (none yet) or Edit Groups. Touch and hold a chip for its actions.
 */
@Composable
fun GroupBar(store: Store, open: (String) -> Unit) {
    val custom = store.customGroups
    val continents = store.chipGroups.filter { store.isContinent(it) }
    val divider = custom.isNotEmpty() && continents.isNotEmpty()
    val state = rememberLazyListState()
    val haptics = LocalHapticFeedback.current
    var deleting by remember { mutableStateOf<String?>(null) }
    val filter = store.groupFilter
    val selected = when {
        filter == null -> 0
        filter in custom -> 1 + custom.indexOf(filter)
        filter in continents -> 1 + custom.size + (if (divider) 1 else 0) + continents.indexOf(filter)
        else -> 0
    }
    // Keep the chosen chip in view, centred where the row allows.
    LaunchedEffect(filter, selected) {
        val info = state.layoutInfo
        val item = info.visibleItemsInfo.firstOrNull { it.index == selected }
        if (item != null) {
            val center = (info.viewportStartOffset + info.viewportEndOffset) / 2
            state.animateScrollBy((item.offset + item.size / 2 - center).toFloat())
        } else state.animateScrollToItem(selected)
    }
    fun select(group: String?) {
        if (group == store.groupFilter) return
        haptics.performHapticFeedback(HapticFeedbackType.TextHandleMove)
        store.updateGroupFilter(group)
    }
    LazyRow(state = state, contentPadding = PaddingValues(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp),
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier.fillMaxWidth().selectableGroup().semantics { contentDescription = "Groups" }) {
        item(key = "__all") {
            GroupChip("All", filter == null, "All, ${cityCount(store.places.size)}", emptyList(), onClick = { select(null) }) { _ -> }
        }
        items(custom, key = { "c:$it" }) { group ->
            GroupChip(group, filter == group, "$group, ${cityCount(store.groupCount(group))}",
                listOf(
                    CustomAccessibilityAction("Edit Group") { open("group:$group"); true },
                    CustomAccessibilityAction("Delete Group") { deleting = group; true },
                ),
                onClick = { select(group) }) { close ->
                DropdownMenuItem(text = { Text("Edit Group…") }, onClick = { close(); open("group:$group") })
                DropdownMenuItem(text = { Text("Delete Group…", color = Palette.destructive) }, onClick = { close(); deleting = group })
            }
        }
        if (divider) item(key = "__divider") { Box(Modifier.size(width = 0.5.dp, height = 20.dp).background(white(0.2f))) }
        items(continents, key = { "k:$it" }) { group ->
            GroupChip(group, filter == group, "$group, ${cityCount(store.groupCount(group))}",
                listOf(CustomAccessibilityAction("Turn Off Continent Groups") { open("settings"); true }),
                onClick = { select(group) }) { close ->
                DropdownMenuItem(text = { Text("Turn Off Continent Groups") }, onClick = { close(); open("settings") })
            }
        }
        item(key = "__edit") {
            val none = custom.isEmpty()
            Row(Modifier.minimumInteractiveComponentSize().heightIn(min = 32.dp).clip(RoundedCornerShape(50))
                .clickable { open(if (none) "newgroup" else "groups") }.padding(horizontal = 8.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Icon(if (none) Icons.Filled.Add else Icons.Filled.Edit, contentDescription = null, tint = white(0.7f), modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(4.dp))
                Text(if (none) "New Group" else "Edit Groups", fontSize = 15.sp, fontWeight = FontWeight.Medium, color = white(0.7f),
                    maxLines = 1, softWrap = false)
            }
        }
    }
    deleting?.let { group ->
        DeleteGroupDialog(group, onConfirm = { deleting = null; store.deleteGroup(group) }, onDismiss = { deleting = null })
    }
}

/** A group chip (as PillChip): tap to show that group, touch and hold for its menu. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun GroupChip(
    title: String,
    on: Boolean,
    description: String,
    actions: List<CustomAccessibilityAction>,
    onClick: () -> Unit,
    menuItems: @Composable ColumnScope.(close: () -> Unit) -> Unit,
) {
    var menu by remember { mutableStateOf(false) }
    val haptics = LocalHapticFeedback.current
    val fg = if (on) Palette.black else Palette.primary
    val longClick: (() -> Unit)? = if (actions.isEmpty()) null else fun() {
        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
        menu = true
    }
    Box {
        Row(Modifier.minimumInteractiveComponentSize().heightIn(min = 32.dp).clip(RoundedCornerShape(50))
            .background(if (on) Palette.primary else Palette.chipOff)
            .combinedClickable(onClick = onClick, onLongClick = longClick)
            .semantics {
                role = Role.Tab
                selected = on
                contentDescription = description
                if (actions.isNotEmpty()) customActions = actions
            }
            .padding(horizontal = 14.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.Center) {
            Text(title, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = fg, maxLines = 1, softWrap = false)
        }
        if (actions.isNotEmpty()) DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
            menuItems { menu = false }
        }
    }
}

/**
 * The hour columns, once, over every row's tiles: "Now" (or the time you went to) in the middle,
 * ±1 and ±2 hr either side as small pills, and a white mark under an hour when everyone is working.
 */
@Composable
fun ColumnHeader(store: Store) {
    val anchor = TimeMath.hourAnchor(store.moment, store.home)
    val nowAnchor = TimeMath.hourAnchor(store.now, store.home)
    val visible = store.visiblePlaces
    val cap = maxOf(1f, LocalDensity.current.fontScale / 1.3f)
    // Lined up over the rows' tiles: the same insets and name column as a row, then the five columns.
    BoxWithConstraints(Modifier.fillMaxWidth().windowInsetsPadding(WindowInsets.systemBars.only(WindowInsetsSides.Horizontal))
        .height(44.dp).padding(horizontal = Strip.inset)) {
    val labelWidth = Strip.labelWidth(maxWidth)
    Row(Modifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
    Spacer(Modifier.width(labelWidth + Strip.labelGap))
    Row(Modifier.weight(1f).fillMaxHeight(), horizontalArrangement = Arrangement.spacedBy(Strip.gap),
        verticalAlignment = Alignment.CenterVertically) {
        (-2..2).forEach { k ->
            val start = anchor.plusSeconds(k * 3600L)
            val readsNow = k != 0 && !store.isNow && start == nowAnchor
            val label = when {
                k == 0 -> if (store.isNow) "Now" else TimeMath.time(store.moment, store.home, store.use24h)
                readsNow -> "Now"
                k > 0 -> "+$k hr"
                else -> "−${-k} hr"
            }
            val overlap = store.showWorkHours && visible.size >= 2 && visible.all { store.isWorking(it, start.plusSeconds(1800)) }
            val hours = if (kotlin.math.abs(k) == 1) "hour" else "hours"
            val description = when {
                k == 0 -> if (store.isNow) "Now" else "Back to now"
                readsNow -> "Back to now"
                store.isNow -> "${kotlin.math.abs(k)} $hours ${if (k > 0) "from now" else "ago"}"
                else -> "${kotlin.math.abs(k)} $hours ${if (k > 0) "later" else "earlier"}, ${TimeMath.time(start, store.home, store.use24h)}"
            } + if (overlap) ", everyone working" else ""
            Column(Modifier.weight(1f).fillMaxHeight()
                .clickable(enabled = k != 0 || !store.isNow) {
                    when {
                        k == 0 || readsNow -> store.backToNow()
                        store.isNow -> store.shift(k * 60)
                        else -> store.jump(start)
                    }
                }
                .semantics { contentDescription = description; if (k == 0) selected = store.isNow },
                horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
                var shrink by remember(label) { mutableFloatStateOf(1f) }
                Box(Modifier.fillMaxWidth().height(28.dp).clearAndSetSemantics {}
                    .then(if (k == 0 || readsNow) Modifier else Modifier.clip(RoundedCornerShape(50)).background(white(0.08f))),
                    contentAlignment = Alignment.Center) {
                    Text(label, style = tnum, fontSize = (13f / cap * shrink).sp, maxLines = 1, softWrap = false,
                        fontWeight = if (k == 0 || readsNow) FontWeight.SemiBold else FontWeight.Medium,
                        color = if (readsNow) white(0.9f) else Palette.primary,
                        onTextLayout = { if (it.didOverflowWidth && shrink > 0.6f) shrink = (shrink - 0.1f).coerceAtLeast(0.6f) })
                }
                Spacer(Modifier.height(3.dp))
                Box(Modifier.size(width = 16.dp, height = 3.dp).clip(RoundedCornerShape(50))
                    .background(if (overlap) Palette.primary else Color.Transparent))
            }
        }
    }
    }
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
 * Moves every city through time from the bottom bar, in thumb reach as in Two Degrees: Go to a Time,
 * the ruler (quarter-hours, two days either way) and Now. The hour columns at the top jump an hour;
 * the tiles on every card drag.
 */
@Composable
fun TimeShifter(store: Store, goToTime: () -> Unit) {
    Column(Modifier.fillMaxWidth()) {
        if (!store.hasScrubbed) {
            Text("Drag the hours or the ruler to change the time.", fontSize = 12.sp, lineHeight = 16.sp, fontWeight = FontWeight.Medium,
                color = white(0.6f), textAlign = TextAlign.Center, maxLines = 1, overflow = TextOverflow.Ellipsis,
                modifier = Modifier.fillMaxWidth().padding(top = 6.dp, start = 16.dp, end = 16.dp).height(16.dp))
        }
        Row(Modifier.fillMaxWidth().padding(start = 4.dp, end = 12.dp, top = 6.dp, bottom = 2.dp).height(44.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            IconButton(onClick = goToTime) { Icon(Icons.Filled.DateRange, contentDescription = "Go to a Time", tint = Palette.primary) }
            Box(Modifier.weight(1f)) { TimeRuler(store) }
            NowButton(store)
        }
    }
}

/** Now: white when you've moved through time, quiet (and off) when you're at now. */
@Composable
fun NowButton(store: Store) {
    Box(Modifier.minimumInteractiveComponentSize().size(64.dp, 32.dp).clip(RoundedCornerShape(50))
        .background(if (store.isNow) white(0.12f) else Palette.primary)
        .clickable(enabled = !store.isNow, onClickLabel = "Back to now") { store.backToNow() }
        .semantics { contentDescription = if (store.isNow) "Now" else "Back to now" },
        contentAlignment = Alignment.Center) {
        Text("Now", fontSize = 15.sp, fontWeight = FontWeight.Medium, color = if (store.isNow) white(0.35f) else Palette.black,
            maxLines = 1, softWrap = false)
    }
}

/**
 * The city list's geometry, as the Mac panel's strip: shared by the column labels at the top and every
 * row, so the labels sit exactly over the tile columns. One even gutter between tiles both ways; the
 * Now lens's 2 dp stroke sits centred in that gutter, its corners concentric with the tiles'.
 */
object Strip {
    /** Screen edge to the panel. */
    val margin = 12.dp
    /** Panel edge to the names and the tiles. */
    val pad = 10.dp
    /** Screen edge to the names and the tiles (the column labels use the same). */
    val inset = margin + pad
    val panelRadius = 20.dp
    /** Above the first row and below the last, inside the panel (with the row's own half gutter, the panel's inset). */
    val panelPadTop = 7.dp
    /** Between tiles, across and down. */
    val gap = 6.dp
    val tileHeight = 44.dp
    val tileRadius = 9.dp
    val lensStroke = 2.dp
    val lensOutset = gap / 2 + lensStroke / 2
    val lensRadius = tileRadius + lensOutset

    /** Between the name column and the tiles. */
    val labelGap = 8.dp

    /** The name column, from the width inside the insets: about a third, as on the Mac; the tiles take the rest. */
    fun labelWidth(inner: Dp): Dp = (inner * 0.32f).coerceIn(100.dp, 150.dp)
}

/** The city cards' sizes: separate rounded cards, a skyline banner on each. */
object Rows {
    val radius = 16.dp
    /** Between cards, and above the first and below the last. */
    val gap = 8.dp
    val edge = 8.dp
    /** Up to this many cities share the screen's height; more scroll. */
    const val fitMax = 5
    /** A card's height when the list scrolls (six or more cities, or too little room to share). */
    val scrollHeight = 132.dp
    /** Shared heights below this scroll at [scrollHeight] instead (landscape). */
    val minFit = 96.dp
    /** From this height a card is tall: a larger time, and the status's detail ("until 6 PM"). */
    val tallFrom = 150.dp
    val tileHeight = 52.dp

    /** The banner across the top: 42% of a tall card, else a third (never under 42 dp). */
    fun bannerHeight(row: Dp): Dp = if (row >= tallFrom) row * 0.42f else maxOf(42.dp, row * 0.34f)
}

/** What a city is doing now, for the pill under its name. */
enum class StatusKind(val color: Color) {
    WORKING(Color(0xFF9FE3A6)), OFF_HOURS(Color(0xFFB9B2A8)), WEEKEND(Color(0xFFF4C47A)), DAY_OFF(Color(0xFFF4C47A)), HOLIDAY(Color(0xFFF29BB5))
}

/** "Working" with "until 6 PM", "Off hours" with "back 9 AM Mon", or a holiday's name. */
data class RowStatus(val kind: StatusKind, val text: String, val detail: String?) {
    val spoken: String get() = if (detail != null) "$text, $detail" else text
}

object CityStatus {
    /** The status at this moment; with [detail], when it ends (scanning ahead in quarter-hours, up to 8 days). */
    fun of(place: Place, at: Instant, start: Int, end: Int, use24h: Boolean, detail: Boolean): RowStatus {
        val off = WorkWeek.offLabel(place, at, start, end)
        val holiday = Holidays.name(place, at)
        val kind = when {
            off == null -> StatusKind.WORKING
            holiday != null && off == holiday -> StatusKind.HOLIDAY
            off == "Weekend" -> StatusKind.WEEKEND
            off == "Day off" -> StatusKind.DAY_OFF
            else -> StatusKind.OFF_HOURS
        }
        val working = kind == StatusKind.WORKING
        var note: String? = null
        if (detail) {
            val from = TimeMath.quarter(at)
            val today = at.atZone(place.zone).toLocalDate()
            for (i in 1..8 * 96) {
                val t = from.plusSeconds(i * 900L)
                if (WorkWeek.isWorking(place, t, start, end) != working) {
                    val local = t.atZone(place.zone)
                    val clock = short(local.hour, local.minute, use24h)
                    val day = if (local.toLocalDate() != today) " " + TimeMath.weekday(t, place.zone) else ""
                    note = (if (working) "until " else "back ") + clock + day
                    break
                }
            }
        }
        return RowStatus(kind, off ?: "Working", note)
    }

    /** "6 PM", "9:30 AM", "18:00". */
    private fun short(hour: Int, minute: Int, use24h: Boolean): String {
        if (use24h) return "%02d:%02d".format(hour, minute)
        val h = if (hour % 12 == 0) 12 else hour % 12
        return "$h${if (minute != 0) ":%02d".format(minute) else ""}${TimeMath.THIN}${if (hour < 12) "AM" else "PM"}"
    }
}

/**
 * The skyline photos built in (res/drawable-nodpi), by city name, decoded once and kept; and how
 * each is shaded for the time of day there.
 */
object Skyline {
    fun photo(city: String): Int? = when (city.trim().lowercase()) {
        "san francisco" -> R.drawable.skyline_sanfrancisco
        "new york", "new york city", "manhattan" -> R.drawable.skyline_newyork
        "london" -> R.drawable.skyline_london
        "tokyo" -> R.drawable.skyline_tokyo
        else -> null
    }

    /** Where each photo is cropped: a little above centre, so the tops of the towers stay in a short banner. */
    fun align(id: Int): Alignment = BiasAlignment(0f, biasY(id))

    private fun biasY(id: Int): Float = when (id) {
        R.drawable.skyline_sanfrancisco -> -0.35f
        R.drawable.skyline_london -> -0.45f
        R.drawable.skyline_newyork -> -0.2f
        else -> -0.1f
    }

    private val bitmaps = HashMap<Int, ImageBitmap>()

    fun bitmap(context: android.content.Context, id: Int): ImageBitmap = synchronized(bitmaps) {
        bitmaps.getOrPut(id) { android.graphics.BitmapFactory.decodeResource(context.resources, id).asImageBitmap() }
    }

    private fun scale(m: FloatArray) = ColorFilter.colorMatrix(ColorMatrix(floatArrayOf(
        m[0], 0f, 0f, 0f, 0f,
        0f, m[1], 0f, 0f, 0f,
        0f, 0f, m[2], 0f, 0f,
        0f, 0f, 0f, 1f, 0f,
    )))

    /** Night: darker (about 45%) and a little cooler; dawn and dusk: a little warmer, about 15% darker; day as taken. */
    private val nightGain = floatArrayOf(0.40f, 0.44f, 0.54f)
    private val twilightGain = floatArrayOf(0.93f, 0.84f, 0.72f)
    private val dayGain = floatArrayOf(1f, 1f, 1f)
    private val night = scale(nightGain)
    private val twilight = scale(twilightGain)

    private fun gain(phase: Sky.Phase): FloatArray = when (phase) {
        Sky.Phase.NIGHT -> nightGain
        Sky.Phase.TWILIGHT -> twilightGain
        Sky.Phase.DAY -> dayGain
    }

    /** Whether the banner is bright behind the time, keyed by photo, phase and banner shape (in steps of 0.05). */
    private val brightness = HashMap<String, Boolean>()

    /**
     * Whether a photo banner is bright (relative luminance over 0.40) behind the time: the bottom-left
     * 55% x 50% of the banner, as the photo is cropped and aligned there, after the time-of-day shading.
     */
    fun photoIsBright(id: Int, bitmap: ImageBitmap, phase: Sky.Phase, width: Int, height: Int): Boolean {
        if (width <= 0 || height <= 0) return false
        val step = (width.toFloat() / height * 20f).roundToInt().coerceAtLeast(1)
        val key = "$id/${phase.name}/$step"
        synchronized(brightness) { brightness[key]?.let { return it } }
        val bright = try {
            regionLuminance(bitmap.asAndroidBitmap(), biasY(id), gain(phase), step / 20f) > 0.40f
        } catch (e: Exception) {
            false
        }
        synchronized(brightness) { brightness[key] = bright }
        return bright
    }

    /**
     * The drawn skyline: the bottom-left of the banner, behind the time, is mostly its (dark) buildings,
     * not its sky, so weigh the lower sky against the ink by how much the buildings cover. The near
     * buildings (opaque, 18-60% of the height, overlapping) cover ~85% of the bottom half and the far ones
     * add more, so even by day (#A9CBEA sky over #22324A ink) this comes to ~0.11: dark in every phase.
     */
    fun drawnIsBright(phase: Sky.Phase): Boolean {
        val (_, sky, ink) = drawnColors(phase)
        val coverage = 0.85f
        return sky.luminance() * (1f - coverage) + ink.luminance() * coverage > 0.40f
    }

    private fun linear(c: Float): Double =
        if (c <= 0.04045f) c / 12.92 else Math.pow((c + 0.055) / 1.055, 2.4)

    /** The mean relative luminance of the photo behind the time, for a banner `aspect` wide by 1 high. */
    private fun regionLuminance(src: android.graphics.Bitmap, biasY: Float, gain: FloatArray, aspect: Float): Float {
        val iw = src.width.toFloat()
        val ih = src.height.toFloat()
        if (iw < 2f || ih < 2f) return 0f
        // ContentScale.Crop, then BiasAlignment(0, biasY), as the Image draws it.
        val bw = aspect
        val bh = 1f
        val s = maxOf(bw / iw, bh / ih)
        val offX = (bw - iw * s) / 2f
        val offY = (bh - ih * s) / 2f * (1f + biasY)
        val left = ((0f - offX) / s).coerceIn(0f, iw - 1f).toInt()
        val right = ((0.55f * bw - offX) / s).coerceIn(left + 1f, iw).toInt()
        val top = ((0.5f * bh - offY) / s).coerceIn(0f, ih - 1f).toInt()
        val bottom = ((bh - offY) / s).coerceIn(top + 1f, ih).toInt()
        val w = (right - left).coerceIn(1, src.width - left)
        val h = (bottom - top).coerceIn(1, src.height - top)
        val crop = android.graphics.Bitmap.createBitmap(src, left, top, w, h)
        val small = android.graphics.Bitmap.createScaledBitmap(crop, 24, 12, true)
        val px = IntArray(24 * 12)
        small.getPixels(px, 0, 24, 0, 0, 24, 12)
        if (small !== src && small !== crop) small.recycle()
        if (crop !== src) crop.recycle()
        var sum = 0.0
        for (c in px) {
            val r = (((c shr 16) and 0xFF) / 255f * gain[0]).coerceIn(0f, 1f)
            val g = (((c shr 8) and 0xFF) / 255f * gain[1]).coerceIn(0f, 1f)
            val b = ((c and 0xFF) / 255f * gain[2]).coerceIn(0f, 1f)
            sum += 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }
        return (sum / px.size).toFloat()
    }

    fun shade(phase: Sky.Phase): ColorFilter? = when (phase) {
        Sky.Phase.NIGHT -> night
        Sky.Phase.TWILIGHT -> twilight
        Sky.Phase.DAY -> null
    }

    /** The drawn skyline's sky (top, bottom) and buildings. */
    fun drawnColors(phase: Sky.Phase): Triple<Color, Color, Color> = when (phase) {
        Sky.Phase.DAY -> Triple(Color(0xFF4A80BD), Color(0xFFA9CBEA), Color(0xFF22324A))
        Sky.Phase.TWILIGHT -> Triple(Color(0xFF2B3A6B), Color(0xFFF08A5D), Color(0xFF1A1A2A))
        Sky.Phase.NIGHT -> Triple(Color(0xFF0B1022), Color(0xFF1A2340), Color(0xFF06080F))
    }
}

/** The city a card's photo is for: a person's city, or where you are for My Location. */
fun skylineCity(store: Store, place: Place): String = if (place.isMyLocation) store.hereCity ?: place.name else place.name

/**
 * A city with no photo: a skyline drawn for it (the same city always gets the same buildings) on the
 * sky for the time of day, with the sun or moon, and lit windows after dark.
 */
@Composable
private fun DrawnSkyline(city: String, phase: Sky.Phase, modifier: Modifier) {
    val seed = city.lowercase().hashCode().toLong()
    Canvas(modifier) {
        val (top, bottom, ink) = Skyline.drawnColors(phase)
        val w = size.width
        val h = size.height
        val u = 1.dp.toPx()
        drawRect(Brush.verticalGradient(listOf(top, bottom)))
        when (phase) {
            Sky.Phase.NIGHT -> drawCircle(Color(0xFFF4F1E6).copy(alpha = 0.9f), 9 * u, Offset(w * 0.86f, h * 0.28f))
            Sky.Phase.TWILIGHT -> drawCircle(Color(0xFFFFC27A).copy(alpha = 0.85f), 22 * u, Offset(w * 0.88f, h * 0.82f))
            Sky.Phase.DAY -> drawCircle(Color(0xFFFFF6D8).copy(alpha = 0.95f), 12 * u, Offset(w * 0.86f, h * 0.25f))
        }
        // The far buildings, fainter.
        val back = java.util.Random(seed xor 0x5DEECE66DL)
        repeat(30) {
            val x = back.nextFloat() * w
            val bw = (10 + back.nextFloat() * 22) * u
            val bh = h * (0.25f + back.nextFloat() * 0.35f)
            drawRect(ink.copy(alpha = 0.55f), Offset(x, h - bh), Size(bw, bh))
        }
        // The near buildings, with windows lit at dusk and at night.
        val r = java.util.Random(seed)
        val lit = when (phase) { Sky.Phase.NIGHT -> 0.35f; Sky.Phase.TWILIGHT -> 0.18f; Sky.Phase.DAY -> 0f }
        val window = Color(0xFFFFD98A)
        var x = 0f
        while (x < w) {
            val bw = (8 + r.nextFloat() * 18) * u
            val bh = h * (0.18f + r.nextFloat() * 0.42f)
            drawRect(ink, Offset(x, h - bh), Size(bw, bh))
            if (lit > 0f) {
                var y = h - bh + 4 * u
                while (y < h - 3 * u) {
                    var wx = x + 2 * u
                    while (wx < x + bw - 2 * u) {
                        if (r.nextFloat() < lit) drawRect(window.copy(alpha = 0.6f + r.nextFloat() * 0.4f), Offset(wx, y), Size(1.6f * u, 2 * u))
                        wx += 4 * u
                    }
                    y += 5 * u
                }
            }
            x += (6 + r.nextFloat() * 14) * u
        }
    }
}

/**
 * The banner across the top of a card: the city's skyline (its photo, shaded for the time of day
 * there, or one drawn for it), with the time there at the bottom left over a soft scrim: white numbers on a
 * dark banner, dark ones on a bright banner (adaptive ink, measured behind the time after the shading). A drawn
 * skyline's buildings fill most of the space behind the time, so it keeps white numbers in every phase.
 */
@Composable
fun SkylineBanner(store: Store, place: Place, compact: Boolean, modifier: Modifier) {
    val moment = store.moment
    val city = skylineCity(store, place)
    val phase = Sky.phase(place, moment)
    val photo = Skyline.photo(city)
    val context = LocalContext.current
    BoxWithConstraints(modifier.clipToBounds().clearAndSetSemantics {}) {
        val widthPx = if (constraints.hasBoundedWidth) constraints.maxWidth else 0
        val heightPx = if (constraints.hasBoundedHeight) constraints.maxHeight else 0
        // Adaptive ink: dark numbers on a bright banner, white ones on a dark one (measured after the shading).
        val bright: Boolean
        if (photo != null) {
            val bitmap = remember(photo) { Skyline.bitmap(context, photo) }
            bright = remember(photo, phase, widthPx, heightPx) { Skyline.photoIsBright(photo, bitmap, phase, widthPx, heightPx) }
            Image(bitmap, contentDescription = null, contentScale = ContentScale.Crop, alignment = Skyline.align(photo),
                colorFilter = Skyline.shade(phase), modifier = Modifier.matchParentSize())
        } else {
            bright = Skyline.drawnIsBright(phase)
            DrawnSkyline(city, phase, Modifier.matchParentSize())
        }
        // The scrim: black (white on a bright banner) at the bottom-left corner, under the time, fading out three
        // quarters of the way along an ellipse 120% of the banner wide and 110% high (the mockup's
        // radial-gradient(120% 110% at 0% 100%)).
        val scrim = if (bright) Color.White else Color.Black
        val (scrimNear, scrimMid) = if (bright) 0.45f to 0.20f else 0.55f to 0.25f
        Box(Modifier.matchParentSize().drawBehind {
            if (size.width <= 0f || size.height <= 0f) return@drawBehind
            val rx = size.width * 1.2f
            val ry = size.height * 1.1f
            scale(scaleX = 1f, scaleY = ry / rx, pivot = Offset(0f, size.height)) {
                drawRect(Brush.radialGradient(0f to scrim.copy(alpha = scrimNear), 0.45f to scrim.copy(alpha = scrimMid),
                    0.75f to scrim.copy(alpha = 0f), center = Offset(0f, size.height), radius = rx),
                    topLeft = Offset(0f, size.height - rx), size = Size(size.width, rx))
            }
        })
        val (digits, suffix) = TimeMath.clock(moment, place.zone, store.use24h)
        BannerTime(digits, suffix, compact, bright, Modifier.align(Alignment.BottomStart).padding(start = 12.dp, bottom = 5.dp))
    }
}

/**
 * The time on a banner: semibold, tabular, a small AM/PM, with a thin outline and a soft shadow. On a dark
 * banner, white with a dark outline and shadow; on a bright one, near-black with a white outline and glow.
 * Grows a little with large text.
 */
// drawStyle on text is stable in current Compose; the opt-in only covers older releases that marked it experimental.
@OptIn(androidx.compose.ui.text.ExperimentalTextApi::class)
@Composable
private fun BannerTime(digits: String, suffix: String?, compact: Boolean, bright: Boolean, modifier: Modifier) {
    val density = LocalDensity.current
    val fontScale = density.fontScale
    val grow = (1f + (fontScale - 1f) * 0.35f).coerceIn(1f, 1.2f)
    val size = ((if (compact) 24f else 36f) * grow / fontScale).sp
    val ink = if (bright) Color(0xFF141210) else Color.White
    val outline = if (bright) Color.White.copy(alpha = 0.85f) else Color.Black.copy(alpha = 0.60f)
    // The outline shows about 1 dp at 24, 1.5 dp at 36: the stroke straddles the glyph's edge and the fill
    // covers its inner half, so it is drawn twice as wide. The AM/PM gets one in proportion to its size.
    val outlineDp = (if (compact) 1f else 1.5f) * grow
    val strokePx = with(density) { (outlineDp * 2f).dp.toPx() }
    val stroke = Stroke(width = strokePx, join = StrokeJoin.Round)
    val suffixStroke = Stroke(width = strokePx * 0.6f, join = StrokeJoin.Round)
    fun text(suffixDraw: DrawStyle) = buildAnnotatedString {
        append(digits)
        if (suffix != null) withStyle(SpanStyle(fontSize = 0.45.em, fontWeight = FontWeight.Medium, letterSpacing = 0.em,
            drawStyle = suffixDraw)) {
            append(TimeMath.THIN + suffix)
        }
    }
    val fillText = text(androidx.compose.ui.graphics.drawscope.Fill)
    val strokeText = text(suffixStroke)
    val base = TextStyle(color = ink, fontSize = size, lineHeight = size, fontWeight = FontWeight.SemiBold,
        letterSpacing = (-0.02).em, fontFeatureSettings = "tnum")
    val shade = if (bright) Color.White else Color.Black
    val near = with(density) {
        if (bright) Shadow(shade.copy(alpha = 0.35f), Offset.Zero, 2.dp.toPx())
        else Shadow(shade.copy(alpha = 0.25f), Offset(0f, 1.dp.toPx()), 2.dp.toPx())
    }
    val wide = with(density) { Shadow(shade.copy(alpha = if (bright) 0.45f else 0.35f), Offset.Zero, 8.dp.toPx()) }
    // The outline (with the wide shadow) under the fill (with the near one): the same text twice, as on the iPhone.
    Box(modifier) {
        Text(strokeText, style = base.copy(color = outline, shadow = wide, drawStyle = stroke), maxLines = 1, softWrap = false)
        Text(fillText, style = base.copy(shadow = near, drawStyle = androidx.compose.ui.graphics.drawscope.Fill),
            maxLines = 1, softWrap = false)
    }
}

/** The pill under a city's name: a small icon and the status, tinted, in a faint outline of its colour. */
@Composable
private fun StatusPill(status: RowStatus, showDetail: Boolean, cap: Float) {
    val color = status.kind.color
    val shape = RoundedCornerShape(50)
    val icon = when (status.kind) {
        StatusKind.WORKING -> painterResource(R.drawable.ic_briefcase)
        StatusKind.OFF_HOURS -> painterResource(R.drawable.ic_moon)
        StatusKind.WEEKEND, StatusKind.DAY_OFF -> painterResource(R.drawable.ic_sun)
        StatusKind.HOLIDAY -> rememberVectorPainter(Icons.Filled.Star)
    }
    val detail = status.detail?.takeIf { showDetail }
    Row(Modifier.clip(shape).border(1.dp, color.copy(alpha = 0.35f), shape).padding(horizontal = 7.dp, vertical = 1.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size((11f / cap).dp.coerceAtLeast(9.dp)))
        Spacer(Modifier.width(4.dp))
        Text(buildAnnotatedString {
            append(status.text)
            if (detail != null) withStyle(SpanStyle(fontWeight = FontWeight.Medium, color = color.copy(alpha = 0.85f))) { append(" · $detail") }
        }, fontSize = (11.5f / cap).sp, lineHeight = (15f / cap).sp, fontWeight = FontWeight.SemiBold, color = color,
            maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
    }
}

/**
 * One city, as its own card: the skyline banner across the top with the time there on it; under it,
 * the city's name, its zone ("UTC−8", or "+1 d · UTC+9" on another day) and what it's doing (a
 * pill) on the left, and its five hour tiles (−2 to +2 hr) on the right. A person's card names the
 * person, with their city before the zone.
 */
@Composable
fun CityRow(store: Store, place: Place, height: Dp, modifier: Modifier = Modifier, onLongPress: () -> Unit = {}) {
    val moment = store.moment
    val time = TimeMath.time(moment, place.zone, store.use24h)
    val shift = TimeMath.dayShift(moment, place.zone, store.home)
    val utc = TimeMath.offsetLabel(TimeMath.offsetSeconds(place.zone, moment))
    val here = store.isHere(place)
    val tall = height >= Rows.tallFrom
    // Said by TalkBack: how it relates to you, the day, and work (when that setting is on).
    val relation = TimeMath.relative(moment, place.zone, store.home)
        ?: if (place.zone.id == store.home.id) "Your time" else "Same time"
    val dayNote = when (shift) { 0 -> null; 1 -> "tomorrow there"; -1 -> "yesterday there"; else -> "${kotlin.math.abs(shift)} days ${if (shift > 0) "ahead" else "behind"}" }
    // Worked out once a quarter-hour (the detail scans ahead), not every second.
    val quarter = TimeMath.quarter(moment)
    val status = if (!store.showWorkHours) null else remember(place, quarter, store.workStart, store.workEnd, store.use24h, tall,
        Holidays.loaded, Holidays.counted) {
        CityStatus.of(place, quarter, store.workStart, store.workEnd, store.use24h, detail = tall)
    }
    val zoneText = listOfNotNull(
        place.person?.let { place.name },
        if (shift != 0) (if (shift > 0) "+$shift d" else "−${-shift} d") else null,
        utc,
    ).joinToString(" · ")
    val cap = maxOf(1f, LocalDensity.current.fontScale / 1.15f)
    val banner = Rows.bannerHeight(height)
    Column(modifier.fillMaxWidth().height(height)
        .semantics(mergeDescendants = true) {
            contentDescription = listOfNotNull(place.title, place.person?.let { place.name }, if (here) "My Location" else null,
                time, relation, utc, dayNote, status?.spoken).joinToString(", ")
        }) {
        SkylineBanner(store, place, compact = !tall, modifier = Modifier.fillMaxWidth().height(banner))
        BoxWithConstraints(Modifier.fillMaxWidth().weight(1f).padding(horizontal = Strip.pad)) {
            val labelWidth = Strip.labelWidth(maxWidth)
            val tileHeight = minOf(Rows.tileHeight, maxHeight - 10.dp).coerceAtLeast(30.dp)
            // Too little room under the banner for three lines: the zone gives way (TalkBack still says it).
            val showZone = maxHeight >= 70.dp || status == null
            Row(Modifier.fillMaxSize()
                .drawWithContent {
                    drawContent()
                    // The lens: an outline around the selected hour's tile.
                    val tilesLeft = (labelWidth + Strip.labelGap).toPx()
                    val gapPx = Strip.gap.toPx()
                    val pitch = (size.width - tilesLeft + gapPx) / 5
                    val outset = Strip.lensOutset.toPx()
                    val stroke = Strip.lensStroke.toPx()
                    val tileTop = (size.height - tileHeight.toPx()) / 2
                    val top = tileTop - outset
                    val bottom = tileTop + tileHeight.toPx() + outset
                    val left = tilesLeft + 2 * pitch - outset
                    val width = pitch - gapPx + 2 * outset
                    val radius = CornerRadius(Strip.lensRadius.toPx())
                    drawRoundRect(white(0.06f), topLeft = Offset(left, top), size = Size(width, bottom - top), cornerRadius = radius)
                    drawRoundRect(Palette.primary, topLeft = Offset(left + stroke / 2, top + stroke / 2),
                        size = Size(width - stroke, bottom - top - stroke),
                        cornerRadius = CornerRadius(radius.x - stroke / 2), style = Stroke(stroke))
                },
                verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.width(labelWidth), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(place.title, fontSize = (17f / cap).sp, lineHeight = (21f / cap).sp, fontWeight = FontWeight.SemiBold,
                            color = Palette.primary, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                        // Where you are: a small pin after the name, as on the Mac.
                        if (here) Icon(Icons.Filled.LocationOn, contentDescription = null, tint = Palette.muted,
                            modifier = Modifier.padding(start = 4.dp).size(12.dp))
                    }
                    if (showZone) {
                        // Shrinks to fit before it would cut, so "UTC+5:30" shows whole (as on the Mac).
                        var zoneShrink by remember(zoneText) { mutableFloatStateOf(1f) }
                        Text(zoneText, style = tnum, fontSize = (12f / cap * zoneShrink).sp, lineHeight = (15f / cap).sp, color = Palette.muted,
                            maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis,
                            onTextLayout = { if (it.didOverflowWidth && zoneShrink > 0.75f) zoneShrink = (zoneShrink - 0.05f).coerceAtLeast(0.75f) })
                    }
                    if (status != null) {
                        Spacer(Modifier.height(1.dp))
                        StatusPill(status, showDetail = tall, cap = cap)
                    }
                }
                Spacer(Modifier.width(Strip.labelGap))
                HourTiles(store, place, Modifier.weight(1f), onLongPress, tileHeight)
            }
        }
    }
}

/**
 * A city's hours as five tiles, two before the selected hour and two after, as on the Mac panel:
 * each tile the colour of the day there at that hour (warm black at night, greys at dawn and dusk,
 * cream by day), dimmed outside working hours, the day's name and a mark where a new day starts,
 * the outer tiles fading softly at the edges. The lens on the selected hour is drawn by the row.
 * Tap a tile to go to that hour; drag to move through time in quarter-hours.
 */
@Composable
fun HourTiles(store: Store, place: Place, modifier: Modifier, onLongPress: () -> Unit, tileHeight: Dp = Strip.tileHeight) {
    val anchor = TimeMath.hourAnchor(store.moment, store.home)
    val starts = (-2..2).map { anchor.plusSeconds(it * 3600L) }
    fun newDay(start: Instant) = start.atZone(place.zone).toLocalDate() != start.minusSeconds(3600).atZone(place.zone).toLocalDate()
    val off = if (store.showWorkHours) WorkWeek.offLabel(place, store.moment, store.workStart, store.workEnd) else null
    val state = TimeMath.time(store.moment, place.zone, store.use24h) + if (store.showWorkHours) ", ${(off ?: "working").lowercase()}" else ""
    val gapPx = with(LocalDensity.current) { Strip.gap.toPx() }
    var widthPx by remember { mutableFloatStateOf(1f) }
    Box(modifier.fillMaxWidth().height(tileHeight)
        .onSizeChanged { widthPx = it.width.toFloat().coerceAtLeast(1f) }
        .pointerInput(place.id) {
            detectTapGestures(onLongPress = { onLongPress() }, onTap = { o ->
                val pitch = (widthPx + gapPx) / 5
                val k = (o.x / pitch).toInt().coerceIn(0, 4) - 2
                if (k != 0 || !store.isNow) store.jump(TimeMath.hourAnchor(store.moment, store.home).plusSeconds(k * 3600L))
            })
        }
        .pointerInput(place.id) {
            var base = 0
            var dx = 0f
            detectHorizontalDragGestures(
                onDragStart = { base = store.offsetMinutes; dx = 0f },
            ) { _, amount ->
                dx += amount
                val minutes = -dx / ((widthPx + gapPx) / 5) * 60
                store.scrubToQuarterNear(base + minutes.toDouble())
            }
        }
        .semantics(mergeDescendants = true) {
            contentDescription = "Hours in ${place.title}"
            stateDescription = state
            customActions = listOf(
                CustomAccessibilityAction("Next hour") { store.travel(1); true },
                CustomAccessibilityAction("Previous hour") { store.travel(-1); true },
            )
        }) {
        // The Mac's edge fade: the outer tiles soften to nothing at the panel's sides.
        Box(Modifier.matchParentSize().clearAndSetSemantics {}
            .graphicsLayer(compositingStrategy = CompositingStrategy.Offscreen)
            .drawWithContent {
                drawContent()
                drawRect(Brush.horizontalGradient(0f to Color.Transparent, 0.11f to Color.Black, 0.89f to Color.Black, 1f to Color.Transparent),
                    blendMode = BlendMode.DstIn)
            }) {
            Row(Modifier.matchParentSize(), horizontalArrangement = Arrangement.spacedBy(Strip.gap)) {
                starts.forEachIndexed { i, start ->
                    HourTile(store, place, start, center = i == 2, newDay = newDay(start), modifier = Modifier.weight(1f).fillMaxHeight())
                }
            }
            // Midnight: a crimson mark in the gap before the tile where a new day starts, as on the Mac.
            Canvas(Modifier.matchParentSize()) {
                val pitchPx = (size.width + Strip.gap.toPx()) / 5
                val inset = 8.dp.toPx()
                for (i in 1..4) {
                    if (!newDay(starts[i])) continue
                    drawRoundRect(Palette.crimson, topLeft = Offset(i * pitchPx - Strip.gap.toPx() / 2 - 1.dp.toPx(), inset),
                        size = Size(2.dp.toPx(), size.height - 2 * inset), cornerRadius = CornerRadius(1.dp.toPx()))
                }
            }
        }
    }
}

/** One hour tile, as on the Mac: the day's colour there at that hour, flat, with the hour in a colour that reads on it. */
@Composable
private fun HourTile(store: Store, place: Place, start: Instant, center: Boolean, newDay: Boolean, modifier: Modifier) {
    val z = start.atZone(place.zone)
    val hour = z.hour
    val minute = z.minute
    val fill = DayColor.at(hour + minute / 60.0)
    val text = if (DayColor.isLight(fill)) Palette.bg else Palette.secondary
    val fillColor by animateColorAsState(Color(fill), tween(250), label = "tile")
    val textColor by animateColorAsState(text, tween(250), label = "tile text")
    // Outside working hours, as on the Mac: the tile a little quieter.
    val dim = store.showWorkHours && !store.isWorking(place, start.plusSeconds(1800))
    val shape = RoundedCornerShape(Strip.tileRadius)
    val use24h = store.use24h
    // Large text is capped, then shrinks to fit the tile (to 60%), as on the Mac.
    val cap = maxOf(1f, LocalDensity.current.fontScale / 1.15f)
    var shrink by remember(hour, minute, use24h) { mutableFloatStateOf(1f) }
    val scale = shrink / cap
    val label = buildAnnotatedString {
        append(if (use24h) "%02d".format(hour) else "${if (hour % 12 == 0) 12 else hour % 12}")
        if (minute != 0) withStyle(SpanStyle(fontSize = (10 * scale).sp)) { append(":%02d".format(minute)) }
        // A thin space before AM/PM, set small, so "12:30AM" stays on one line.
        if (!use24h) withStyle(SpanStyle(fontSize = ((if (minute != 0) 7 else 9) * scale).sp)) {
            append(" " + if (hour < 12) "AM" else "PM")
        }
    }
    Box(modifier.clip(shape).background(fillColor.copy(alpha = if (dim) 0.72f else 1f)), contentAlignment = Alignment.Center) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            // Half-hour zones ("10:30 PM") set a size smaller, so the whole label fits the tile.
            Text(label, style = tnum, fontSize = ((if (minute != 0 && !use24h) 13 else 16) * scale).sp, lineHeight = (19 * scale).sp,
                fontWeight = if (center) FontWeight.SemiBold else FontWeight.Medium,
                color = textColor, maxLines = 1, softWrap = false,
                onTextLayout = { if (it.didOverflowWidth && shrink > 0.6f) shrink = (shrink - 0.1f).coerceAtLeast(0.6f) })
            if (newDay) Text(TimeMath.weekday(start, place.zone).uppercase(), fontSize = (9 / cap).sp, lineHeight = (11 / cap).sp,
                fontWeight = FontWeight.Medium, letterSpacing = 0.5.sp, color = textColor, maxLines = 1, softWrap = false)
        }
    }
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
fun SearchResults(store: Store, query: String, searched: Pair<String, List<CityEntry>>?, modifier: Modifier, added: (String?) -> Unit) {
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
            Row(Modifier.fillMaxWidth().clickable(enabled = !have && store.canAdd, onClickLabel = "Add") { added(store.add(entry)) }
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

    BoxWithConstraints(Modifier.fillMaxWidth().height(40.dp)) {
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
        Box(Modifier.align(Alignment.TopCenter).padding(top = 14.dp).width(2.dp).height(24.dp)
            .clip(RoundedCornerShape(50)).background(Palette.primary))
    }
}

/** One quarter-hour on the ruler: a tall tick and its hour on the hour (the day at midnight), shorter ones between. */
@Composable
private fun RulerTick(at: java.time.ZonedDateTime, use24h: Boolean, modifier: Modifier) {
    val hour = at.hour; val minute = at.minute
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.height(12.dp).wrapContentWidth(unbounded = true), contentAlignment = Alignment.Center) {
            if (minute == 0) Text(
                if (hour == 0) at.dayOfWeek.getDisplayName(java.time.format.TextStyle.SHORT, java.util.Locale.ENGLISH).uppercase()
                else if (use24h) "%02d".format(hour) else "${if (hour % 12 == 0) 12 else hour % 12}${TimeMath.THIN}${if (hour < 12) "AM" else "PM"}",
                fontSize = 11.sp, lineHeight = 12.sp, maxLines = 1, softWrap = false,
                fontWeight = if (hour == 0) FontWeight.SemiBold else FontWeight.Medium,
                color = if (hour == 0) Palette.primary else white(0.6f))
        }
        Spacer(Modifier.height(3.dp))
        Box(Modifier.width(if (minute == 0) 1.5.dp else 1.dp)
            .height(if (minute == 0) 14.dp else if (minute == 30) 9.dp else 5.dp)
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

    /** Twilight is within an hour of sunrise or sunset, either side. */
    fun phase(place: Place, at: java.time.Instant): Phase {
        fun isDay(t: java.time.Instant): Boolean? = when (Sun.phase(place, t)) {
            is Sun.Phase.Day, Sun.Phase.AllDay -> true
            is Sun.Phase.Night, Sun.Phase.AllNight -> false
            null -> null
        }
        val now = isDay(at) ?: return if (at.atZone(place.zone).hour in 7..18) Phase.DAY else Phase.NIGHT
        if (isDay(at.minusSeconds(3600)) != now || isDay(at.plusSeconds(3600)) != now) return Phase.TWILIGHT
        return if (now) Phase.DAY else Phase.NIGHT
    }

    /** Top and bottom of the gradient. */
    fun colors(phase: Phase): Pair<Color, Color> = when (phase) {
        Phase.DAY -> Color(0xFF3D74B0) to Color(0xFF1C3A5E)
        Phase.TWILIGHT -> Color(0xFF4F78A3) to Color(0xFF24384F)
        Phase.NIGHT -> Color(0xFF141E3C) to Color(0xFF0A0E1C)
    }
}
