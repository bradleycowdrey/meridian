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
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.*
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

/** The groups a card is in ("Design team", "Family"): tick existing ones or make a new one. */
@Composable
fun GroupsDialog(store: Store, place: Place, onDone: () -> Unit) {
    var chosen by remember { mutableStateOf(place.groups?.toSet() ?: emptySet()) }
    var newGroup by remember { mutableStateOf("") }
    val all = (store.customGroups + chosen).distinct().sortedWith(String.CASE_INSENSITIVE_ORDER)
    fun addNew() {
        val name = newGroup.trim()
        if (name.isEmpty()) return
        chosen = chosen + name.take(30)
        newGroup = ""
    }
    AlertDialog(
        onDismissRequest = onDone,
        containerColor = Palette.tile,
        shape = RoundedCornerShape(16.dp),
        title = { Text(place.title) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                all.forEach { group ->
                    val on = group in chosen
                    Row(Modifier.fillMaxWidth().clickable { chosen = if (on) chosen - group else chosen + group }.padding(vertical = 2.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Text(group, Modifier.weight(1f), color = Palette.primary)
                        Checkbox(checked = on, onCheckedChange = { chosen = if (it) chosen + group else chosen - group },
                            colors = CheckboxDefaults.colors(checkedColor = Palette.primary, checkmarkColor = Palette.black, uncheckedColor = white(0.6f)))
                    }
                }
                if (all.isNotEmpty()) Spacer(Modifier.height(8.dp))
                Row(verticalAlignment = Alignment.CenterVertically) {
                    OutlinedTextField(newGroup, { newGroup = it }, singleLine = true, modifier = Modifier.weight(1f),
                        placeholder = { Text("New group, like Design Team") },
                        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Done),
                        keyboardActions = KeyboardActions(onDone = { addNew() }))
                    TextButton(onClick = { addNew() }, enabled = newGroup.isNotBlank()) { Text("Add") }
                }
                Spacer(Modifier.height(8.dp))
                Text("Show one group at a time on your list, and pick a group in Find a Time. Continents are added automatically.", fontSize = 13.sp, color = white(0.6f))
            }
        },
        confirmButton = { TextButton(onClick = { store.setGroups(chosen.toList(), place); onDone() }) { Text("Done") } },
        dismissButton = { TextButton(onClick = onDone) { Text("Cancel") } },
    )
}


@Composable
fun SettingsScreen(store: Store, onDone: () -> Unit) {
    val context = LocalContext.current
    fun open(url: String) = context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
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
                Note("Cities are grouped by continent automatically, for the chips above your cards and Find a Time.")
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
