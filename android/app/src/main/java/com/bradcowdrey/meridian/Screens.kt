package com.bradcowdrey.meridian

import android.content.Intent
import android.net.Uri
import android.widget.FrameLayout
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Search
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.selection.toggleable
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView

/**
 * A sub-screen, as Two Degrees' pages: close (or back, for Settings) top left with the title beside
 * it, on the sheet colour, the content no wider than 600 dp.
 */
@Composable
internal fun Screen(title: String, onBack: () -> Unit, back: Boolean = false, content: @Composable (PaddingValues) -> Unit) {
    Scaffold(
        containerColor = Palette.bg,
        topBar = {
            Row(Modifier.fillMaxWidth().background(Palette.bg).statusBarsPadding().padding(horizontal = 4.dp, vertical = 4.dp),
                verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onBack) {
                    if (back) Icon(Icons.AutoMirrored.Filled.ArrowBack, "Back", tint = Palette.primary)
                    else Icon(Icons.Filled.Close, "Close", tint = Palette.primary)
                }
                Text(title, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = Palette.primary, maxLines = 1,
                    modifier = Modifier.weight(1f).semantics { heading() })
            }
        },
    ) { padding ->
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
            Box(Modifier.widthIn(max = 600.dp).fillMaxSize()) { content(padding) }
        }
    }
}

/** Rename a city (not My Location, which is named from where you are), or the person on a person's card. */
@Composable
fun RenameDialog(place: Place, onDone: (String?) -> Unit) {
    var name by remember { mutableStateOf(place.title) }
    AlertDialog(
        onDismissRequest = { onDone(null) },
        containerColor = Palette.tile,
        shape = RoundedCornerShape(16.dp),
        title = { Text(if (place.person != null) "Rename Person" else "Rename City") },
        text = { OutlinedTextField(name, { name = it }, singleLine = true) },
        confirmButton = { TextButton(onClick = { onDone(name) }) { Text("Rename") } },
        dismissButton = { TextButton(onClick = { onDone(null) }) { Text("Cancel") } },
    )
}

/** "Add a Person Here": a card for someone in this card's city ("Ana", in Lisbon). */
@Composable
fun AddPersonDialog(city: String, onDone: (String?) -> Unit) {
    var name by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = { onDone(null) },
        containerColor = Palette.tile,
        shape = RoundedCornerShape(16.dp),
        title = { Text("Add a Person in $city") },
        text = {
            OutlinedTextField(name, { name = it }, singleLine = true, placeholder = { Text("Name") },
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { if (name.isNotBlank()) onDone(name) }))
        },
        confirmButton = { TextButton(onClick = { onDone(name) }, enabled = name.isNotBlank()) { Text("Add") } },
        dismissButton = { TextButton(onClick = { onDone(null) }) { Text("Cancel") } },
    )
}

private val checkColors: CheckboxColors @Composable get() =
    CheckboxDefaults.colors(checkedColor = Palette.primary, checkmarkColor = Palette.black, uncheckedColor = white(0.6f))

/**
 * A card's groups ("Design team", "Family"), from its actions: tick to add or remove (saved as you
 * go), or make a new group with this card in it. Its continent is shown, as it's automatic.
 */
@Composable
fun GroupPickerDialog(store: Store, placeId: String, onDone: () -> Unit) {
    val place = store.places.firstOrNull { it.id == placeId }
    if (place == null) {
        LaunchedEffect(placeId) { onDone() }
        return
    }
    var naming by remember { mutableStateOf(false) }
    val own = place.groups ?: emptyList()
    val continent = if (store.continentGroups) Continent.of(place) else null
    AlertDialog(
        onDismissRequest = onDone,
        containerColor = Palette.tile,
        shape = RoundedCornerShape(16.dp),
        title = { Text(place.title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                if (store.customGroups.isEmpty()) {
                    Text("No groups yet.", fontSize = 15.sp, color = white(0.6f), modifier = Modifier.padding(vertical = 8.dp))
                }
                store.customGroups.forEach { group ->
                    val on = group in own
                    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp)
                        .toggleable(value = on, role = Role.Checkbox) { store.setGroups(if (it) own + group else own.filter { g -> g != group }, place) },
                        verticalAlignment = Alignment.CenterVertically) {
                        Text(group, Modifier.weight(1f), color = Palette.primary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                        Checkbox(checked = on, onCheckedChange = null, colors = checkColors)
                    }
                }
                TextButton(onClick = { naming = true }, enabled = store.customGroups.size < Store.MAX_GROUPS,
                    contentPadding = PaddingValues(horizontal = 0.dp, vertical = 8.dp)) {
                    Icon(Icons.Filled.Add, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(Modifier.width(6.dp))
                    Text("New Group…")
                }
                if (continent != null) {
                    Text("$continent · automatic", fontSize = 15.sp, color = white(0.5f), modifier = Modifier.padding(vertical = 8.dp))
                }
                Spacer(Modifier.height(4.dp))
                Text(if (store.customGroups.size >= Store.MAX_GROUPS) "You can have up to ${Store.MAX_GROUPS} groups."
                    else "Add this card to as many groups as you like.", fontSize = 13.sp, color = white(0.6f))
            }
        },
        confirmButton = { TextButton(onClick = onDone) { Text("Done") } },
    )
    if (naming) GroupNameDialog(store, "New Group", confirm = "Create") { name ->
        naming = false
        if (name != null) store.createGroup(name)?.let { group ->
            store.places.firstOrNull { it.id == placeId }?.let { p -> store.setGroups((p.groups ?: emptyList()) + group, p) }
        }
    }
}

