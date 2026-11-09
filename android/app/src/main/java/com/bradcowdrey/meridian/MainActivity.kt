package com.bradcowdrey.meridian

import android.Manifest
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.animation.Crossfade
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
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
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.yield
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
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
import androidx.compose.ui.geometry.Rect
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
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
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
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onPlaced
import androidx.compose.ui.graphics.vector.rememberVectorPainter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import java.time.Instant
import kotlin.math.roundToInt

/** The Two Degrees colours the app and widgets use: black, white at opacities, sky blues and its accents. */
object Palette {
    val bg = Color(0xFF000000)
    val tile = Color(0xFF262626)
    val border = Color(0x26FFFFFF)
    val primary = Color.White
    /** White 92%, as the iPhone's Theme.secondary: the card's zone line, the weakest text over a photo. */
    val secondary = Color(0xEBFFFFFF)
    val muted = Color(0x99FFFFFF)
    val faint = Color(0x66FFFFFF)
    /** The new day's weekday tag above the midnight hour tile: the Two Degrees sunrise accent. */
    val midnight = Color(0xFFF2C66D)
    val black = Color.Black
    val notice = Color(0xFFF2A65A)
    val destructive = Color(0xFFE5484D)
    /** Cards on the flat sheets. Two Degrees uses black 20% over its sky; our sheets are flat, so white. */
    val cardFill = Color(0x14FFFFFF)
    val cardBorder = Color(0x1FFFFFFF)
    val chipOff = Color(0x1FFFFFFF)
    /** The Two Degrees bottom bar. */
    // Nearly opaque: Android has no blur behind a bar, so cards must not show through the ruler.
    val barBg = Color(0xFF101216)
    /** The Two Degrees search field. */
    val searchBg = Color(0xFF1E1E22)
    val sun = Color(0xFFF2C66D)
    val moon = Color(0xFFEFE3CC)
    val pickerAccent = Color(0xFF3D74B0)
    val switchOn = Color(0xFF3D74B0)
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

/**
 * Section icons not in Material's core icon set, drawn from Material's own paths (24 dp grid): a clock for
 * the Time sections (iOS "clock") and a grid for Find a Time's Every hour (iOS "tablecells").
 */
object Glyphs {
    private fun glyph(name: String, path: String): ImageVector =
        ImageVector.Builder(name = name, defaultWidth = 24.dp, defaultHeight = 24.dp, viewportWidth = 24f, viewportHeight = 24f)
            .addPath(pathData = androidx.compose.ui.graphics.vector.addPathNodes(path),
                fill = androidx.compose.ui.graphics.SolidColor(Color.Black))
            .build()

    /** Material "schedule". */
    val clock: ImageVector by lazy {
        glyph("Clock", "M11.99 2C6.47 2 2 6.48 2 12s4.47 10 9.99 10C17.52 22 22 17.52 22 12S17.52 2 11.99 2zM12 20c-4.42 0-8-3.58-8-8s3.58-8 8-8 8 3.58 8 8-3.58 8-8 8zM12.5 7H11v6l5.25 3.15.75-1.23-4.5-2.67z")
    }