/** Name a new group, or rename one: the problem with the name shows as you type, and confirm waits for a good one. */
@Composable
fun GroupNameDialog(
    store: Store,
    title: String,
    initial: String = "",
    renaming: String? = null,
    confirm: String,
    onDone: (String?) -> Unit,
) {
    var text by remember { mutableStateOf(initial) }
    val problem = if (text.isBlank()) null else store.groupNameProblem(text, renaming)
    val ok = store.groupNameProblem(text, renaming) == null
    AlertDialog(
        onDismissRequest = { onDone(null) },
        containerColor = Palette.tile,
        shape = RoundedCornerShape(16.dp),
        title = { Text(title) },
        text = {
            val focus = remember { FocusRequester() }
            LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
            OutlinedTextField(text, { text = it }, singleLine = true, isError = problem != null,
                placeholder = { Text("Design Team") },
                supportingText = { Text(problem ?: "Name a group of cities, like your team or family.") },
                keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Done),
                keyboardActions = KeyboardActions(onDone = { if (ok) onDone(text) }),
                modifier = Modifier.focusRequester(focus))
        },
        confirmButton = { TextButton(onClick = { onDone(text) }, enabled = ok) { Text(confirm) } },
        dismissButton = { TextButton(onClick = { onDone(null) }) { Text("Cancel") } },
    )
}

/** "Delete “Design team”?" The cities stay. */
@Composable
fun DeleteGroupDialog(group: String, onConfirm: () -> Unit, onDismiss: () -> Unit) {
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = Palette.tile,
        shape = RoundedCornerShape(16.dp),
        title = { Text("Delete “$group”?") },
        text = { Text("The cities stay on your list.") },
        confirmButton = { TextButton(onClick = onConfirm) { Text("Delete", color = Palette.destructive) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

/**
 * Groups: your groups in your order (open one to choose its cities, rename it or delete it; move
 * them up and down), a new group, and the automatic continent groups. Opened on a group ([open]),
 * or straight to naming a new one ([create]), it shows just that group and closes when done.
 */
@Composable
fun GroupsScreen(store: Store, open: String?, create: Boolean = false, onDone: () -> Unit) {
    var detail by remember { mutableStateOf(open) }
    var naming by remember { mutableStateOf(create) }
    var created by remember { mutableStateOf<String?>(null) }
    var deleting by remember { mutableStateOf<String?>(null) }
    // Opened on one group (or a new one): that group is the whole screen.
    val direct = open != null || create
    fun finish() {
        // A new group from the bar is shown once it has cities.
        created?.let { group -> if (store.groupCount(group) > 0 && group in store.chipGroups) store.updateGroupFilter(group) }
        onDone()
    }
    fun back() { if (detail != null && !direct) detail = null else finish() }
    // Declared here, so it comes before the app's own Back.
    BackHandler { back() }

    val current = detail
    Screen(current ?: "Groups", onBack = { back() }, back = current != null && !direct) { padding ->
        if (current != null) {
            GroupDetail(store, current, Modifier.padding(padding),
                onRenamed = { detail = it; if (created != null) created = it },
                onDeleted = { if (created == current) created = null; if (direct) finish() else detail = null })
        } else if (!create) {
            val custom = store.customGroups
            val atCap = custom.size >= Store.MAX_GROUPS
            Column(Modifier.padding(padding).verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 8.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)) {
                GlassCard("Your Groups", Icons.Filled.Person, spacing = 0.dp) {
                    if (custom.isEmpty()) Text("No groups yet.", fontSize = 15.sp, color = white(0.6f), modifier = Modifier.padding(vertical = 10.dp))
                    custom.forEachIndexed { i, group ->
                        key(group) {
                            var menu by remember { mutableStateOf(false) }
                            Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable(onClickLabel = "Edit") { detail = group },
                                verticalAlignment = Alignment.CenterVertically) {
                                Text(group, Modifier.weight(1f), color = Palette.primary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Text(cityCount(store.groupCount(group)), fontSize = 15.sp, color = white(0.6f), maxLines = 1)
                                Box {
                                    IconButton(onClick = { menu = true }) { Icon(Icons.Filled.MoreVert, "More for $group", tint = white(0.6f)) }
                                    DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                                        DropdownMenuItem(text = { Text("Move Up") }, enabled = i > 0,
                                            leadingIcon = { Icon(Icons.Filled.KeyboardArrowUp, null) },
                                            onClick = { menu = false; store.moveGroup(group, -1) })
                                        DropdownMenuItem(text = { Text("Move Down") }, enabled = i < custom.size - 1,
                                            leadingIcon = { Icon(Icons.Filled.KeyboardArrowDown, null) },
                                            onClick = { menu = false; store.moveGroup(group, 1) })
                                        DropdownMenuItem(text = { Text("Delete…", color = Palette.destructive) },
                                            onClick = { menu = false; deleting = group })
                                    }
                                }
                            }
                            HorizontalDivider(thickness = 0.5.dp, color = white(0.15f))
                        }
                    }
                    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable(enabled = !atCap) { naming = true },
                        verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Filled.Add, contentDescription = null, tint = if (atCap) white(0.35f) else Palette.primary, modifier = Modifier.size(20.dp))
                        Spacer(Modifier.width(10.dp))
                        Text("New Group…", color = if (atCap) white(0.35f) else Palette.primary)
                    }
                }
                Note(if (atCap) "You can have up to ${Store.MAX_GROUPS} groups."
                    else "Show one group at a time on your list, and pick a group in Find a Time.")
                GlassCard("Continents", Icons.Filled.LocationOn, spacing = 0.dp) {
                    SwitchRow("Group by Continent", store.continentGroups) { store.updateContinentGroups(it) }
                    if (store.continentGroups) {
                        val present = store.places.mapNotNull { Continent.of(it) }.toSet()
                        Continent.ordered.filter { it in present }.forEach { continent ->
                            Row(Modifier.fillMaxWidth().heightIn(min = 44.dp), verticalAlignment = Alignment.CenterVertically) {
                                Text(continent, Modifier.weight(1f), color = white(0.85f))
                                Text(cityCount(store.places.count { Continent.of(it) == continent }), fontSize = 15.sp, color = white(0.6f))
                            }
                        }
                    }
                }
                Note("Cities are grouped by continent automatically. Continent chips show when your list spans two or more.")
                Spacer(Modifier.height(24.dp))
            }
        }
    }
    if (naming) GroupNameDialog(store, "New Group", confirm = "Create") { name ->
        naming = false
        val group = name?.let { store.createGroup(it) }
        if (group != null) {
            if (create) created = group
            detail = group
        } else if (create && detail == null) onDone()
    }
    deleting?.let { group ->
        DeleteGroupDialog(group, onConfirm = { deleting = null; store.deleteGroup(group) }, onDismiss = { deleting = null })
    }
}

/** One group: its name (tap to rename), its cities as a checklist (saved as you go), and Delete. */
@Composable
private fun GroupDetail(store: Store, name: String, modifier: Modifier, onRenamed: (String) -> Unit, onDeleted: () -> Unit) {
    // Deleted elsewhere (or never there): close.
    if (name !in store.customGroups) {
        LaunchedEffect(name) { onDeleted() }
        return
    }
    var renaming by remember { mutableStateOf(false) }
    var confirmDelete by remember { mutableStateOf(false) }
    var query by remember { mutableStateOf("") }
    val members = store.places.filter { name in (it.groups ?: emptyList()) }.map { it.id }.toSet()
    val allIn = store.places.isNotEmpty() && members.size == store.places.size
    val q = query.trim()
    val shown = if (q.isEmpty()) store.places else store.places.filter { it.title.contains(q, ignoreCase = true) || it.name.contains(q, ignoreCase = true) }
    Column(modifier.verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 8.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp)) {
        GlassCard("Name", null, spacing = 0.dp) {
            Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable(onClickLabel = "Rename") { renaming = true },
                verticalAlignment = Alignment.CenterVertically) {
                Text(name, Modifier.weight(1f), color = Palette.primary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Icon(Icons.Filled.Edit, contentDescription = "Rename", tint = white(0.6f), modifier = Modifier.size(18.dp))
            }
        }
        GlassCard("Cities", Icons.Filled.LocationOn, spacing = 0.dp) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text("${cityCount(members.size).replaceFirstChar { it.uppercase() }} in this group", Modifier.weight(1f),
                    fontSize = 13.sp, color = white(0.6f))
                TextButton(onClick = { store.setMembers(if (allIn) emptySet() else store.places.map { it.id }.toSet(), name) },
                    enabled = store.places.isNotEmpty()) { Text(if (allIn) "Select None" else "Select All") }
            }
            if (store.places.size > 10) {
                OutlinedTextField(query, { query = it }, singleLine = true, placeholder = { Text("Search cities") },
                    leadingIcon = { Icon(Icons.Filled.Search, contentDescription = null, tint = white(0.6f)) },
                    shape = RoundedCornerShape(12.dp), modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp))
            }
            if (store.places.isEmpty()) Text("Add cities with + on the main screen.", fontSize = 15.sp, color = white(0.6f),
                modifier = Modifier.padding(vertical = 10.dp))
            else if (shown.isEmpty()) Text("No cities match “$q”.", fontSize = 15.sp, color = white(0.6f),
                modifier = Modifier.padding(vertical = 10.dp))
            shown.forEach { p ->
                key(p.id) {
                    val member = p.id in members
                    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp)
                        .toggleable(value = member, role = Role.Checkbox) { on ->
                            store.setMembers(if (on) members + p.id else members - p.id, name)
                        }
                        .semantics { selected = member },
                        verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(p.title, color = Palette.primary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                            if (p.person != null) Text(p.name, fontSize = 13.sp, color = white(0.6f), maxLines = 1)
                        }
                        Text(TimeMath.time(store.now, p.zone, store.use24h), style = tnum, fontSize = 15.sp, color = white(0.6f), maxLines = 1)
                        Spacer(Modifier.width(10.dp))
                        Icon(Icons.Filled.Check, contentDescription = null, tint = if (member) Palette.primary else Color.Transparent,
                            modifier = Modifier.size(20.dp))
                    }
                }
            }
        }
        Note("Changes save as you go.")
        TextButton(onClick = { confirmDelete = true }, modifier = Modifier.heightIn(min = 48.dp)) {
            Text("Delete Group", color = Palette.destructive)
        }
        Spacer(Modifier.height(24.dp))
    }
    if (renaming) GroupNameDialog(store, "Rename Group", initial = name, renaming = name, confirm = "Rename") { new ->
        renaming = false
        if (new != null && store.renameGroup(name, new)) onRenamed(Store.normalizedGroupName(new))
    }
    if (confirmDelete) DeleteGroupDialog(name, onConfirm = { confirmDelete = false; store.deleteGroup(name); onDeleted() },
        onDismiss = { confirmDelete = false })
}