    /** Material "grid_view". */
    val grid: ImageVector by lazy {
        glyph("Grid", "M3 3v8h8V3H3zm6 6H5V5h4v4zm-6 4v8h8v-8H3zm6 6H5v-4h4v4zm4-16v8h8V3h-8zm6 6h-4V5h4v4zm-6 4v8h8v-8h-8zm6 6h-4v-4h4v4z")
    }
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
        // One step lighter than the digits (Go to a Time's Medium answer), so the time leads, as on the iPhone.
        withStyle(SpanStyle(fontSize = 0.42.em, baselineShift = BaselineShift(0.5f), fontWeight = FontWeight.Normal)) {
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
        // CI diagnostics only (screenshot mode): switch single parts of the city cards off.
        if (demo) Diag.off = intent.getStringExtra("off")?.split(',')?.map { it.trim() }?.toSet() ?: emptySet()
        // Screenshot mode never reads, fetches or exports photos for the widgets (the first frame waits on nothing).
        CityPhotos.demo = demo
        val store = Store(applicationContext, demo = demo && screen != "terms")
        this.store = store
        setContent {
            MaterialTheme(colorScheme = darkColorScheme(
                // White highlights inside the app, as in Two Degrees.
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
    // The ruler and Now, in a bar at the bottom as in Two Degrees (the time control); the groups pinned
    // at the top.
    val showBar = !adding && !editing && store.places.isNotEmpty()
    val showGroupBar = showBar && (store.customGroups.isNotEmpty() || store.continentChipCount >= 2)
    val customFilter = store.groupFilter?.takeIf { it in store.chipGroups && !store.isContinent(it) }

    Scaffold(
        // The list sits on black, as in Two Degrees.
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
                else if (showGroupBar) {
                    Column(Modifier.fillMaxWidth().background(Palette.barBg)) {
                        GroupBar(store, open)
                        HorizontalDivider(thickness = 0.5.dp, color = white(0.15f))
                    }
                }
            }
        },
        bottomBar = {
            if (showBar) {
                Column(Modifier.fillMaxWidth().background(Palette.barBg).navigationBarsPadding()) {
                    HorizontalDivider(thickness = 0.5.dp, color = white(0.15f))
                    if (!Diag.has("footer")) TimeShifter(store) { open("date") }
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
                    // One to five cities share the height between the top bar and the bottom bar
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
                // The cards scroll under the translucent bottom bar, as in Two Degrees. A list that scrolls ends
                // 16 dp past the bar, so the last card (and its status) scrolls fully clear of it.
                val dir = LocalLayoutDirection.current
                val listPadding = if (fit) padding else PaddingValues(
                    start = padding.calculateStartPadding(dir), top = padding.calculateTopPadding(),
                    end = padding.calculateEndPadding(dir), bottom = padding.calculateBottomPadding() + 16.dp)
                LazyColumn(Modifier.fillMaxSize(), contentPadding = listPadding) {
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
                        // Every city is its own rounded card, filled by its skyline: its time, name, zone and status
                        // at the bottom left and its five hour tiles at the bottom right.
                        // Touch and hold a card for its own actions (a tap does nothing, so scrolling never
                        // opens them by accident); dragging its hour tiles still moves every city's time.
                        val first = i == 0
                        val last = i == rows.lastIndex
                        val shape = RoundedCornerShape(Rows.radius)
                        val count = rows.size
                        // One Now capsule down the list: each card's item draws its slice over itself (not in Edit List).
                        val capsule = if (editing || Diag.has("capsule")) Modifier else Modifier.drawWithContent {
                            drawContent()
                            drawNowCapsule(i, count, rowHeight, first)
                        }
                        Box(capsule.padding(start = Strip.margin, end = Strip.margin, top = if (first) Rows.edge else 0.dp,
                            bottom = if (last) Rows.edge else Rows.gap)
                            .fillMaxWidth().clip(shape).background(Palette.tile)) {
                            if (editing) EditRow(store, place)
                            else if (Diag.has("rows")) Box(Modifier.fillMaxWidth().height(rowHeight))
                            else {
                                CityRow(store, place, height = rowHeight, modifier = Modifier
                                    .pointerInput(place.id) {
                                        detectTapGestures(onLongPress = { openActions() })
                                    }
                                    .semantics { onLongClick(label = "Actions for ${place.title}") { actions = true; true } },
                                    first = first, onLongPress = { openActions() })
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
        // The trailing 40 dp fades while there's more to scroll, so a cut chip ("+ Ne") reads as "more", not a clipped word.
        modifier = Modifier.fillMaxWidth().fadeEnd(state).selectableGroup().semantics { contentDescription = "Groups" }) {
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
 * Moves every city through time from the bottom bar, in thumb reach as in Two Degrees: Now,
 * the ruler (quarter-hours, two days either way) and Go to a Time. The tiles on every card tap to an hour and drag.
 */
@Composable
fun TimeShifter(store: Store, goToTime: () -> Unit) {
    Column(Modifier.fillMaxWidth()) {
        if (!store.hasScrubbed) {
            // The iPhone's words; two lines allowed at large text (1.3x and up), so it never ends in an ellipsis.
            Text("Drag the hours or the ruler.", fontSize = 13.sp, lineHeight = 17.sp, fontWeight = FontWeight.Medium,
                color = white(0.7f), textAlign = TextAlign.Center, maxLines = if (LocalDensity.current.fontScale >= 1.3f) 2 else 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.fillMaxWidth().padding(top = 6.dp, start = 16.dp, end = 16.dp).heightIn(min = 17.dp))
        }
        // Now on the left, the ruler filling the middle, Go to a Time at the far right.
        Row(Modifier.fillMaxWidth().padding(start = 12.dp, end = 4.dp, top = 6.dp, bottom = 4.dp).height(48.dp),
            verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            NowButton(store)
            Box(Modifier.weight(1f)) { TimeRuler(store) }
            IconButton(onClick = goToTime) { Icon(Icons.Filled.DateRange, contentDescription = "Go to a Time", tint = Palette.primary) }
        }
    }
}

/**
 * Now: a large, readable pill. At now, light text on a faint glass fill with a hairline edge (and off);
 * moved through time, filled white with black text (as a selected chip), the action that brings you back.
 */
@Composable
fun NowButton(store: Store) {
    val atNow = store.isNow
    val shape = RoundedCornerShape(50)
    Box(Modifier.defaultMinSize(minWidth = 68.dp, minHeight = 44.dp).height(44.dp).clip(shape)
        .background(if (atNow) white(0.14f) else NowFill)
        .then(if (atNow) Modifier.border(0.5.dp, white(0.25f), shape) else Modifier)
        .clickable(enabled = !atNow, onClickLabel = "Back to now") { store.backToNow() }
        .semantics { contentDescription = if (atNow) "Now" else "Back to now" }
        .padding(horizontal = 18.dp),
        contentAlignment = Alignment.Center) {
        Text("Now", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = if (atNow) NowFill else NowInk,
            maxLines = 1, softWrap = false)
    }
}

/** The Now button's white and the black ink on it (as a selected chip). */
private val NowFill = Color(0xFFFFFFFF)
private val NowInk = Color(0xFF000000)

/**
 * The city list's geometry, as the Mac panel's strip: shared by every row and the Now capsule down the
 * list, so the capsule sits exactly over the centre tile column. One even gutter between tiles.
 */
object Strip {
    /** Screen edge to the panel. */
    val margin = 12.dp
    /** Panel edge to the names and the tiles. */
    val pad = 10.dp
    /** Screen edge to the names and the tiles. */
    val inset = margin + pad
    val panelRadius = 20.dp
    /** Above the first row and below the last, inside the panel (with the row's own half gutter, the panel's inset). */
    val panelPadTop = 7.dp
    /** Between tiles, across and down. */
    val gap = 6.dp
    val tileHeight = 44.dp
    val tileRadius = 9.dp
    /** The Now (centre) tile's width against each of the other four (about 12% wider); the gaps stay [gap]. */
    const val NOW_WIDTH = 1.12f
    /** The Now tile's extra height each side (above and below the other tiles' centre line). */
    val nowGrow = 4.dp

    /** Each of the four other tiles' width, in a row of five [tiles] wide with [gap] between (px). */
    fun tileWidth(tiles: Float, gap: Float): Float = (tiles - 4 * gap) / (4 + NOW_WIDTH)
    /** Tile [i]'s left edge (0..4, the Now tile at 2), from the row's left (px). */
    fun tileLeft(i: Int, tiles: Float, gap: Float): Float {
        val w = tileWidth(tiles, gap)
        return i * (w + gap) + if (i > 2) (NOW_WIDTH - 1f) * w else 0f
    }
    /** Tile [i]'s width (px). */
    fun tileWidthAt(i: Int, tiles: Float, gap: Float): Float = tileWidth(tiles, gap) * (if (i == 2) NOW_WIDTH else 1f)

    /** Between the name column and the tiles. */
    val labelGap = 8.dp

    /** The name column, from the width inside the insets: about a third, as on the Mac; the tiles take the rest. */
    fun labelWidth(inner: Dp): Dp = (inner * 0.32f).coerceIn(100.dp, 150.dp)
}

/** The city cards' sizes: separate rounded cards, each filled by its city's skyline. */
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
    /** Card edge to the text and the tiles: left and right, the top, and the bottom (everything sits at the bottom). */
    val padH = 14.dp
    val padTop = 8.dp
    val padBottom = 12.dp

    /** The hour tiles' height on a card this tall: 52 dp, a little less on the shortest cards. */
    fun tileHeightFor(row: Dp): Dp = minOf(tileHeight, row - 50.dp).coerceAtLeast(34.dp)

    /** The name column's width, on a card this wide. */
    fun labelWidth(card: Dp): Dp = Strip.labelWidth(card - padH * 2)
}

/** What a city is doing now, for the pill under its name. */
enum class StatusKind(val color: Color) {
    WORKING(Color(0xFF9AD3A8)), OFF_HOURS(Color(0xFFD9DEE6)), WEEKEND(Color(0xFFF2C66D)), DAY_OFF(Color(0xFFF2C66D)), HOLIDAY(Color(0xFFF39A72))
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
 * The skyline photos built in (res/drawable-nodpi, listed in skylines.json), by city name, decoded once
 * and kept; and how each photo (built in or downloaded) is shaded for the time of day there. A city with
 * a night photo shows it as taken at night (and after sunset); only a city without one has its day
 * photo darkened, as before.
 */
object Skyline {
    /** The built-in photo for a city in this zone (by name or alias), if there is one. */
    fun photo(context: android.content.Context, city: String, zoneId: String): SkylineManifest.Photo? =
        SkylineManifest.photo(context, city, zoneId)

    /** Where each photo is cropped: a little above centre, so the tops of the towers stay in the card. */
    fun align(key: String?): Alignment = BiasAlignment(0f, biasY(key))

    fun biasY(key: String?): Float = when (key) {
        "sanfrancisco" -> -0.35f
        "london" -> -0.45f
        "newyork" -> -0.2f
        else -> -0.1f
    }

    /** Which built-in photo a city has (or none), once looked up: by "city|zone". */
    class Lookup(val photo: SkylineManifest.Photo?)
    private val lookups = java.util.concurrent.ConcurrentHashMap<String, Lookup>()

    /** The lookup for a city in this zone, if it's been done (a map read: safe in composition). */
    fun knownPhoto(city: String, zoneId: String): Lookup? = lookups["$city|$zoneId"]

    /** Looks up a city's built-in photo (the manifest and the resources). Call off the main thread. */
    fun lookUp(context: android.content.Context, city: String, zoneId: String): Lookup {
        knownPhoto(city, zoneId)?.let { return it }
        val found = Lookup(runCatching { photo(context, city, zoneId) }.getOrNull())
        // Kept only once the data files can be read (before that, the next card asks again).
        if (DataFiles.ready) lookups["$city|$zoneId"] = found
        return found
    }

    /**
     * Decoded photos by drawable: at least 48 MB (a 1000 x 500 photo is about 2 MB, so two photos, day and night,
     * for every card on screen and more), or an eighth of the app's memory where that's more, so a prefetched
     * other half never pushes out a photo on screen.
     */
    private val bitmaps = object : android.util.LruCache<Int, ImageBitmap>(
        maxOf(48 * 1024, (Runtime.getRuntime().maxMemory() / 1024L / 8L).coerceAtMost(Int.MAX_VALUE.toLong()).toInt())) {
        override fun sizeOf(key: Int, value: ImageBitmap): Int = (value.width * value.height * 4 / 1024).coerceAtLeast(1)
    }

    /**
     * The photo on screen first. Cards whose own photo (the one they show) is still being looked up or decoded:
     * changed on the main thread only (in each card's effects). The other half (day or night) is prefetched only
     * once this is 0, so it never competes with a photo on screen.
     */
    var pendingCurrent by mutableIntStateOf(0)
        private set
    private var everReady = false

    fun beginCurrent() { pendingCurrent++ }
    fun endCurrent() { pendingCurrent = (pendingCurrent - 1).coerceAtLeast(0) }
    /**
     * Logged once, the first time a card finds every photo on screen settled (pendingCurrent 0 for 0.4 s): CI can wait
     * for this line (with a timeout) before its screenshots, so a capture shows the finished cards. Main thread only.
     */
    fun markReady() { if (!everReady) { everReady = true; android.util.Log.i("Meridian", "photos ready") } }

    /** Decodes of photos on screen: two at a time, so the top cards finish first rather than all of them at once. */
    val currentDecodes: kotlinx.coroutines.CoroutineDispatcher =
        java.util.concurrent.Executors.newFixedThreadPool(2) { r -> Thread(r, "skyline-decode").apply { isDaemon = true } }
            .asCoroutineDispatcher()
    /** Prefetches of the other half: one at a time, at a low thread priority, after the photos on screen. */
    val prefetches: kotlinx.coroutines.CoroutineDispatcher =
        java.util.concurrent.Executors.newSingleThreadExecutor { r ->
            Thread(r, "skyline-prefetch").apply { isDaemon = true; priority = Thread.MIN_PRIORITY }
        }.asCoroutineDispatcher()
    /** Measuring a card's look (scrim boost, time ink): two at a time, so it never starves the city search on Default. */
    val measures: kotlinx.coroutines.CoroutineDispatcher =
        java.util.concurrent.Executors.newFixedThreadPool(2) { r -> Thread(r, "skyline-measure").apply { isDaemon = true } }
            .asCoroutineDispatcher()

    /** Drawables decoded at full size (sample 1): no wider copy exists, so any card can use them. */
    private val fullSize: MutableSet<Int> = java.util.concurrent.ConcurrentHashMap.newKeySet()

    /** Whether a cached copy is wide enough for a card [minWidth] px wide (a narrow card's copy isn't). */
    private fun wideEnough(id: Int, b: ImageBitmap, minWidth: Int): Boolean =
        minWidth <= 0 || b.width >= minWidth || id in fullSize

    /** A photo already decoded at least [minWidth] px wide (a cache read: safe in composition), or null. */
    fun cachedBitmap(id: Int, minWidth: Int = 0): ImageBitmap? =
        if (id == 0) null else bitmaps.get(id)?.takeIf { wideEnough(id, it, minWidth) }

    /**
     * A built-in photo, decoded once and kept, sampled down (by powers of two) to no less than [maxWidth]
     * px wide but near it. A copy kept from a narrower card is decoded again wider (the wider one is kept).
     * Reads and decodes the resource: call off the main thread (never in composition).
     */
    fun bitmap(context: android.content.Context, id: Int, maxWidth: Int): ImageBitmap? {
        if (id == 0) return null
        cachedBitmap(id, maxWidth)?.let { return it }
        var sample = 1
        val decoded = runCatching {
            val res = context.resources
            val bounds = android.graphics.BitmapFactory.Options().apply { inJustDecodeBounds = true }
            android.graphics.BitmapFactory.decodeResource(res, id, bounds)
            if (maxWidth > 0 && bounds.outWidth > 0) while (bounds.outWidth / (sample * 2) >= maxWidth) sample *= 2
            android.graphics.BitmapFactory.decodeResource(res, id, android.graphics.BitmapFactory.Options().apply { inSampleSize = sample })
        }.getOrNull() ?: return null
        if (sample == 1) fullSize.add(id)
        return decoded.asImageBitmap().also { bitmaps.put(id, it) }
    }

    private fun scale(m: FloatArray) = ColorFilter.colorMatrix(ColorMatrix(floatArrayOf(
        m[0], 0f, 0f, 0f, 0f,
        0f, m[1], 0f, 0f, 0f,
        0f, 0f, m[2], 0f, 0f,
        0f, 0f, 0f, 1f, 0f,
    )))

    /** Night: darker (about 45%) and a little cooler; dawn and dusk: a little warmer, about 15% darker; day as taken. */
    private val nightGain = floatArrayOf(0.400f, 0.459f, 0.522f)
    private val twilightGain = floatArrayOf(0.941f, 0.820f, 0.714f)
    private val dayGain = floatArrayOf(1f, 1f, 1f)
    private val night = scale(nightGain)
    private val twilight = scale(twilightGain)

    /** How a photo is shaded: as taken, warmed (dawn and dusk), or darkened (night, for a city with no night photo). */
    enum class Shade { NONE, WARM, NIGHT }

    /**
     * The shade for a card: a night photo is shown as taken; a day photo as before, by the phase (darkened at
     * night only when the city has no night photo, or it isn't read yet).
     */
    fun shadeFor(phase: Sky.Phase, nightPhoto: Boolean): Shade = when {
        nightPhoto -> Shade.NONE
        phase == Sky.Phase.NIGHT -> Shade.NIGHT
        phase == Sky.Phase.TWILIGHT -> Shade.WARM
        else -> Shade.NONE
    }

    private fun gain(shade: Shade): FloatArray = when (shade) {
        Shade.NIGHT -> nightGain
        Shade.WARM -> twilightGain
        Shade.NONE -> dayGain
    }

    fun filter(shade: Shade): ColorFilter? = when (shade) {
        Shade.NIGHT -> night
        Shade.WARM -> twilight
        Shade.NONE -> null
    }

    /** Whether the photo is bright behind the time, keyed by photo (day or night), shade, card shape, boost and where the time is (in steps of 0.05). */
    private val brightness = HashMap<String, Boolean>()
    /** The scrim's extra strength behind the name column, keyed by photo (day or night), shade and card shape. */
    private val boosts = HashMap<String, Float>()

    /**
     * The brightest a background may be (relative luminance) behind the name, zone and status: 0.09 keeps the
     * zone's white 85% at 13 sp at about 6:1, a margin over 4.5:1 without darkening day photos more than needed.
     */
    private const val LABEL_MAX = 0.09
    /** The share of the label rectangle's samples that must be no brighter than [LABEL_MAX] (all but the brightest 5%). */
    private const val LABEL_QUANTILE = 0.95f
    /** The grid a region of a photo is sampled at. */
    private const val SAMPLES_W = 24
    private const val SAMPLES_H = 12
    /** The most the scrim is boosted behind the name column (black at the left edge), for skies at luma 200 and up. */
    private const val BOOST_MAX = 0.55f

    /** The left scrim (as iOS CardScrim): black [LEFT_ALPHA] held to [LEFT_HOLD] of the width, past the longest names. */
    const val LEFT_ALPHA = 0.5f
    const val LEFT_HOLD = 0.34f
    /** Where the left scrim has eased out to nothing (smoothstep, as iOS). */
    const val LEFT_REACH = 0.78f
    /**
     * The left scrim's alpha at evenly spaced points from [LEFT_HOLD] to [LEFT_REACH]: smoothstep sampled at
     * quarters (0.5 x (1 - ease)). Drawn as two-colour bands between them, so it eases in and out with no edge.
     */
    val LEFT_KNOTS = floatArrayOf(0.5f, 0.421875f, 0.25f, 0.078125f, 0f)

    /** The x (fraction of the width) of knot [i] of [LEFT_KNOTS]. */
    fun leftKnotX(i: Int): Float = LEFT_HOLD + (LEFT_REACH - LEFT_HOLD) * i / (LEFT_KNOTS.size - 1)

    /** The left scrim's alpha at [x] (fraction of the width), exactly as drawn (linear between the knots). */
    fun leftAlpha(x: Float): Float {
        if (x <= LEFT_HOLD) return LEFT_ALPHA
        if (x >= LEFT_REACH) return 0f
        val t = (x - LEFT_HOLD) / (LEFT_REACH - LEFT_HOLD) * (LEFT_KNOTS.size - 1)
        val i = t.toInt().coerceIn(0, LEFT_KNOTS.size - 2)
        val f = t - i
        return LEFT_KNOTS[i] * (1f - f) + LEFT_KNOTS[i + 1] * f
    }

    /** How a photo's card is drawn: the scrim's [boost] behind the name column, and whether the time's spot is [bright]. */
    data class CardLook(val boost: Float, val bright: Boolean)

    /**
     * The look a photo is drawn with until its own is measured: white ink, and the full boost behind the
     * name column on a day photo (night photos are dark there), so the text is readable from the first frame.
     */
    fun provisionalLook(nightPhoto: Boolean): CardLook =
        CardLook(boost = if (nightPhoto || Diag.has("scrim")) 0f else BOOST_MAX, bright = false)

    private fun stepOf(width: Int, height: Int): Int = (width.toFloat() / height * 20f).roundToInt().coerceAtLeast(1)
    private fun boostKey(id: String, shade: Shade, width: Int, height: Int) = "$id/${shade.name}/${stepOf(width, height)}"
    private fun brightKey(id: String, shade: Shade, width: Int, height: Int, region: TimeRegion, boost: Float) =
        "$id/${shade.name}/${stepOf(width, height)}/$boost/${region.key}"

    /** The card's look if it's been measured (map reads only: safe in composition), else null. */
    fun cachedLook(id: String, shade: Shade, width: Int, height: Int, region: TimeRegion): CardLook? {
        if (width <= 0 || height <= 0) return null
        val boost = if (Diag.has("scrim")) 0f else synchronized(boosts) { boosts[boostKey(id, shade, width, height)] } ?: return null
        val bright = synchronized(brightness) { brightness[brightKey(id, shade, width, height, region, boost)] } ?: return null
        return CardLook(boost, bright)
    }

    /** Measures the card's look on its photo (crops, scales and sorts pixels): call off the main thread. */
    fun look(id: String, bitmap: ImageBitmap, biasY: Float, shade: Shade, width: Int, height: Int, region: TimeRegion): CardLook {
        val boost = if (Diag.has("scrim")) 0f else scrimBoost(id, bitmap, biasY, shade, width, height)
        return CardLook(boost, photoIsBright(id, bitmap, biasY, shade, width, height, region, boost))
    }

    /**
     * Whether a photo is bright (relative luminance over 0.40) behind the time: the [region] of the card
     * (fractions of its width and height) where the time is drawn, as the photo is cropped and aligned
     * there, after the time-of-day shading and the card's scrim (with its [boost]) at that spot.
     */
    fun photoIsBright(id: String, bitmap: ImageBitmap, biasY: Float, shade: Shade, width: Int, height: Int, region: TimeRegion, boost: Float = 0f): Boolean {
        if (width <= 0 || height <= 0) return false
        val step = stepOf(width, height)
        val key = brightKey(id, shade, width, height, region, boost)
        synchronized(brightness) { brightness[key]?.let { return it } }
        val bright = try {
            val lum = regionLuminance(bitmap.asAndroidBitmap(), biasY, gain(shade), step / 20f, region)
            // The scrim blends in sRGB-encoded values, so in linear light it darkens by about (1 - a)^2.2.
            val a = scrimAlpha(region.centerX, region.centerY, boost)
            (lum * Math.pow(1.0 - a, 2.2).toFloat()) > 0.40f
        } catch (e: Exception) {
            false
        }
        synchronized(brightness) { brightness[key] = bright }
        return bright
    }

    /**
     * How much stronger the scrim is behind the name column on this photo (0 to [BOOST_MAX], in steps of 0.05):
     * enough that the 95th-percentile pixel over the whole name, zone and status rectangle, after the shading
     * and the scrim as drawn at each spot, is no brighter than [LABEL_MAX], so the text keeps about 6:1 on bright day photos.
     */
    fun scrimBoost(id: String, bitmap: ImageBitmap, biasY: Float, shade: Shade, width: Int, height: Int): Float {
        if (width <= 0 || height <= 0) return 0f
        val step = stepOf(width, height)
        val key = boostKey(id, shade, width, height)
        synchronized(boosts) { boosts[key]?.let { return it } }
        val boost = try {
            // Every sample over the whole label rectangle, each under the scrim as drawn at its own spot (the
            // left scrim eases out across the column, so the right end of a long name sits on the lightest part).
            val lums = regionSamples(bitmap.asAndroidBitmap(), biasY, gain(shade), step / 20f, LABELS)
            val n = lums.size
            // Each sample's spot, worked out once.
            val xs = FloatArray(n) { i -> LABELS.x0 + (i % SAMPLES_W + 0.5f) / SAMPLES_W * (LABELS.x1 - LABELS.x0) }
            val ys = FloatArray(n) { i -> LABELS.y0 + (i / SAMPLES_W + 0.5f) / SAMPLES_H * (LABELS.y1 - LABELS.y0) }
            // The 95th-percentile sample (sorted index q) is brighter than LABEL_MAX exactly when at least n - q samples
            // are: so count instead of sorting.
            val q = ((n - 1) * LABEL_QUANTILE).roundToInt()
            fun tooBright(b: Float): Boolean {
                var above = 0
                for (i in 0 until n) if (lums[i] * Math.pow(1.0 - scrimAlpha(xs[i], ys[i], b), 2.2) > LABEL_MAX) above++
                return above >= n - q
            }
            // The least boost (in steps of 0.05) that brings the 95th-percentile pixel down to LABEL_MAX: more boost
            // only darkens, so a binary search over the steps (about 4 tries rather than up to 12).
            val most = (BOOST_MAX * 20).roundToInt()
            var lo = 0
            var hi = most
            if (n == 0) hi = 0
            while (lo < hi) {
                val mid = (lo + hi) / 2
                if (tooBright(mid / 20f)) lo = mid + 1 else hi = mid
            }
            lo / 20f
        } catch (e: Exception) {
            0f
        }
        synchronized(boosts) { boosts[key] = boost }
        return boost
    }

    /** Where the name, zone and status sit on a card (fractions), for [scrimBoost]. */
    private val LABELS = TimeRegion(0f, 0.55f, 0.4f, 1f)

    /**
     * The card's scrim, as drawn by [CityRow]: black 60% at the bottom edge fading to 25% at 72% of the height
     * and nothing by half of it, plus black 50% held over the left [LEFT_HOLD] then easing to nothing by
     * [LEFT_REACH] of the width ([leftAlpha], as iOS CardScrim), plus the
     * [boost] (black, fading to nothing by 55% of the width) on bright photos.
     */
    fun scrimAlpha(x: Float, y: Float, boost: Float = 0f): Float {
        val v = when {
            y <= 0.5f -> 0f
            y <= 0.72f -> (y - 0.5f) / 0.22f * 0.25f
            else -> 0.25f + (minOf(y, 1f) - 0.72f) / 0.28f * 0.35f
        }
        val h = leftAlpha(x)
        val b = (boost * (1f - x / 0.55f)).coerceAtLeast(0f)
        return 1f - (1f - v) * (1f - h) * (1f - b)
    }

    /**
     * The drawn skyline: the bottom-left of the banner, behind the time, is mostly its (dark) buildings,
     * not its sky, so weigh the lower sky against the ink by how much the buildings cover. The near
     * buildings (opaque, 18-60% of the height, overlapping) cover ~85% of the bottom half and the far ones
     * add more, so even by day (#1C3A5E sky over #0A0E1C ink) this comes to ~0.11: dark in every phase.
     */
    fun drawnIsBright(phase: Sky.Phase): Boolean {
        val (_, sky, ink) = drawnColors(phase)
        val coverage = 0.85f
        return sky.luminance() * (1f - coverage) + ink.luminance() * coverage > 0.40f
    }

    private fun linear(c: Float): Double =
        if (c <= 0.04045f) c / 12.92 else Math.pow((c + 0.055) / 1.055, 2.4)

    /** The mean (or, with [quantile], that quantile of the) relative luminance of the photo in [region] of a card `aspect` wide by 1 high. */
    /**
     * The relative luminance (after [gain]) of [region] of the photo as the card crops it, as a grid of
     * [SAMPLES_W] x [SAMPLES_H] samples, row by row from the top left (empty if the photo is too small).
     */
    private fun regionSamples(src: android.graphics.Bitmap, biasY: Float, gain: FloatArray, aspect: Float, region: TimeRegion): DoubleArray {
        val iw = src.width.toFloat()
        val ih = src.height.toFloat()
        if (iw < 2f || ih < 2f) return DoubleArray(0)
        // ContentScale.Crop, then BiasAlignment(0, biasY), as the Image draws it.
        val bw = aspect
        val bh = 1f
        val s = maxOf(bw / iw, bh / ih)
        val offX = (bw - iw * s) / 2f
        val offY = (bh - ih * s) / 2f * (1f + biasY)
        val left = ((region.x0 * bw - offX) / s).coerceIn(0f, iw - 1f).toInt()
        val right = ((region.x1 * bw - offX) / s).coerceIn(left + 1f, iw).toInt()
        val top = ((region.y0 * bh - offY) / s).coerceIn(0f, ih - 1f).toInt()
        val bottom = ((region.y1 * bh - offY) / s).coerceIn(top + 1f, ih).toInt()
        val w = (right - left).coerceIn(1, src.width - left)
        val h = (bottom - top).coerceIn(1, src.height - top)
        val crop = android.graphics.Bitmap.createBitmap(src, left, top, w, h)
        val small = android.graphics.Bitmap.createScaledBitmap(crop, SAMPLES_W, SAMPLES_H, true)
        val px = IntArray(SAMPLES_W * SAMPLES_H)
        small.getPixels(px, 0, SAMPLES_W, 0, 0, SAMPLES_W, SAMPLES_H)
        if (small !== src && small !== crop) small.recycle()
        if (crop !== src) crop.recycle()
        val lums = DoubleArray(px.size)
        for ((i, c) in px.withIndex()) {
            val r = (((c shr 16) and 0xFF) / 255f * gain[0]).coerceIn(0f, 1f)
            val g = (((c shr 8) and 0xFF) / 255f * gain[1]).coerceIn(0f, 1f)
            val b = ((c and 0xFF) / 255f * gain[2]).coerceIn(0f, 1f)
            lums[i] = 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }
        return lums
    }

    private fun regionLuminance(src: android.graphics.Bitmap, biasY: Float, gain: FloatArray, aspect: Float, region: TimeRegion, quantile: Float? = null): Float {
        val lums = regionSamples(src, biasY, gain, aspect, region)
        if (lums.isEmpty()) return 0f
        if (quantile != null) {
            lums.sort()
            return lums[((lums.size - 1) * quantile.coerceIn(0f, 1f)).roundToInt()].toFloat()
        }
        return (lums.sum() / lums.size).toFloat()
    }

    /** The drawn skyline's sky (top, bottom) and buildings. */
    fun drawnColors(phase: Sky.Phase): Triple<Color, Color, Color> = when (phase) {
        Sky.Phase.DAY -> Triple(Color(0xFF3D74B0), Color(0xFF1C3A5E), Color(0xFF0A0E1C))
        Sky.Phase.TWILIGHT -> Triple(Color(0xFF4F78A3), Color(0xFF24384F), Color(0xFF0A0E1C))
        Sky.Phase.NIGHT -> Triple(Color(0xFF141E3C), Color(0xFF0A0E1C), Color(0xFF000000))
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
            Sky.Phase.NIGHT -> drawCircle(Color(0xFFEFE3CC).copy(alpha = 0.9f), 9 * u, Offset(w * 0.86f, h * 0.28f))
            Sky.Phase.TWILIGHT -> drawCircle(Color(0xFFF39A72).copy(alpha = 0.85f), 22 * u, Offset(w * 0.88f, h * 0.82f))
            Sky.Phase.DAY -> drawCircle(Color(0xFFFFFFFF).copy(alpha = 0.95f), 12 * u, Offset(w * 0.86f, h * 0.25f))
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
        val window = Color(0xFFF2C66D)
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

/** Where a card's time is drawn, as fractions of the card (in steps of 0.05), for the adaptive ink. */
data class TimeRegion(val x0: Float, val y0: Float, val x1: Float, val y1: Float) {
    val centerX: Float get() = (x0 + x1) / 2f
    val centerY: Float get() = (y0 + y1) / 2f
    val key: String get() = "$x0,$y0,$x1,$y1"

    companion object {
        /** Before the time is laid out: the left of the card, a little below the middle. */
        val DEFAULT = TimeRegion(0f, 0.45f, 0.4f, 0.7f)
        private fun q(v: Float): Float = (v.coerceIn(0f, 1f) * 20f).roundToInt() / 20f
        fun of(x0: Float, y0: Float, x1: Float, y1: Float): TimeRegion {
            val a = q(x0)
            val b = q(y0)
            return TimeRegion(a, b, maxOf(q(x1), a + 0.05f), maxOf(q(y1), b + 0.05f))
        }
    }
}

/** A card's photo as drawn: the bitmap, its time-of-day shade, and its measured look (scrim boost and ink). */
data class ShownPhoto(val bitmap: ImageBitmap, val shade: Skyline.Shade, val look: Skyline.CardLook)

/** How much a card's time grows with large text: a third of the font scale's growth, up to 1.3x. */
object BannerGrow {
    fun of(fontScale: Float): Float = (1f + (fontScale - 1f) * 0.35f).coerceIn(1f, 1.3f)
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
    val grow = BannerGrow.of(fontScale)
    val size = ((if (compact) 26f else 38f) * grow / fontScale).sp
    val ink = if (bright) Color(0xFF0A0E1C) else Color.White
    val outline = if (bright) Color.White.copy(alpha = 0.85f) else Color.Black.copy(alpha = 0.60f)
    // The outline shows about 1 dp at 26, 1.5 dp at 38: the stroke straddles the glyph's edge and the fill
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
    if (Diag.has("outline")) {
        Text(fillText, style = base.copy(shadow = if (Diag.has("shadows")) Shadow.None else near), modifier = modifier, maxLines = 1, softWrap = false)
        return
    }
    if (Diag.has("shadows")) Box(modifier) {
        Text(strokeText, style = base.copy(color = outline, drawStyle = stroke), maxLines = 1, softWrap = false)
        Text(fillText, style = base.copy(drawStyle = androidx.compose.ui.graphics.drawscope.Fill), maxLines = 1, softWrap = false)
    } else Box(modifier) {
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
    // A translucent dark backing, so the pill reads on any photo: black 68% (as iOS), so the status keeps its contrast over
    // bright day photos; the edge at half its colour so it shows. Text 12 sp semibold, the icon 12 dp (both grow with large text).
    val iconDp = 12f * LocalDensity.current.fontScale / cap
    Row(Modifier.clip(shape).background(Color.Black.copy(alpha = 0.68f)).border(1.dp, color.copy(alpha = 0.5f), shape)
        .padding(horizontal = 7.dp, vertical = 1.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, contentDescription = null, tint = color, modifier = Modifier.size(iconDp.dp.coerceAtLeast(11.dp)))
        Spacer(Modifier.width(4.dp))
        Text(buildAnnotatedString {
            append(status.text)
            if (detail != null) withStyle(SpanStyle(fontWeight = FontWeight.Medium)) { append(" · $detail") }
        }, fontSize = (12f / cap).sp, lineHeight = (16f / cap).sp, fontWeight = FontWeight.SemiBold, color = color,
            maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
    }
}

/**
 * One city, as its own card: the city's skyline fills the card (its photo, shaded for the time of day
 * there, or one drawn for it) under a soft scrim, darkest at the bottom and the left. Anchored to the
 * bottom, so the sky shows above: on the left the time there (white numbers on a dark photo, dark ones
 * on a bright photo, measured behind the time), the city's name, its zone ("UTC−8", or "+1 d · UTC+9"
 * on another day) and what it's doing (a pill); on the right its five hour tiles (−2 to +2 hr). A
 * person's card names the person, with their city before the zone. The Now capsule down the list is
 * drawn by the list ([drawNowCapsule]).
 */
@Composable
fun CityRow(store: Store, place: Place, height: Dp, modifier: Modifier = Modifier, first: Boolean = false, onLongPress: () -> Unit = {}) {
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
    val density = LocalDensity.current
    // Large text grows up to 1.3x here (Material's font scaling); past that the card reflows (the zone gives way first).
    val cap = maxOf(1f, density.fontScale / 1.3f)
    val context = LocalContext.current
    // The photo: built in, else downloaded once (in the background, if Settings allows), else drawn.
    val city = skylineCity(store, place)
    val phase = Sky.phase(place, moment)
    // Night (and after sunset): the city's night photo, as taken, where it has one.
    val wantsNight = Sky.look(place, moment) == Sky.Look.NIGHT
    // Which built-in photo the city has: looked up off the main thread (the manifest and the resources), once per city;
    // until then (null) the card shows its drawn skyline, so the first frame never waits for a photo.
    var lookup by remember(city, place.zoneId) { mutableStateOf(Skyline.knownPhoto(city, place.zoneId)) }
    LaunchedEffect(city, place.zoneId) {
        if (lookup != null) return@LaunchedEffect
        // Counted as a photo on screen still to come, so no prefetch starts before this card has its own photo.
        Skyline.beginCurrent()
        try {
            // (Only once the data files can be read, so a city is never taken for one without a photo too early.)
            while (lookup == null) {
                val found = withContext(Dispatchers.IO) { if (DataFiles.ready) Skyline.lookUp(context, city, place.zoneId) else null }
                if (found != null) lookup = found else delay(250)
            }
        } finally {
            Skyline.endCurrent()
        }
    }
    val photo = lookup?.photo
    val slug = remember(city, place.zoneId) { CityPhotos.slug(city, place.zoneId) }
    val download = store.downloadPhotos
    // No built-in photo: a downloaded one (never in screenshot mode). Its night photo is read only when it's night there.
    val useDownload = lookup != null && photo == null && !store.demo
    if (useDownload) {
        LaunchedEffect(slug, download, wantsNight) { CityPhotos.request(context, city, place.zoneId, place.country, download, night = wantsNight) }
    }
    val downloaded = if (useDownload) CityPhotos.bitmap(slug) else null
    // Where the time is on the card, for the adaptive ink (measured once it's laid out).
    var region by remember { mutableStateOf(TimeRegion.DEFAULT) }
    // The time's own box on the card (px), read only when the tiles' weekday tag is drawn (so the tag never sits on it).
    var timeBox by remember { mutableStateOf(Rect.Zero) }
    val card = remember { arrayOfNulls<LayoutCoordinates>(1) }
    val textShadow = if (Diag.has("shadows")) Shadow.None else with(density) { Shadow(Color.Black.copy(alpha = 0.6f), Offset(0f, 1.dp.toPx()), 3.dp.toPx()) }
    BoxWithConstraints(modifier.fillMaxWidth().height(height)
        .onPlaced { card[0] = it }
        .semantics(mergeDescendants = true) {
            contentDescription = listOfNotNull(place.title, place.person?.let { place.name }, if (here) "My Location" else null,
                time, relation, utc, dayNote, status?.spoken).joinToString(", ")
        }) {
        val widthPx = constraints.maxWidth
        val heightPx = constraints.maxHeight
        val usePhotos = !Diag.has("photos")
        // The one built-in photo the card shows: the night one when it's night there and the city has one, else the
        // day one. Decoded off the main thread (the one shown first); the photo shown stays until the next one is ready.
        val nightResId = photo?.nightResId ?: 0
        val resId = when {
            photo == null || !usePhotos -> 0
            wantsNight && nightResId != 0 -> nightResId
            else -> photo?.resId ?: 0
        }
        var decoded by remember(city, place.zoneId) { mutableStateOf<Pair<Int, ImageBitmap>?>(null) }
        LaunchedEffect(resId, widthPx) {
            if (resId == 0) { decoded = null; return@LaunchedEffect }
            val cached = Skyline.cachedBitmap(resId, widthPx)
            if (cached != null) { decoded = resId to cached; return@LaunchedEffect }
            // The photo on screen: on the decode pool (two at a time, top cards first), counted until it's ready.
            Skyline.beginCurrent()
            try {
                val b = withContext(Skyline.currentDecodes) { Skyline.bitmap(context, resId, widthPx) }
                // A failed decode keeps the photo already shown (never back to the drawn skyline for it).
                if (b != null) decoded = resId to b
            } finally {
                Skyline.endCurrent()
            }
        }
        // Then the other half (day or night) is decoded too, so a time jump (travel, Go to a Time) past sunrise or
        // sunset swaps photo to photo instead of waiting on a decode. Only once every card on screen has its own
        // photo (Skyline.pendingCurrent is 0), one at a time, at low priority: it never delays a photo on screen.
        val otherResId = when {
            resId == 0 || nightResId == 0 -> 0
            resId == nightResId -> photo?.resId ?: 0
            else -> nightResId
        }
        LaunchedEffect(otherResId, widthPx, decoded?.first == resId) {
            if (decoded?.first != resId && resId != 0) return@LaunchedEffect
            // Settled: no photo on screen still to come for 0.4 s (a card between its lookup and its decode counts).
            // Every card gets here (no night photo, a cached photo, no photo at all), so "photos ready" is always logged.
            var calm = 0
            while (calm < 2) { delay(200); calm = if (Skyline.pendingCurrent == 0) calm + 1 else 0 }
            Skyline.markReady()
            if (otherResId == 0) return@LaunchedEffect
            if (Skyline.cachedBitmap(otherResId, widthPx) == null)
                withContext(Skyline.prefetches) { yield(); Skyline.bitmap(context, otherResId, widthPx) }
        }
        // While the other half (day or night) of the same city's photo is read, the one shown stays.
        val bundled: Pair<Int, ImageBitmap>? = if (resId == 0) null else Skyline.cachedBitmap(resId, widthPx)?.let { resId to it }
            ?: decoded?.takeIf { it.first == resId || it.first == photo?.resId || (nightResId != 0 && it.first == nightResId) }
        val downloadedNight = if (useDownload && wantsNight && usePhotos && downloaded != null) CityPhotos.nightBitmap(slug) else null
        val bitmap: ImageBitmap? = when {
            !usePhotos -> null
            photo != null -> bundled?.second
            else -> downloadedNight ?: downloaded
        }
        val nightShown = if (photo != null) bundled != null && nightResId != 0 && bundled.first == nightResId
            else downloadedNight != null
        val shade = Skyline.shadeFor(phase, nightPhoto = nightShown)
        // Night with no night photo for this city (built in without one, or a download whose night search found none
        // or is still on its way): the drawn night skyline, not the day photo darkened. Drawing only: the photos above
        // still load and prefetch as before, so a jump back to day shows the day photo at once.
        val drawnNight = shade == Skyline.Shade.NIGHT && (photo == null || nightResId == 0)
        val biasY = Skyline.biasY(photo?.key)
        val id = (if (photo != null) "res:${photo.key}" else "dl:$slug") + if (nightShown) ":night" else ""
        // The scrim's boost behind the name column (so the white name, zone and status keep 4.5:1) and the adaptive
        // ink for the time (dark numbers on a bright photo), measured off the main thread after the shading and scrim.
        val lookKey = "$id/${shade.name}"
        var measured by remember(city, place.zoneId) { mutableStateOf<Pair<String, Skyline.CardLook>?>(null) }
        if (bitmap != null) LaunchedEffect(id, bitmap, shade, widthPx, heightPx, region) {
            val b = bitmap
            val got = Skyline.cachedLook(id, shade, widthPx, heightPx, region)
                ?: withContext(Skyline.measures) { Skyline.look(id, b, biasY, shade, widthPx, heightPx, region) }
            measured = lookKey to got
        }
        val look = if (bitmap == null) null else Skyline.cachedLook(id, shade, widthPx, heightPx, region)
            ?: measured?.takeIf { it.first == lookKey }?.second
        // What's drawn: the photo as soon as it's decoded. While its look is measured, the last photo shown stays;
        // with none yet, the new photo shows at once with a safe look (full boost on a day photo, white ink) that the
        // measured one replaces in place (only the scrim and ink change). The drawn skyline only while nothing is decoded.
        val last = remember(city, place.zoneId) { arrayOfNulls<ShownPhoto>(1) }
        val shown = when {
            // Never back to the drawn skyline while this city's photo was shown and its photo is on its way.
            bitmap == null -> if (photo != null && usePhotos) last[0] else null
            look != null -> ShownPhoto(bitmap, shade, look).also { last[0] = it }
            else -> last[0] ?: ShownPhoto(bitmap, shade, Skyline.provisionalLook(nightPhoto = nightShown))
        }
        // The boost eases (0.25 s) from the provisional look to the measured one, so the name column never flashes dark.
        val boostTarget = if (drawnNight) 0f else shown?.look?.boost ?: 0f
        val boost by animateFloatAsState(boostTarget, tween(250), label = "scrim boost")
        val bright = if (drawnNight) Skyline.drawnIsBright(phase) else shown?.look?.bright ?: Skyline.drawnIsBright(phase)
        Box(Modifier.matchParentSize().clearAndSetSemantics {}) {
            // Photo to drawn skyline (a city with no night photo at sunset, and back at sunrise) fades over 0.3 s too.
            // Inside a Crossfade there's no card BoxScope: its children fill the Crossfade's own box (fillMaxSize),
            // which matchParentSize sizes to the card. matchParentSize in here measured the photo at 0x0 (pass 6).
            Crossfade(targetState = shown != null && !drawnNight, modifier = Modifier.matchParentSize(), animationSpec = tween(300), label = "drawn night") { photoShown ->
                if (photoShown && shown != null) {
                    // Photo to photo (day to night, and back) crossfades over 0.3 s; the first photo just appears.
                    Crossfade(targetState = shown.bitmap to shown.shade, modifier = Modifier.fillMaxSize(), animationSpec = tween(300), label = "skyline") { (pic, how) ->
                        Image(pic, contentDescription = null, contentScale = ContentScale.Crop, alignment = BiasAlignment(0f, biasY),
                            colorFilter = if (Diag.has("shade")) null else Skyline.filter(how), modifier = Modifier.fillMaxSize())
                    }
                } else {
                    DrawnSkyline(city, phase, Modifier.fillMaxSize())
                }
            }
            // The scrim, the only darkening over a photo that's shown as taken: black 60% at the bottom fading
            // to 25% at 72% of the height and nothing by half of it, and black 50% held over the left 34% then
            // easing to nothing by 78% of the width (as iOS CardScrim); on a bright photo, a little more at the left (Skyline.scrimAlpha matches).
            if (!Diag.has("scrim")) Box(Modifier.matchParentSize().drawBehind {
                // Two-colour gradients over exact bands only: multi-stop gradients across whole cards took
                // the Android emulator's graphics down (CI), and simple ones look the same.
                // Band edges on whole pixels, so neighbouring bands meet exactly (no anti-aliased seam).
                val h = size.height
                val w = size.width
                val y50 = kotlin.math.round(h * 0.5f)
                val y72 = kotlin.math.round(h * 0.72f)
                val clear = Color.Black.copy(alpha = 0f)
                val mid = Color.Black.copy(alpha = 0.25f)
                drawRect(Brush.verticalGradient(listOf(clear, mid), startY = y50, endY = y72),
                    topLeft = Offset(0f, y50), size = Size(w, y72 - y50))
                drawRect(Brush.verticalGradient(listOf(mid, Color.Black.copy(alpha = 0.6f)), startY = y72, endY = h),
                    topLeft = Offset(0f, y72), size = Size(w, h - y72))
                // The left scrim, as on the iPhone (CardScrim): black 50% held over the label column, then eased
                // to nothing; the two bands meet at the same alpha, so there's no edge.
                // The ease is drawn as a few two-colour bands (Skyline.LEFT_KNOTS), each starting at the alpha the last ends on.
                val hold = kotlin.math.round(w * Skyline.LEFT_HOLD)
                drawRect(Color.Black.copy(alpha = Skyline.LEFT_ALPHA), size = Size(hold, h))
                var x0 = hold
                for (i in 0 until Skyline.LEFT_KNOTS.size - 1) {
                    val x1 = kotlin.math.round(w * Skyline.leftKnotX(i + 1))
                    if (x1 > x0) drawRect(Brush.horizontalGradient(listOf(Color.Black.copy(alpha = Skyline.LEFT_KNOTS[i]),
                        Color.Black.copy(alpha = Skyline.LEFT_KNOTS[i + 1])), startX = x0, endX = x1),
                        topLeft = Offset(x0, 0f), size = Size(x1 - x0, h))
                    x0 = x1
                }
                if (boost > 0f) drawRect(Brush.horizontalGradient(listOf(Color.Black.copy(alpha = boost), clear), startX = 0f, endX = w * 0.55f),
                    size = Size(w * 0.55f, h))
            })
        }
        val labelWidth = Rows.labelWidth(maxWidth)
        val tileHeight = Rows.tileHeightFor(height)
        // Too little room for four lines (a short card, or large text): the zone gives way (TalkBack still says it).
        val grow = density.fontScale / cap
        val linesDp = (if (tall) 38f else 26f) * BannerGrow.of(density.fontScale) + 3f + 21f * grow + 16f * grow +
            (if (status != null) 18f * grow + 2f else 0f)
        val showZone = status == null || (height >= 112.dp && linesDp <= (height - Rows.padTop - Rows.padBottom).value)
        Row(Modifier.fillMaxSize().padding(start = Rows.padH, end = Rows.padH, top = Rows.padTop, bottom = Rows.padBottom),
            verticalAlignment = Alignment.Bottom) {
            Column(Modifier.width(labelWidth).wrapContentHeight(Alignment.Bottom, unbounded = true),
                verticalArrangement = Arrangement.spacedBy(1.dp)) {
                val (digits, suffix) = TimeMath.clock(moment, place.zone, store.use24h)
                // The time may run wider than the name column: it sits above the hour tiles.
                if (!Diag.has("time")) BannerTime(digits, suffix, compact = !tall, bright = bright, modifier = Modifier
                    .padding(bottom = 2.dp)
                    .wrapContentWidth(Alignment.Start, unbounded = true)
                    .onGloballyPositioned { coords ->
                        val parent = card[0] ?: return@onGloballyPositioned
                        if (!parent.isAttached || !coords.isAttached) return@onGloballyPositioned
                        val w = parent.size.width.toFloat()
                        val h = parent.size.height.toFloat()
                        if (w <= 0f || h <= 0f) return@onGloballyPositioned
                        val r = parent.localBoundingBoxOf(coords, false)
                        if (r != timeBox) timeBox = r
                        // Written only when it moves (by 0.05 of the card), so measuring never loops.
                        val moved = TimeRegion.of(r.left / w, r.top / h, r.right / w, r.bottom / h)
                        if (moved != region) region = moved
                    })
                if (!Diag.has("texts")) Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(place.title, style = LocalTextStyle.current.copy(shadow = textShadow), fontSize = (17f / cap).sp, lineHeight = (21f / cap).sp,
                        fontWeight = FontWeight.SemiBold, color = Palette.primary, maxLines = 1, overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f, fill = false))
                    // Where you are: a small pin after the name, as on the Mac.
                    if (here) Icon(Icons.Filled.LocationOn, contentDescription = null, tint = Palette.secondary,
                        modifier = Modifier.padding(start = 4.dp).size(12.dp))
                }
                if (showZone && !Diag.has("texts")) {
                    // Shrinks to fit before it would cut, so "UTC+5:30" shows whole (as on the Mac), never below 11 sp.
                    // Medium weight (thicker strokes over busy photo detail), still a clear step down from the SemiBold name.
                    var zoneShrink by remember(zoneText) { mutableFloatStateOf(1f) }
                    val zoneFloor = 11f / 13f
                    Text(zoneText, style = tnum.copy(shadow = textShadow), fontSize = (13f / cap * zoneShrink).sp, lineHeight = (16f / cap).sp,
                        fontWeight = FontWeight.Medium, color = Palette.secondary, maxLines = 1, softWrap = false, overflow = TextOverflow.Ellipsis,
                        onTextLayout = { if (it.didOverflowWidth && zoneShrink > zoneFloor) zoneShrink = (zoneShrink - 0.04f).coerceAtLeast(zoneFloor) })
                }
                if (status != null && !Diag.has("pills")) {
                    Spacer(Modifier.height(1.dp))
                    StatusPill(status, showDetail = tall, cap = cap)
                }
            }
            Spacer(Modifier.width(Strip.labelGap))
            if (Diag.has("tiles")) Spacer(Modifier.weight(1f)) else {
                // The tiles' place on the card (px), so the weekday tag knows the card's top and where the time is.
                val tilesLeft = with(density) { (Rows.padH + labelWidth + Strip.labelGap).toPx() }
                val tilesTop = with(density) { (height - Rows.padBottom - tileHeight).toPx() }
                HourTiles(store, place, Modifier.weight(1f), onLongPress, tileHeight, first = first,
                    headroom = height - Rows.padBottom - tileHeight, avoid = { timeBox.translate(-tilesLeft, -tilesTop) })
            }
        }
    }
}

/**
 * The Now capsule, once down the whole list as on the icon: drawn by each city card's list item over
 * its own slice, so the slices join into one capsule that scrolls with the cards and runs on past the
 * screen's edge. It runs round the centre (selected hour) Now tile of every card, a rounded rectangle
 * concentric with those tiles: its line half the tile gap outside the Now tiles' edges (left, right, above
 * the first card's and below the last's), midway to the neighbouring tiles, its radius the tile's plus that. Only drawn: it
 * takes no touches and TalkBack doesn't see it. Geometry from [Rows] and [Strip], as [CityRow] lays out.
 */
fun DrawScope.drawNowCapsule(index: Int, count: Int, rowHeight: Dp, first: Boolean) {
    if (count <= 0 || size.width <= 0f || size.height <= 0f) return
    val rowPx = rowHeight.roundToPx()
    val pitch = (rowPx + Rows.gap.roundToPx()).toFloat()
    val cardTop = if (first) Rows.edge.roundToPx().toFloat() else 0f
    val tileBottom = cardTop + rowPx - Rows.padBottom.roundToPx()
    val tileHeightPx = Rows.tileHeightFor(rowHeight).roundToPx()
    val tileTop = tileBottom - tileHeightPx
    val gap = Strip.gap.toPx()
    // The line's centre runs half the gap outside the Now tiles (midway between them and their neighbours), all round.
    val inset = gap / 2
    // The Now tile grows [Strip.nowGrow] above and below the row's other tiles (as HourTiles lays it out; the card has
    // Rows.padBottom, 12 dp, below the tiles and at least 38 dp above, so it always fits whole).
    val grow = Strip.nowGrow.toPx()
    val top = tileTop - grow - inset - index * pitch
    val bottom = tileBottom + grow + inset + (count - 1 - index) * pitch
    // Across: the card's insets, the name column, then the centre of five tiles.
    val margin = Strip.margin.roundToPx().toFloat()
    val cardWidth = size.width - 2 * margin
    val padH = Rows.padH.roundToPx().toFloat()
    val labelWidth = Rows.labelWidth(cardWidth.toDp()).roundToPx().toFloat()
    val labelGap = Strip.labelGap.roundToPx().toFloat()
    val tilesLeft = margin + padH + labelWidth + labelGap
    val tilesWidth = cardWidth - 2 * padH - labelWidth - labelGap
    val nowWidth = Strip.tileWidthAt(2, tilesWidth, gap)
    if (nowWidth <= 0f || bottom <= top) return
    // The line's centre: half the gap outside the Now tile's left and right edges.
    val left = tilesLeft + Strip.tileLeft(2, tilesWidth, gap) - inset
    val width = nowWidth + 2 * inset
    val height = bottom - top
    // Concentric with the tiles' corners (the tile radius plus the inset), not a capsule.
    val radius = Strip.tileRadius.toPx() + inset
    clipRect(0f, 0f, size.width, size.height) {
        // No glow (it would reach the tiles) and no fill (a white wash lightened the tile under it).
        // Both strokes are centred on the line, so together they fit in the gap with clear space to both tiles.
        val stroke = NowCapsule.stroke.toPx()
        // A dark halo under the white line, centred on it (1 dp of dark edge each side): the line keeps 3:1 against a
        // bright day sky, and is unchanged on a night photo. Black 60%: about 3.9:1 on a bright day sky (WCAG 1.4.11).
        val halo = NowCapsule.haloFor(gap, density)
        drawRoundRect(Color.Black.copy(alpha = 0.6f), topLeft = Offset(left, top), size = Size(width, height),
            cornerRadius = CornerRadius(radius), style = Stroke(halo))
        drawRoundRect(Color.White.copy(alpha = 0.85f), topLeft = Offset(left, top), size = Size(width, height),
            cornerRadius = CornerRadius(radius), style = Stroke(minOf(stroke, halo - density)))
    }
}

/** The Now outline's style. */
object NowCapsule {
    /** The white line. */
    val stroke = 2.dp
    /** The dark halo under the line (black 60%), 1 dp each side of it. */
    val halo = 4.dp

    /** The halo's width (px) in a [gap] (px): no wider than the gap less 1 dp (0.5 dp clear to each tile). */
    fun haloFor(gap: Float, density: Float): Float = minOf(halo.value * density, gap - density)
}

/**
 * A city's hours as five tiles, two before the selected hour and two after, as on the Mac panel:
 * each tile the colour of the day there at that hour (navy at night, blue-greys at dawn and dusk,
 * sky blue by day), dimmed outside working hours, the day's name in a small tag above the tile where a new day starts,
 * shown whole with a soft shadow under them (over a photo). The Now
 * capsule over the selected hour is drawn down the whole list.
 * Tap a tile to go to that hour; drag to move through time in quarter-hours.
 * [first]: the list's first card (the Now outline's top line passes above its Now tile). [headroom]: the card's
 * room above the tiles. [avoid]: the card's time, in this row's own px (the weekday tag keeps off it).
 */
@Composable
fun HourTiles(store: Store, place: Place, modifier: Modifier, onLongPress: () -> Unit, tileHeight: Dp = Strip.tileHeight,
              first: Boolean = false, headroom: Dp = 38.dp, avoid: () -> Rect = { Rect.Zero }) {
    val anchor = TimeMath.hourAnchor(store.moment, store.home)
    val starts = (-2..2).map { anchor.plusSeconds(it * 3600L) }
    fun newDay(start: Instant) = start.atZone(place.zone).toLocalDate() != start.minusSeconds(3600).atZone(place.zone).toLocalDate()
    val off = if (store.showWorkHours) WorkWeek.offLabel(place, store.moment, store.workStart, store.workEnd) else null
    val state = TimeMath.time(store.moment, place.zone, store.use24h) + if (store.showWorkHours) ", ${(off ?: "working").lowercase()}" else ""
    val gapPx = with(LocalDensity.current) { Strip.gap.toPx() }
    var widthPx by remember { mutableFloatStateOf(1f) }
    // One hour size for the whole row (as iOS HourTiles): measure the row's widest label once against the tile's
    // width and give every tile the same shrink, so "10:30" never draws smaller than "7:30" beside it.
    val use24h = store.use24h
    val fontScale = LocalDensity.current.fontScale
    val padPx = with(LocalDensity.current) { 4.dp.toPx() }
    val measurer = rememberTextMeasurer()
    val digitStyle = tnum.copy(fontWeight = FontWeight.SemiBold)
    val labels = starts.map { val z = it.atZone(place.zone); z.hour to z.minute }
    val rowShrink = remember(labels, use24h, fontScale, widthPx, digitStyle) {
        // Row weights give each tile a whole-pixel width, up to 1 px under its share, so floor it and keep 1 px slack.
        val tileText = kotlin.math.floor(Strip.tileWidth(widthPx, gapPx)) - padPx - 1f
        fun width(h: Int, m: Int, s: Float): Int {
            val cap = TileText.cap(fontScale, m)
            return measurer.measure(TileText.digits(h, m, use24h, cap), digitStyle.copy(fontSize = (17f * s / cap).sp),
                maxLines = 1, softWrap = false).size.width
        }
        if (widthPx <= 1f || tileText <= 0f) 1f else {
            val (wh, wm) = labels.maxBy { (h, m) -> width(h, m, 1f) }
            var s = 1f
            while (s > TileText.SHRINK_FLOOR && width(wh, wm, s) > tileText) s = (s - 0.05f).coerceAtLeast(TileText.SHRINK_FLOOR)
            s
        }
    }
    // The Now tile's hour (20 sp, ":30" at 14) against its own, wider tile: shrinks to fit, but never below the
    // other tiles' hour size (17 sp x rowShrink, which fits a narrower tile, so the Now tile's always fits too).
    val nowShrink = remember(labels, use24h, fontScale, widthPx, digitStyle, rowShrink) {
        val tileText = kotlin.math.floor(Strip.tileWidthAt(2, widthPx, gapPx)) - padPx - 1f
        val (h, m) = labels[2]
        val cap = TileText.cap(fontScale, m)
        fun width(s: Float): Int = measurer.measure(TileText.digits(h, m, use24h, cap, TileText.NOW_MINUTES),
            digitStyle.copy(fontSize = (TileText.NOW_DIGITS * s / cap).sp), maxLines = 1, softWrap = false).size.width
        val floor = 17f * rowShrink / TileText.NOW_DIGITS
        if (widthPx <= 1f || tileText <= 0f) floor else {
            var s = 1f
            while (s > floor && width(s) > tileText) s = (s - 0.025f).coerceAtLeast(floor)
            s
        }
    }
    val nowGrow = Strip.nowGrow
    // The new day's tag: the weekday ("WED") over the tile where a new day starts there. 11 dp whatever the text
    // size (it must stay narrower than a tile); the tile's hour and AM/PM are as every other tile's.
    val tags = starts.map { if (newDay(it)) TimeMath.weekday(it, place.zone).uppercase() else null }
    val tagStyle = with(LocalDensity.current) {
        LocalTextStyle.current.copy(fontSize = 11.dp.toSp(), lineHeight = TextUnit.Unspecified, fontWeight = FontWeight.SemiBold,
            letterSpacing = 0.3.dp.toSp(), color = Palette.midnight)
    }
    Box(modifier.fillMaxWidth().height(tileHeight)
        .onSizeChanged { widthPx = it.width.toFloat().coerceAtLeast(1f) }
        // A soft drop shadow under each tile (black ~35%, 1 dp down, ~3 dp soft), so they stand off the photo.
        .drawBehind {
            val g = Strip.gap.toPx()
            if (Strip.tileWidth(size.width, g) <= 0f) return@drawBehind
            val r = Strip.tileRadius.toPx()
            val dy = 1.dp.toPx()
            val grow = nowGrow.toPx()
            for ((spread, alpha) in TileShadow.layers) {
                val sp = spread.toPx()
                val black = Color.Black.copy(alpha = alpha)
                for (i in 0..4) {
                    val up = if (i == 2) grow else 0f
                    drawRoundRect(black, topLeft = Offset(Strip.tileLeft(i, size.width, g) - sp, dy - up - sp),
                        size = Size(Strip.tileWidthAt(i, size.width, g) + 2 * sp, size.height + 2 * up + 2 * sp),
                        cornerRadius = CornerRadius(r + sp))
                }
            }
        }
        .pointerInput(place.id) {
            detectTapGestures(onLongPress = { onLongPress() }, onTap = { o ->
                // The tile under the tap (the gap split between its two tiles).
                val k = (1..4).count { o.x >= Strip.tileLeft(it, widthPx, gapPx) - gapPx / 2 } - 2
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
        // On a card's photo the five tiles show whole (no edge fade, as on the iPhone).
        Box(Modifier.matchParentSize().clearAndSetSemantics {}) {
            Row(Modifier.matchParentSize(), horizontalArrangement = Arrangement.spacedBy(Strip.gap)) {
                starts.forEachIndexed { i, start ->
                    // The Now tile: about 12% wider than each other tile, and nowGrow taller above and below their
                    // centre line (it draws past this row's height; the card has room above and below).
                    if (i == 2) HourTile(store, place, start, center = true, height = tileHeight + nowGrow * 2,
                        shrink = nowShrink, modifier = Modifier.weight(Strip.NOW_WIDTH).fillMaxHeight()
                            .wrapContentHeight(Alignment.CenterVertically, unbounded = true).requiredHeight(tileHeight + nowGrow * 2))
                    else HourTile(store, place, start, center = false, height = tileHeight, shrink = rowShrink, modifier = Modifier.weight(1f).fillMaxHeight())
                }
            }
            // A new day: its weekday in a small gold-on-dark tag centred just above the tile where it starts (midnight
            // there), 3 dp clear of the tile's top. Drawn past this row's top; the card has [headroom] above the tiles.
            Canvas(Modifier.matchParentSize()) {
                val g = Strip.gap.toPx()
                val timeBox = avoid()
                for (i in 0..4) {
                    val day = tags[i] ?: continue
                    val tileW = Strip.tileWidthAt(i, size.width, g)
                    if (tileW <= 0f) continue
                    val label = measurer.measure(day, tagStyle, maxLines = 1, softWrap = false)
                    val textW = label.size.width.toFloat()
                    val textH = label.size.height.toFloat()
                    // A pill: 15 dp high, 5 dp each side of the text, never wider than its tile (so it stays clear of
                    // the Now outline's vertical lines, in the gaps beside the Now tile).
                    val h = maxOf(15.dp.toPx(), textH)
                    val w = minOf(textW + 10.dp.toPx(), maxOf(tileW, textW + 2.dp.toPx()))
                    val x = Strip.tileLeft(i, size.width, g) + (tileW - w) / 2
                    val tileTop = if (i == 2) -nowGrow.toPx() else 0f
                    // The first card's Now tile has the outline's top line just above it (drawNowCapsule: half the gap
                    // out, the halo's width): the tag sits 2 dp above that line, never on it.
                    val lineTop = tileTop - g / 2 - NowCapsule.haloFor(g, density) / 2
                    var y = if (i == 2 && first) lineTop - 2.dp.toPx() - h else tileTop - 3.dp.toPx() - h
                    // No room above (the card's top, or the card's time running over the tiles): inside the tile's top.
                    val clipped = y < 2.dp.toPx() - headroom.toPx()
                    val onTime = Rect(x, y, x + w, y + h).inflate(2.dp.toPx()).overlaps(timeBox)
                    if (clipped || onTime) y = tileTop + 2.dp.toPx()
                    drawRoundRect(Color.Black.copy(alpha = 0.55f), topLeft = Offset(x, y), size = Size(w, h), cornerRadius = CornerRadius(h / 2))
                    drawText(label, topLeft = Offset(x + (w - textW) / 2, y + (h - textH) / 2))
                }
            }
        }
    }
}

/** An hour tile's hour label, shared by the row's one-size measurement (HourTiles) and the tile itself. */
private object TileText {
    /** How far the hour may shrink to fit: to 80% (13.6 sp), so it stays larger than the 13 sp ":30". */
    const val SHRINK_FLOOR = 0.8f

    /** Large text grows up to 1.3x (1.15x on half-hour tiles); past that the text size is capped. */
    fun cap(fontScale: Float, minute: Int) = maxOf(1f, fontScale / (if (minute != 0) 1.15f else 1.3f))

    /** The Now tile's sizes (sp): its hour 3 over the others' 17, its ":30", AM/PM and day 1 over their 13. */
    const val NOW_DIGITS = 20f
    const val NOW_MINUTES = 14f

    /** The hour, ":30" inline at [minutes] sp (13; never shrinks with the hour), normal tracking. */
    fun digits(hour: Int, minute: Int, use24h: Boolean, cap: Float, minutes: Float = 13f): AnnotatedString = buildAnnotatedString {
        append(if (use24h) "%02d".format(hour) else "${if (hour % 12 == 0) 12 else hour % 12}")
        if (minute != 0) withStyle(SpanStyle(fontSize = (minutes / cap).sp)) { append(":%02d".format(minute)) }
    }
}

/** The hour tiles' soft shadow: wider, fainter layers (spread, alpha). */
private object TileShadow {
    val layers = listOf(3.dp to 0.06f, 2.dp to 0.08f, 1.dp to 0.12f)
}

/**
 * One hour tile, as on the Mac: the day's colour there at that hour, flat, with the hour in white on it.
 * The hour on one line (17 sp, ":30" inline at 13 sp, tabular), AM/PM under it (13 sp semibold), on every tile
 * alike: midnight is "12 / AM", noon "12 / PM" (the new day's name is a tag above the tile, HourTiles). Large text
 * grows up to 1.3x (1.15x on half-hour tiles); then the hour shrinks to fit the tile (to 80%); AM/PM and ":30" never shrink.
 */
@Composable
private fun HourTile(store: Store, place: Place, start: Instant, center: Boolean, height: Dp, shrink: Float, modifier: Modifier) {
    val z = start.atZone(place.zone)
    val hour = z.hour
    val minute = z.minute
    // Outside working hours, as on the Mac: the tile a little quieter, and opaque (its colour mixed toward the
    // sky at 30% of its luminance, via TileDim), so no photo shows through behind the numbers.
    val dim = store.showWorkHours && !store.isWorking(place, start.plusSeconds(1800))
    // The sky colour, its brightest steps held so white on it stays at least 5.6:1; a working tile (where working
    // hours are shown) no darker than DayColor.WORKING_FLOOR, so 9 AM and 5 PM stand 3:1 from the off tile beside them.
    // Only where the hour's own sky is day or shoulder (6:30 AM to 8:30 PM): a night-shift city's working midnight
    // keeps its navy, so the colour still says night; the 1 dp edge (below) tells it from the photo.
    val h = hour + minute / 60.0
    val floor = if (store.showWorkHours && !dim && h >= 6.5 && h <= 20.5) DayColor.WORKING_FLOOR else 0.0
    val fill = DayColor.tile(h, floor)
    val text = Color.White
    val fillColor by animateColorAsState(Color(if (dim) TileDim.opaque(fill) else fill), tween(250), label = "tile")
    val textColor by animateColorAsState(text, tween(250), label = "tile text")
    val shape = RoundedCornerShape(Strip.tileRadius)
    val use24h = store.use24h
    val fontScale = LocalDensity.current.fontScale
    val cap = TileText.cap(fontScale, minute)
    // [shrink] is the row's (HourTiles): every tile in a row draws its hour at the same size.
    // The Now tile's text a size up: the hour 20 sp (17), ":30", AM/PM and the day 14 sp (13).
    val big = if (center) TileText.NOW_DIGITS else 17f
    val small = if (center) TileText.NOW_MINUTES else 13f
    val digits = TileText.digits(hour, minute, use24h, cap, small)
    val suffix = if (use24h) null else if (hour < 12) "AM" else "PM"
    // A plain Box (the tile's height comes from HourTiles): no subcomposition per tile, so a card's first frame is quick.
    // 2 dp clear each side on every tile (the Now outline's stroke sits in the gap outside the tile, NowCapsule).
    // Off-hours and night tiles (fill near the night photo's own darkness) get a 1 dp white 32% edge, so the five
    // still read as tiles on a dark photo; the fill stays as it is (3:1 working against off).
    val edge = dim || Color(fill).luminance() < 0.03f
    Box(modifier.clip(shape).background(fillColor)
        .then(if (edge) Modifier.border(1.dp, Color.White.copy(alpha = 0.32f), shape)
            // Day tiles a 1 dp black 30% edge, so the blue stands about 4:1 off a pale day sky (was about 2.6:1).
            else Modifier.border(1.dp, Color.Black.copy(alpha = 0.3f), shape))
        .padding(horizontal = 2.dp),
        contentAlignment = Alignment.Center) {
        // Two lines on every tile (12-hour): the hour, then AM/PM, midnight ("12 / AM") and noon ("12 / PM") as any
        // other. 24-hour: the hour alone, centred. The new day's name is the tag above the tile (HourTiles).
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Text(digits, style = tnum, fontSize = (big * shrink / cap).sp, lineHeight = ((big + 1f) / cap).sp,
                fontWeight = if (center) FontWeight.SemiBold else FontWeight.Medium,
                color = textColor, maxLines = 1, softWrap = false)
            // AM/PM at 13 sp (the 13 floor the rest of the tile uses, as iOS TileLabel; it never shrinks with the
            // hour), full white, semibold, tracked 0.3.
            if (suffix != null) Text(suffix, style = tnum, fontSize = (small / cap).sp, lineHeight = ((small + 2f) / cap).sp,
                fontWeight = FontWeight.SemiBold,
                letterSpacing = 0.3.sp, color = textColor, maxLines = 1, softWrap = false)
        }
    }
}

/**
 * An hour tile outside working hours, as on the iPhone (HourTiles.offHours): the hour's sky at [FACTOR] of its
 * luminance, never brighter than [CAP] and never darker than the night tile ([FLOOR], #0A0E1C), same hue, opaque,
 * so no photo shows through behind the numbers. The midday working tile (#3F6A97-like, L 0.136) now stands 3.3:1
 * from an off tile (was 1.6:1 when mixed 28% toward the night ink), so who is working reads at a glance.
 */
object TileDim {
    const val FACTOR = 0.30
    const val CAP = 0.006
    const val FLOOR = 0.0048

    private fun lin(c: Int): Double { val s = c / 255.0; return if (s <= 0.04045) s / 12.92 else Math.pow((s + 0.055) / 1.055, 2.4) }
    private fun enc(l: Double): Int {
        val s = if (l <= 0.0031308) l * 12.92 else 1.055 * Math.pow(l, 1 / 2.4) - 0.055
        return (s * 255.0).roundToInt().coerceIn(0, 255)
    }

    /** [argb] as a dimmed (off-hours) tile: opaque. */
    fun opaque(argb: Int): Int {
        val r = lin((argb shr 16) and 0xFF); val g = lin((argb shr 8) and 0xFF); val b = lin(argb and 0xFF)
        val l = 0.2126 * r + 0.7152 * g + 0.0722 * b
        if (l <= 0.0) return argb or (0xFF shl 24)
        val k = maxOf(minOf(l, FLOOR), minOf(l * FACTOR, CAP)) / l
        return (0xFF shl 24) or (enc(r * k) shl 16) or (enc(g * k) shl 8) or enc(b * k)
    }
}

/** The widgets' hour tiles: the sky colour kept visible at night (never darker than #24384F), and dimmed halfway toward black. */
fun tone(argb: Int, dim: Boolean): Int {
    var r = (argb shr 16) and 0xFF; var g = (argb shr 8) and 0xFF; var b = argb and 0xFF
    val lum = 0.2126 * r + 0.7152 * g + 0.0722 * b
    if (lum < 0.2126 * 0x24 + 0.7152 * 0x38 + 0.0722 * 0x4F) { r = 0x24; g = 0x38; b = 0x4F }
    if (dim) { r = r / 2; g = g / 2; b = b / 2 }
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
                Text("Ahead with + or a plain number, back with −. Hours and minutes work too: 2:30.", fontSize = 13.sp, lineHeight = 18.sp, color = white(0.6f))
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
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(0.dp)) {
        // Two lines, as on iOS: the credit, then the link on its own 48 dp row so "·"/"↗" never wrap alone.
        Text("Made by Bradley Cowdrey. Free. Forever.", fontSize = 13.sp, color = white(0.6f), textAlign = TextAlign.Center)
        Text("bradcowdrey.com ↗", fontSize = 13.sp, color = white(0.6f),
            modifier = Modifier.heightIn(min = 48.dp).clickable { open(Palette.WEBSITE) }.wrapContentHeight(Alignment.CenterVertically))
        Text("Terms & Privacy", fontSize = 13.sp, color = white(0.6f),
            modifier = Modifier.heightIn(min = 48.dp).clickable { open(Palette.LEGAL) }.wrapContentHeight(Alignment.CenterVertically))
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
        // (While a new query runs, the last results stay; this shows only before the first ones, with a spinner
        // so the screen never reads as empty.)
        if (!ready && results.isEmpty()) item {
            Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically) {
                CircularProgressIndicator(Modifier.size(16.dp), color = white(0.6f), strokeWidth = 2.dp)
                Spacer(Modifier.width(10.dp))
                Text("Searching…", fontSize = 15.sp, color = white(0.6f))
            }
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
    // At large text (1.3x and up, as the ruler hint) the time goes back under the offsets, so the name is never cut.
    val stackTime = LocalDensity.current.fontScale >= 1.3f
    Row(Modifier.fillMaxWidth().heightIn(min = 64.dp).padding(horizontal = 4.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        IconButton(onClick = { store.remove(place) }) {
            Box(Modifier.size(22.dp).clip(CircleShape).background(Palette.destructive), contentAlignment = Alignment.Center) {
                Box(Modifier.width(10.dp).height(2.dp).background(Color.White))
            }
        }
        Column(Modifier.weight(1f)) {
            // The name, and its time at the right on the same line (as on the iPhone), so the time reads as the row's value.
            Row(verticalAlignment = Alignment.CenterVertically) {
                Row(Modifier.weight(1f), verticalAlignment = Alignment.CenterVertically) {
                    Text(place.title, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = Palette.primary,
                        maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                    if (store.isHere(place)) MyLocationMark()
                }
                if (!stackTime) Text(TimeMath.time(store.now, place.zone, store.use24h), style = tnum, fontSize = 17.sp, color = Palette.primary,
                    maxLines = 1, softWrap = false, modifier = Modifier.padding(start = 8.dp))
            }
            // How it relates to you and its UTC offset ("+3 hr · UTC−4", "Your time · UTC−7"), as on the iPhone,
            // so offsets can be checked while reordering.
            val relation = TimeMath.relative(store.now, place.zone, store.home)
                ?: if (place.zone.id == store.home.id) "Your time" else "Same time"
            Text("$relation · ${TimeMath.offsetLabel(TimeMath.offsetSeconds(place.zone, store.now))}", style = tnum,
                fontSize = 13.sp, color = white(0.6f), maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (stackTime) Text(TimeMath.time(store.now, place.zone, store.use24h), style = tnum, fontSize = 17.sp,
                color = Palette.primary, maxLines = 1)
        }
        IconButton(onClick = { store.move(place, -1) }, enabled = place != store.places.first()) {
            Icon(Icons.Filled.KeyboardArrowUp, "Move ${place.title} up", tint = if (place != store.places.first()) Palette.primary else white(0.38f))
        }
        IconButton(onClick = { store.move(place, 1) }, enabled = place != store.places.last()) {
            Icon(Icons.Filled.KeyboardArrowDown, "Move ${place.title} down", tint = if (place != store.places.last()) Palette.primary else white(0.38f))
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
    // Waits for the ruler's first layout (a jump at launch, such as travel, can come before it). A jump of more
    // than two hours (a travel or a date) goes straight there; a short move animates. Then it checks it landed,
    // and snaps there if anything (a busy first frame, an interrupted animation) left it short.
    LaunchedEffect(selected) {
        while (listState.layoutInfo.totalItemsCount == 0) delay(16)
        if (listState.isScrollInProgress || centered == selected) return@LaunchedEffect
        val target = (selected - base).coerceIn(0, 4 * span)
        syncing.set(true)
        try {
            if (kotlin.math.abs(centered - selected) > 8) listState.scrollToItem(target)
            else listState.animateScrollToItem(target)
            if (centered != selected && !listState.isScrollInProgress) listState.scrollToItem(target)
        } finally {
            syncing.set(false)
        }
    }

    BoxWithConstraints(Modifier.fillMaxWidth().height(40.dp)) {
        val side = ((maxWidth - tick) / 2).coerceAtLeast(0.dp)
        LazyRow(state = listState, flingBehavior = fling, contentPadding = PaddingValues(horizontal = side),
            modifier = Modifier.fillMaxSize()
                .semantics { stateDescription = if (store.isNow) "Now" else relative(store) }) {
            items(4 * span + 1) { k ->
                val index = base + k
                // The ends fade per item, never through a label: each label fades whole (by how far its box is from
                // the ruler's edge, gone before it would touch it), so a clipped "12 PM" can never read as "2 PM".
                // Read in the draw layer only (no recomposition while it scrolls).
                val fade: (Float) -> Float = { half ->
                    val info = listState.layoutInfo
                    val item = info.visibleItemsInfo.firstOrNull { it.index == k }
                    if (item == null) 0f else {
                        val w = (info.viewportEndOffset - info.viewportStartOffset).toFloat()
                        val x = item.offset - info.viewportStartOffset + item.size / 2f
                        if (w <= 0f) 1f else ((minOf(x, w - x) - half) / (w * 0.12f)).coerceIn(0f, 1f)
                    }
                }
                RulerTick(java.time.Instant.ofEpochSecond(index * 900L).atZone(store.home), store.use24h,
                    centre = (index - centered) in -2..1, fade = fade,
                    modifier = Modifier.width(tick).fillMaxHeight().clickable { scope.launch { listState.animateScrollToItem(k) } })
            }
        }
        // The fixed line: where you are in time.
        Box(Modifier.align(Alignment.TopCenter).padding(top = 16.dp).width(2.dp).height(22.dp)
            .clip(RoundedCornerShape(50)).background(Palette.primary))
    }
}

/**
 * One quarter-hour on the ruler: a tall tick and its hour on the hour (the day at midnight), shorter ones
 * between. Hours at 12 sp medium, tabular, white 70%; the hour nearest the centre line (the hour the Now
 * capsule shows, in your time zone) at full white.
 */
@Composable
private fun RulerTick(at: java.time.ZonedDateTime, use24h: Boolean, centre: Boolean, fade: (Float) -> Float, modifier: Modifier) {
    val hour = at.hour; val minute = at.minute
    // Half the label's width (px), so the whole label is faded out before its box reaches the ruler's edge.
    var labelHalf by remember { mutableFloatStateOf(0f) }
    Column(modifier, horizontalAlignment = Alignment.CenterHorizontally) {
        Box(Modifier.height(14.dp).wrapContentWidth(unbounded = true)
            .onSizeChanged { labelHalf = it.width / 2f }
            // A label shows whole (alpha 1) or not at all: only while its whole box sits inside the ruler with 8 dp clear.
            // A part-faded label read as a ghost ("4 PM" at 1.1:1 at the edge); the ticks below keep the gradual fade.
            .graphicsLayer { alpha = if (fade(labelHalf + 8.dp.toPx()) > 0f) 1f else 0f }, contentAlignment = Alignment.Center) {
            if (minute == 0) Text(
                if (hour == 0) at.dayOfWeek.getDisplayName(java.time.format.TextStyle.SHORT, java.util.Locale.ENGLISH).uppercase()
                else if (use24h) "%02d".format(hour) else "${if (hour % 12 == 0) 12 else hour % 12}${TimeMath.THIN}${if (hour < 12) "AM" else "PM"}",
                style = tnum, fontSize = 12.sp, lineHeight = 14.sp, maxLines = 1, softWrap = false,
                fontWeight = if (hour == 0) FontWeight.SemiBold else FontWeight.Medium,
                color = if (hour == 0 || centre) Palette.primary else white(0.85f))  // 0.85, as the iPhone's ruler labels (was 0.7)
        }
        Spacer(Modifier.height(3.dp))
        Box(Modifier.width(if (minute == 0) 1.5.dp else 1.dp)
            .graphicsLayer { alpha = fade(0f) }
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

    private fun isDay(place: Place, t: java.time.Instant): Boolean? = when (Sun.phase(place, t)) {
        is Sun.Phase.Day, Sun.Phase.AllDay -> true
        is Sun.Phase.Night, Sun.Phase.AllNight -> false
        null -> null
    }

    /** Twilight is within an hour of sunrise or sunset, either side. */
    fun phase(place: Place, at: java.time.Instant): Phase {
        val now = isDay(place, at) ?: return if (at.atZone(place.zone).hour in 7..18) Phase.DAY else Phase.NIGHT
        if (isDay(place, at.minusSeconds(3600)) != now || isDay(place, at.plusSeconds(3600)) != now) return Phase.TWILIGHT
        return if (now) Phase.DAY else Phase.NIGHT
    }

    /** Which photo suits the moment: the day photo as taken, the day photo warmed, or the night photo. */
    enum class Look { DAY, WARM, NIGHT }

    /**
     * Day: the day photo. Night, and twilight after sunset: the night photo. Twilight with the sun up (the
     * hour before sunset, or just after sunrise) and before sunrise: the day photo, gently warmed.
     */
    fun look(place: Place, at: java.time.Instant): Look = when (phase(place, at)) {
        Phase.DAY -> Look.DAY
        Phase.NIGHT -> Look.NIGHT
        Phase.TWILIGHT -> if (isDay(place, at) == false && isDay(place, at.minusSeconds(3600)) == true) Look.NIGHT else Look.WARM
    }

    /** Top and bottom of the gradient. */
    fun colors(phase: Phase): Pair<Color, Color> = when (phase) {
        Phase.DAY -> Color(0xFF3D74B0) to Color(0xFF1C3A5E)
        Phase.TWILIGHT -> Color(0xFF4F78A3) to Color(0xFF24384F)
        Phase.NIGHT -> Color(0xFF141E3C) to Color(0xFF0A0E1C)
    }
}


/** CI diagnostics (screenshot mode only): parts of the city cards to leave out, from the "off" extra. */
object Diag {
    @Volatile var off: Set<String> = emptySet()
    fun has(part: String) = part in off
}