@Composable
fun SettingsScreen(store: Store, openGroups: () -> Unit, onDone: () -> Unit) {
    val context = LocalContext.current
    fun open(url: String) = context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
    // Photo Credits, from About: its own screen, back to Settings.
    var credits by rememberSaveable { mutableStateOf(false) }
    if (credits) {
        BackHandler { credits = false }
        PhotoCreditsScreen { credits = false }
        return
    }
    Screen("Settings", onDone, back = true) { padding ->
        Column(Modifier.padding(padding).verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 8.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)) {
            GlassCard("Time", Icons.Filled.DateRange) {
                SwitchRow("24-Hour Time", store.use24h) { store.updateUse24h(it) }
                SwitchRow("Highlight Working Hours", store.showWorkHours) { store.updateShowWorkHours(it) }
                SwitchRow("Public Holidays Are Days Off", store.countHolidays) { store.updateCountHolidays(it) }
                if (store.showWorkHours) {
                    Note("Each city follows its country's usual working days and hours and its national public holidays. To change a city's, touch and hold its card.")
                }
            }
            GlassCard("Cities", Icons.Filled.LocationOn) {
                SwitchRow("Show My Location", store.useMyLocation) { store.updateUseMyLocation(it) }
                Note("Keeps the city you're in on your list, and updates it when you travel. Location is used only to name the city, and only on your phone.")
                SwitchRow("Group by Continent", store.continentGroups) { store.updateContinentGroups(it) }
                Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).clickable(onClick = openGroups), verticalAlignment = Alignment.CenterVertically) {
                    Text("Groups", Modifier.weight(1f), color = Palette.primary)
                    Text("${store.customGroups.size}", color = white(0.6f))
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = white(0.6f))
                }
                Note("Cities are grouped by continent automatically when your list spans two or more.")
                SwitchRow("Download City Photos", store.downloadPhotos) { store.updateDownloadPhotos(it) }
                Note("Photos of cities without a built-in one come from Wikimedia Commons, once, then stay on this phone. Only the city's name is sent.")
            }
            GlassCard("Widgets", Icons.Filled.Settings) {
                Note("Touch and hold your home screen, tap Widgets, then find Meridian. Widgets show your cities in the same order as here.")
            }
            GlassCard("About", Icons.Filled.Info, spacing = 0.dp) {
                val version = runCatching { context.packageManager.getPackageInfo(context.packageName, 0).versionName }.getOrNull() ?: ""
                Row(Modifier.fillMaxWidth().heightIn(min = 44.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("Version", Modifier.weight(1f), color = Palette.primary)
                    Text(version, color = white(0.6f))
                }
                LinkRow("bradcowdrey.com/meridian") { open(Palette.APP_PAGE) }
                LinkRow("Source code on GitHub") { open(Palette.SOURCE) }
                LinkRow("Terms & Privacy") { open(Palette.LEGAL) }
                Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).clickable { credits = true }, verticalAlignment = Alignment.CenterVertically) {
                    Text("Photo Credits", Modifier.weight(1f), color = Palette.primary)
                    Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = white(0.6f))
                }
            }
            Text("Made by Bradley Cowdrey. Free. Forever.", fontSize = 13.sp, color = white(0.6f), textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().padding(top = 10.dp, bottom = 24.dp))
        }
    }
}

/** A line of explanation under a setting. */
@Composable
private fun Note(text: String) {
    Text(text, fontSize = 13.sp, color = white(0.6f))
}

@Composable
private fun SwitchRow(label: String, on: Boolean, set: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 44.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f), color = Palette.primary)
        // On: green with a white knob, as the system's switches; off: faint white.
        Switch(on, set, colors = SwitchDefaults.colors(checkedTrackColor = Palette.switchOn, checkedThumbColor = Color.White,
            checkedBorderColor = Palette.switchOn, uncheckedTrackColor = white(0.15f), uncheckedThumbColor = white(0.6f),
            uncheckedBorderColor = Color.Transparent))
    }
}

@Composable
private fun StepperRow(label: String, down: () -> Unit, up: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f), color = Palette.primary)
        OutlinedButton(onClick = down, contentPadding = PaddingValues(0.dp), modifier = Modifier.size(width = 44.dp, height = 34.dp),
            border = BorderStroke(1.dp, white(0.3f)), colors = ButtonDefaults.outlinedButtonColors(contentColor = Palette.primary)) { Text("−") }
        Spacer(Modifier.width(8.dp))
        OutlinedButton(onClick = up, contentPadding = PaddingValues(0.dp), modifier = Modifier.size(width = 44.dp, height = 34.dp),
            border = BorderStroke(1.dp, white(0.3f)), colors = ButtonDefaults.outlinedButtonColors(contentColor = Palette.primary)) { Text("+") }
    }
}

/**
 * Photo Credits: the skyline photos built in (skylines.json) and those downloaded for other cities,
 * each with its author and licence; tap one to open its page on Wikimedia Commons.
 */
@Composable
fun PhotoCreditsScreen(onBack: () -> Unit) {
    val context = LocalContext.current
    fun open(url: String) {
        if (url.isBlank()) return
        runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
    }
    val bundled = remember { SkylineManifest.credited(context) }
    // Read off the main thread; again whenever a photo is saved.
    val downloaded by produceState(emptyList<CityPhotos.Downloaded>(), CityPhotos.saved) {
        value = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) { CityPhotos.downloaded(context) }
    }
    Screen("Photo Credits", onBack, back = true) { padding ->
        Column(Modifier.padding(padding).verticalScroll(rememberScrollState()).padding(start = 16.dp, end = 16.dp, top = 8.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Note("City skyline photos from Wikimedia Commons, under the licence shown for each.")
            GlassCard("Built In", null, spacing = 0.dp) {
                bundled.forEach { (city, credit) -> CreditRow(city, credit) { open(it) } }
            }
            if (downloaded.isNotEmpty()) {
                GlassCard("Downloaded", null, spacing = 0.dp) {
                    downloaded.forEach { CreditRow(it.city, it.credit) { url -> open(url) } }
                }
            }
            Spacer(Modifier.height(24.dp))
        }
    }
}

/** A photo's city, author and licence, opening its source page (and its licence from the licence line). */
@Composable
private fun CreditRow(city: String, credit: PhotoCredit?, open: (String) -> Unit) {
    val source = credit?.source.orEmpty()
    Row(Modifier.fillMaxWidth().heightIn(min = 52.dp).clickable(enabled = source.isNotBlank(), onClickLabel = "Open on Wikimedia Commons") { open(source) }
        .padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(city, color = Palette.primary)
            val byline = listOfNotNull(credit?.author?.takeIf { it.isNotBlank() }, credit?.license?.takeIf { it.isNotBlank() }).joinToString(" · ")
            if (byline.isNotEmpty()) Text(byline, fontSize = 12.sp, color = white(0.7f), maxLines = 2, overflow = TextOverflow.Ellipsis)
            if (source.isNotBlank()) Text(source.removePrefix("https://commons.wikimedia.org/wiki/").replace('_', ' '), fontSize = 12.sp,
                color = white(0.5f), maxLines = 1, overflow = TextOverflow.Ellipsis)
            val licenseUrl = credit?.licenseUrl
            if (!licenseUrl.isNullOrBlank()) Text("Licence", fontSize = 12.sp, color = white(0.6f),
                modifier = Modifier.heightIn(min = 24.dp).clickable(onClickLabel = "Open the licence") { open(licenseUrl) }.padding(vertical = 3.dp))
        }
        if (source.isNotBlank()) Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = white(0.6f))
    }
}

@Composable
private fun LinkRow(label: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).clickable(onClick = onClick), verticalAlignment = Alignment.CenterVertically) {
        Text(label, color = Palette.primary)
    }
}

/** Terms of Use and Privacy: asked once, and again if the terms change (same version as the Mac and iPhone apps). As Two Degrees' terms. */
@Composable
fun TermsScreen(changed: Boolean = false, onAgree: () -> Unit) {
    val context = LocalContext.current
    Box(Modifier.fillMaxSize().background(Palette.bg), contentAlignment = Alignment.TopCenter) {
        Column(Modifier.widthIn(max = 520.dp).fillMaxSize().systemBarsPadding().padding(horizontal = 24.dp, vertical = 28.dp),
            horizontalAlignment = Alignment.CenterHorizontally) {
            Spacer(Modifier.weight(1f))
            Image(painterResource(R.drawable.mark), contentDescription = null, modifier = Modifier.size(88.dp).clip(RoundedCornerShape(20.dp)))
            Spacer(Modifier.height(20.dp))
            Text(if (changed) "The Terms of Use and Privacy have changed" else "Terms of Use and Privacy",
                fontSize = 28.sp, lineHeight = 34.sp, letterSpacing = (-0.4).sp, fontWeight = FontWeight.SemiBold,
                color = Palette.primary, textAlign = TextAlign.Center)
            Spacer(Modifier.height(16.dp))
            Text("Meridian is free and provided as is, without warranty. You use it at your own risk: always confirm meeting and travel times. Your cities stay on your phone. If you allow it, your location is used only to name the city you're in.\n\nBy tapping I Agree and using Meridian, you agree to the Terms of Use and Privacy at bradcowdrey.com/legal.",
                fontSize = 17.sp, lineHeight = 24.sp, color = white(0.85f), textAlign = TextAlign.Center)
            Spacer(Modifier.weight(1f))
            Button(onClick = onAgree, shape = RoundedCornerShape(50),
                colors = ButtonDefaults.buttonColors(containerColor = Palette.cream, contentColor = Palette.bg),
                modifier = Modifier.fillMaxWidth().height(50.dp)) {
                Text("I Agree", fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            }
            TextButton(onClick = { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(Palette.LEGAL))) },
                modifier = Modifier.heightIn(min = 44.dp)) {
                Text("Read the Terms", fontSize = 17.sp, fontWeight = FontWeight.Medium, color = Palette.primary)
            }
        }
    }
}

/** Screenshot mode's "widgets" screen: the home screen widgets, drawn by the real widget code. */
@Composable
fun WidgetShowcase(store: Store) {
    Column(Modifier.fillMaxSize().background(Palette.bg).systemBarsPadding().padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text("Widgets for your home screen", fontSize = 22.sp, lineHeight = 28.sp, fontWeight = FontWeight.Medium, color = Palette.primary)
        Text("Your cities, in the order you set.", fontSize = 14.sp, color = white(0.6f))
        Spacer(Modifier.height(20.dp))
        WidgetPreview(store, MeridianWidgets.Size.LARGE, Modifier.size(320.dp, 320.dp))
        Spacer(Modifier.height(16.dp))
        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
            WidgetPreview(store, MeridianWidgets.Size.SMALL, Modifier.size(152.dp, 152.dp))
        }
        Spacer(Modifier.height(16.dp))
        WidgetPreview(store, MeridianWidgets.Size.MEDIUM, Modifier.size(320.dp, 152.dp))
    }
}

@Composable
private fun WidgetPreview(store: Store, size: MeridianWidgets.Size, modifier: Modifier) {
    AndroidView(modifier = modifier, factory = { context ->
        FrameLayout(context).apply {
            val views = MeridianWidgets.views(context, size, store.places, store.use24h, store.moment, store.home)
            addView(views.apply(context, this))
        }
    })
}

/** One city's working days and hours. Saves only what differs from the usual week there and Settings' hours. */
@Composable
fun WorkHoursDialog(store: Store, place: Place, onDone: () -> Unit) {
    val usual = WorkWeek.usualDays(place.zoneId)
    // The hours most days keep there, to the whole hour (Settings' hours where none are known).
    val typical = WorkWeek.typicalHours(place.zoneId)
    val usualStart = typical?.start?.toInt() ?: store.workStart
    val usualEnd = typical?.end?.let { kotlin.math.ceil(it).toInt() } ?: store.workEnd
    var days by remember { mutableStateOf(place.workDays ?: usual) }
    var start by remember { mutableIntStateOf(place.workStart ?: usualStart) }
    var end by remember { mutableIntStateOf(place.workEnd ?: usualEnd) }
    fun save() = store.setWork(place, days.takeIf { it != usual }, start.takeIf { it != usualStart }, end.takeIf { it != usualEnd })
    AlertDialog(
        onDismissRequest = onDone,
        containerColor = Palette.tile,
        shape = RoundedCornerShape(16.dp),
        title = { Text(place.title) },
        text = {
            Column {
                Text("WORKING DAYS", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = white(0.6f))
                Spacer(Modifier.height(8.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    listOf("S", "M", "T", "W", "T", "F", "S").forEachIndexed { i, letter ->
                        val day = i + 1
                        val on = day in days
                        Box(Modifier.weight(1f).height(36.dp).clip(RoundedCornerShape(50))
                            .background(if (on) white(0.9f) else white(0.1f))
                            .clickable { days = if (on) days - day else days + day; save() },
                            contentAlignment = Alignment.Center) {
                            Text(letter, fontSize = 15.sp, fontWeight = FontWeight.Medium, color = if (on) Palette.black else Palette.primary)
                        }
                    }
                }
                Spacer(Modifier.height(6.dp))
                Text("Usual in ${place.name}: ${WorkWeek.describeUsual(place.zoneId, store.use24h)}.", fontSize = 12.sp, color = white(0.6f))
                Spacer(Modifier.height(16.dp))
                Text("WORKING HOURS", fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = white(0.6f))
                StepperRow("Starts at ${TimeMath.hourLabel(start, store.use24h)}",
                    { start = (start - 1).coerceIn(0, 23); save() }, { start = (start + 1).coerceIn(0, 23); save() })
                StepperRow("Ends at ${TimeMath.hourLabel(end % 24, store.use24h)}",
                    { end = (end - 1).coerceIn(1, 24); save() }, { end = (end + 1).coerceIn(1, 24); save() })
            }
        },
        confirmButton = { TextButton(onClick = onDone) { Text("Done") } },
        dismissButton = {
            TextButton(onClick = { days = usual; start = usualStart; end = usualEnd; save() },
                enabled = days != usual || start != usualStart || end != usualEnd) { Text("Use Usual") }
        },
    )
}

/**
 * Go to a day and time (on your clock), in quarter-hours, and see every city at that moment
 * before going there: the answer at the top, quick picks, a calendar, the time, your cities.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DateJumpScreen(store: Store, onDone: () -> Unit) {
    val zone = store.home
    fun quarterOf(i: java.time.Instant) = java.time.Instant.ofEpochSecond(Math.round(i.epochSecond / 900.0) * 900)
    fun utcMillis(d: java.time.LocalDate) = d.atStartOfDay(java.time.ZoneOffset.UTC).toInstant().toEpochMilli()
    val first = remember { quarterOf(store.moment).atZone(zone) }
    val dateState = rememberDatePickerState(initialSelectedDateMillis = utcMillis(first.toLocalDate()))
    var hour by remember { mutableIntStateOf(first.hour) }
    var quarter by remember { mutableIntStateOf(first.minute / 15) }
    val day = dateState.selectedDateMillis?.let { java.time.Instant.ofEpochMilli(it).atZone(java.time.ZoneOffset.UTC).toLocalDate() } ?: first.toLocalDate()
    val moment = day.atTime(hour, quarter * 15).atZone(zone).toInstant()
    fun set(i: java.time.Instant) {
        val z = quarterOf(i).atZone(zone)
        dateState.selectedDateMillis = utcMillis(z.toLocalDate()); hour = z.hour; quarter = z.minute / 15
    }
    val nine = if (store.use24h) "09:00" else "9${TimeMath.THIN}AM"
    // 123: type hours from now ("+3", "-1.5", "-2:30").
    var typing by remember { mutableStateOf(false) }
    if (typing) TypeOffsetDialog(onDone = { minutes -> typing = false; minutes?.let { store.shift(it); onDone() } })

    Screen("Go to a Time", onDone) { padding ->
        // Top inset only: the Go bar below reaches under the navigation bar.
        Column(Modifier.padding(top = padding.calculateTopPadding()).fillMaxSize()) {
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(10.dp)) {
                // The answer: the chosen time, large and thin, with its day and how far away it is.
                Column(Modifier.fillMaxWidth().padding(top = 24.dp, bottom = 16.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    val (clock, suffix) = TimeMath.clock(moment, zone, store.use24h)
                    Text(clockText(clock, suffix), fontSize = 72.sp, lineHeight = 76.sp, fontWeight = FontWeight.Thin,
                        letterSpacing = (-2).sp, color = Palette.primary, maxLines = 1, softWrap = false,
                        modifier = Modifier.semantics { contentDescription = TimeMath.time(moment, zone, store.use24h) })
                    Text("${moment.atZone(zone).format(java.time.format.DateTimeFormatter.ofPattern("EEE d MMM", java.util.Locale.ENGLISH))} · ${relativeSpan(store.now, moment)}",
                        fontSize = 17.sp, fontWeight = FontWeight.Medium, color = white(0.85f), textAlign = TextAlign.Center)
                }
                Row(Modifier.bleed(16.dp).horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    PillChip("Tomorrow $nine", false, selectable = false) { set(store.now.atZone(zone).toLocalDate().plusDays(1).atTime(9, 0).atZone(zone).toInstant()) }
                    PillChip("Monday $nine", false, selectable = false) {
                        set(store.now.atZone(zone).toLocalDate().with(java.time.temporal.TemporalAdjusters.next(java.time.DayOfWeek.MONDAY)).atTime(9, 0).atZone(zone).toInstant())
                    }
                    PillChip("In a Week", false, selectable = false) { set(store.now.plusSeconds(7 * 86_400L)) }
                    PillChip("123", false, description = "Type hours from now", selectable = false) { typing = true }
                }
                GlassCard("Date", Icons.Filled.DateRange) {
                    // To the card's edges: the calendar keeps its own margins.
                    DatePicker(state = dateState, modifier = Modifier.bleed(14.dp), title = null, headline = null, showModeToggle = false,
                        colors = DatePickerDefaults.colors(containerColor = Color.Transparent, selectedDayContainerColor = Palette.pickerAccent,
                            selectedDayContentColor = Color.White, todayDateBorderColor = Palette.pickerAccent, todayContentColor = Color.White,
                            dayContentColor = Color.White, weekdayContentColor = white(0.6f), navigationContentColor = Color.White,
                            titleContentColor = Color.White, headlineContentColor = Color.White))
                }
                GlassCard("Time", Icons.Filled.DateRange) {
                    // Hour, then the quarter-hour: it can only land on :00, :15, :30 or :45.
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Hour", Modifier.weight(1f), color = white(0.85f))
                        OutlinedIconButton(onClick = { hour = (hour + 23) % 24 }, border = BorderStroke(1.dp, white(0.3f)),
                            colors = IconButtonDefaults.outlinedIconButtonColors(contentColor = Palette.primary)) { Text("−", fontSize = 20.sp) }
                        Text(if (store.use24h) "%02d".format(hour) else "${if (hour % 12 == 0) 12 else hour % 12}${TimeMath.THIN}${if (hour < 12) "AM" else "PM"}",
                            style = tnum, fontSize = 20.sp, color = Palette.primary, textAlign = TextAlign.Center, modifier = Modifier.width(88.dp))
                        OutlinedIconButton(onClick = { hour = (hour + 1) % 24 }, border = BorderStroke(1.dp, white(0.3f)),
                            colors = IconButtonDefaults.outlinedIconButtonColors(contentColor = Palette.primary)) { Text("+", fontSize = 20.sp) }
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        (0..3).forEach { q -> PillChip(":%02d".format(q * 15), q == quarter, Modifier.weight(1f)) { quarter = q } }
                    }
                }
                if (store.places.isNotEmpty()) GlassCard("In your cities", Icons.Filled.LocationOn, spacing = 0.dp) {
                    // Every city at the chosen moment, with whether it's working there.
                    store.places.forEachIndexed { i, place ->
                        Row(Modifier.fillMaxWidth().heightIn(min = 44.dp).padding(vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(place.title, fontSize = 17.sp, fontWeight = FontWeight.Medium, color = Palette.primary, maxLines = 1,
                                    overflow = androidx.compose.ui.text.style.TextOverflow.Ellipsis)
                                val off = if (store.showWorkHours) WorkWeek.offLabel(place, moment, store.workStart, store.workEnd) else null
                                if (off != null) StatusNote(off, R.drawable.ic_moon, Palette.moon, color = white(0.6f), fontSize = 13.sp)
                            }
                            Text(TimeMath.time(moment, place.zone, store.use24h), style = tnum, fontSize = 20.sp, fontWeight = FontWeight.Light,
                                color = Palette.primary, maxLines = 1, softWrap = false)
                            val shift = TimeMath.dayShift(moment, place.zone, store.home)
                            if (shift != 0) Text(if (shift > 0) " +$shift d" else " −${-shift} d", fontSize = 13.sp, fontWeight = FontWeight.Medium, color = white(0.6f))
                        }
                        if (i < store.places.size - 1) HorizontalDivider(color = white(0.2f))
                    }
                }
                Spacer(Modifier.height(6.dp))
            }
            // Go, in a bar at the bottom as in Two Degrees.
            Column(Modifier.fillMaxWidth().background(Palette.barBg).navigationBarsPadding()) {
                HorizontalDivider(thickness = 0.5.dp, color = white(0.15f))
                Button(onClick = { store.jump(moment); onDone() }, shape = RoundedCornerShape(50),
                    colors = ButtonDefaults.buttonColors(containerColor = Color.White, contentColor = Color.Black),
                    modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp).height(50.dp)) {
                    Text("Go to This Time", fontSize = 17.sp, fontWeight = FontWeight.Medium)
                }
            }
        }
    }
}

/** "Now", "In 3 d 2 hr", "5 hr ago". */
fun relativeSpan(now: java.time.Instant, at: java.time.Instant): String {
    val total = ((at.epochSecond - now.epochSecond) / 60.0).let { Math.round(it).toInt() }
    if (kotlin.math.abs(total) < 1) return "Now"
    val a = kotlin.math.abs(total)
    val span = listOfNotNull((a / 1440).takeIf { it > 0 }?.let { "$it d" }, (a % 1440 / 60).takeIf { it > 0 }?.let { "$it hr" },
        (a % 60).takeIf { it > 0 && a < 1440 }?.let { "$it min" }).joinToString(" ")
    return if (total > 0) "In $span" else "$span ago"
}
