package com.bradcowdrey.meridian

import android.content.Intent
import android.net.Uri
import android.widget.FrameLayout
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView

@OptIn(ExperimentalMaterial3Api::class)
@Composable
/** A sub-screen: its title and, as Material does, one way back (the arrow). */
internal fun Screen(title: String, onBack: () -> Unit, content: @Composable (PaddingValues) -> Unit) {
    Scaffold(
        containerColor = Palette.bg,
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text(title, fontWeight = FontWeight.SemiBold) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.Filled.ArrowBack, "Back") } },
                colors = TopAppBarDefaults.centerAlignedTopAppBarColors(containerColor = Palette.bg,
                    titleContentColor = Palette.primary, navigationIconContentColor = Palette.cream),
            )
        },
        content = content,
    )
}

/** Rename a city (not My Location, which is named from where you are), or the person on a person's card. */
@Composable
fun RenameDialog(place: Place, onDone: (String?) -> Unit) {
    var name by remember { mutableStateOf(place.title) }
    AlertDialog(
        onDismissRequest = { onDone(null) },
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
    val all = (store.groups + chosen).distinct().sortedWith(String.CASE_INSENSITIVE_ORDER)
    fun addNew() {
        val name = newGroup.trim()
        if (name.isEmpty()) return
        chosen = chosen + name.take(30)
        newGroup = ""
    }
    AlertDialog(
        onDismissRequest = onDone,
        containerColor = Palette.tile,
        title = { Text(place.title) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState())) {
                all.forEach { group ->
                    val on = group in chosen
                    Row(Modifier.fillMaxWidth().clickable { chosen = if (on) chosen - group else chosen + group }.padding(vertical = 2.dp),
                        verticalAlignment = Alignment.CenterVertically) {
                        Text(group, Modifier.weight(1f), color = Palette.primary)
                        Checkbox(checked = on, onCheckedChange = { chosen = if (it) chosen + group else chosen - group },
                            colors = CheckboxDefaults.colors(checkedColor = Palette.cream, checkmarkColor = Palette.bg, uncheckedColor = Palette.muted))
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
                Text("Show one group at a time on your list, and pick a group in Find a Time.", fontSize = 13.sp, color = Palette.muted)
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
    Screen("Settings", onDone) { padding ->
        Column(Modifier.padding(padding).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp)) {
            Section("TIME") {
                SwitchRow("24-Hour Time", store.use24h) { store.updateUse24h(it) }
                SwitchRow("Highlight Working Hours", store.showWorkHours) { store.updateShowWorkHours(it) }
                SwitchRow("Public Holidays Are Days Off", store.countHolidays) { store.updateCountHolidays(it) }
                if (store.showWorkHours) {
                    Text("Each city follows its country's usual working days and hours and its national public holidays. To change a city's, tap its card.",
                        fontSize = 13.sp, color = Palette.muted, modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 14.dp))
                }
            }
            Section("CITIES") {
                SwitchRow("Show My Location", store.useMyLocation) { store.updateUseMyLocation(it) }
                Text("Keeps the city you're in on your list, and updates it when you travel. Location is used only to name the city, and only on your phone.",
                    fontSize = 13.sp, color = Palette.muted, modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 14.dp))
            }
            Section("WIDGETS") {
                Text("Touch and hold your home screen, tap Widgets, then find Meridian. Widgets show your cities in the same order as here.",
                    fontSize = 13.sp, color = Palette.muted, modifier = Modifier.padding(16.dp))
            }
            Section("ABOUT") {
                val version = runCatching { context.packageManager.getPackageInfo(context.packageName, 0).versionName }.getOrNull() ?: ""
                Row(Modifier.fillMaxWidth().padding(16.dp)) { Text("Version", Modifier.weight(1f)); Text(version, color = Palette.muted) }
                LinkRow("bradcowdrey.com/meridian") { open(Palette.APP_PAGE) }
                LinkRow("Source code on GitHub") { open(Palette.SOURCE) }
                LinkRow("Terms & Privacy") { open(Palette.LEGAL) }
            }
            Text("Made by Bradley Cowdrey. Free. Forever.", fontSize = 13.sp, color = Palette.muted, modifier = Modifier.padding(vertical = 20.dp))
        }
    }
}

@Composable
private fun Section(title: String, content: @Composable ColumnScope.() -> Unit) {
    Text(title, fontSize = 12.sp, color = Palette.muted, modifier = Modifier.padding(start = 16.dp, top = 20.dp, bottom = 6.dp))
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Palette.tile), content = content)
}

@Composable
private fun SwitchRow(label: String, on: Boolean, set: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f))
        // On: the brand crimson with a white knob (clear against the dark, unlike cream); off: dark grey.
        Switch(on, set, colors = SwitchDefaults.colors(checkedTrackColor = Palette.crimson, checkedThumbColor = Color.White,
            checkedBorderColor = Palette.crimson, uncheckedTrackColor = Palette.border, uncheckedThumbColor = Palette.muted,
            uncheckedBorderColor = Palette.border))
    }
}

@Composable
private fun StepperRow(label: String, down: () -> Unit, up: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.weight(1f))
        OutlinedButton(onClick = down, contentPadding = PaddingValues(0.dp), modifier = Modifier.size(width = 44.dp, height = 34.dp)) { Text("−") }
        Spacer(Modifier.width(8.dp))
        OutlinedButton(onClick = up, contentPadding = PaddingValues(0.dp), modifier = Modifier.size(width = 44.dp, height = 34.dp)) { Text("+") }
    }
}

@Composable
private fun LinkRow(label: String, onClick: () -> Unit) {
    Text(label, color = Palette.cream, modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(16.dp))
}

/** Terms of Use and Privacy: asked once, and again if the terms change (same version as the Mac and iPhone apps). */
@Composable
fun TermsScreen(changed: Boolean = false, onAgree: () -> Unit) {
    val context = LocalContext.current
    Column(Modifier.fillMaxSize().background(Palette.bg).systemBarsPadding().padding(28.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.weight(1f))
        Image(painterResource(R.drawable.mark), contentDescription = null, modifier = Modifier.size(88.dp).clip(RoundedCornerShape(20.dp)))
        Spacer(Modifier.height(20.dp))
        Text(if (changed) "The Terms of Use and Privacy have changed" else "Terms of Use and Privacy",
            fontSize = 22.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
        Spacer(Modifier.height(16.dp))
        Text("Meridian is free and provided as is, without warranty. You use it at your own risk: always confirm meeting and travel times. Your cities stay on your phone. If you allow it, your location is used only to name the city you're in.\n\nBy tapping I Agree and using Meridian, you agree to the Terms of Use and Privacy at bradcowdrey.com/legal.",
            color = Palette.secondary, textAlign = TextAlign.Center)
        Spacer(Modifier.weight(1f))
        Button(onClick = onAgree, modifier = Modifier.fillMaxWidth().height(52.dp)) { Text("I Agree", fontWeight = FontWeight.SemiBold) }
        TextButton(onClick = { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(Palette.LEGAL))) }) {
            Text("Read the Terms", color = Palette.cream, fontWeight = FontWeight.SemiBold)
        }
    }
}

/** Screenshot mode's "widgets" screen: the home screen widgets, drawn by the real widget code. */
@Composable
fun WidgetShowcase(store: Store) {
    Column(Modifier.fillMaxSize().background(Palette.bg).systemBarsPadding().padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Text("Widgets for your home screen", fontSize = 22.sp, fontWeight = FontWeight.Medium, color = Palette.cream)
        Text("Your cities, in the order you set.", fontSize = 14.sp, color = Palette.muted)
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
        title = { Text(place.title) },
        text = {
            Column {
                Text("WORKING DAYS", fontSize = 12.sp, color = Palette.muted)
                Spacer(Modifier.height(8.dp))
                Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    listOf("S", "M", "T", "W", "T", "F", "S").forEachIndexed { i, letter ->
                        val day = i + 1
                        val on = day in days
                        Box(Modifier.weight(1f).height(36.dp).clip(RoundedCornerShape(50))
                            .background(if (on) Palette.cream else Palette.border)
                            .clickable { days = if (on) days - day else days + day; save() },
                            contentAlignment = Alignment.Center) {
                            Text(letter, fontWeight = FontWeight.SemiBold, color = if (on) Palette.bg else Palette.primary)
                        }
                    }
                }
                Spacer(Modifier.height(6.dp))
                Text("Usual in ${place.name}: ${WorkWeek.describeUsual(place.zoneId, store.use24h)}.", fontSize = 12.sp, color = Palette.muted)
                Spacer(Modifier.height(16.dp))
                Text("WORKING HOURS", fontSize = 12.sp, color = Palette.muted)
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
        Column(Modifier.padding(padding).fillMaxSize()) {
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp)) {
                // The answer: the chosen time, large, with its day and how far away it is.
                Column(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    Text(TimeMath.time(moment, zone, store.use24h), fontSize = 44.sp, fontWeight = FontWeight.Light)
                    Text("${moment.atZone(zone).format(java.time.format.DateTimeFormatter.ofPattern("EEE d MMM", java.util.Locale.ENGLISH))} · ${relativeSpan(store.now, moment)}",
                        fontSize = 14.sp, color = Palette.muted)
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    QuickChip("Tomorrow $nine", Modifier.weight(1f)) { set(store.now.atZone(zone).toLocalDate().plusDays(1).atTime(9, 0).atZone(zone).toInstant()) }
                    QuickChip("Monday $nine", Modifier.weight(1f)) {
                        set(store.now.atZone(zone).toLocalDate().with(java.time.temporal.TemporalAdjusters.next(java.time.DayOfWeek.MONDAY)).atTime(9, 0).atZone(zone).toInstant())
                    }
                    QuickChip("In a Week", Modifier.weight(1f)) { set(store.now.plusSeconds(7 * 86_400L)) }
                    QuickChip("123", Modifier.width(56.dp)) { typing = true }
                }
                DateCard {
                    DatePicker(state = dateState, title = null, headline = null, showModeToggle = false,
                        colors = DatePickerDefaults.colors(containerColor = Palette.tile, selectedDayContainerColor = Palette.cream,
                            selectedDayContentColor = Palette.bg, todayDateBorderColor = Palette.cream, todayContentColor = Palette.cream))
                }
                DateCard {
                    // Hour, then the quarter-hour: it can only land on :00, :15, :30 or :45.
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Text("Hour", Modifier.weight(1f), color = Palette.secondary)
                            OutlinedIconButton(onClick = { hour = (hour + 23) % 24 }) { Text("−", fontSize = 20.sp) }
                            Text(if (store.use24h) "%02d".format(hour) else "${if (hour % 12 == 0) 12 else hour % 12}${TimeMath.THIN}${if (hour < 12) "AM" else "PM"}",
                                fontSize = 20.sp, textAlign = TextAlign.Center, modifier = Modifier.width(88.dp))
                            OutlinedIconButton(onClick = { hour = (hour + 1) % 24 }) { Text("+", fontSize = 20.sp) }
                        }
                        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            (0..3).forEach { q ->
                                val on = q == quarter
                                Box(Modifier.weight(1f).height(36.dp).clip(RoundedCornerShape(50))
                                    .background(if (on) Palette.cream else Palette.border).clickable { quarter = q },
                                    contentAlignment = Alignment.Center) {
                                    Text(":%02d".format(q * 15), fontWeight = FontWeight.SemiBold, color = if (on) Palette.bg else Palette.primary)
                                }
                            }
                        }
                    }
                }
                if (store.places.isNotEmpty()) DateCard {
                    // Every city at the chosen moment, with whether it's working there.
                    Column(Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) {
                        store.places.forEachIndexed { i, place ->
                            Row(Modifier.fillMaxWidth().padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                                Column(Modifier.weight(1f)) {
                                    Text(place.title, fontWeight = FontWeight.SemiBold, maxLines = 1)
                                    val off = if (store.showWorkHours) WorkWeek.offLabel(place, moment, store.workStart, store.workEnd) else null
                                    if (off != null) StatusNote(off, R.drawable.ic_moon, Palette.muted)
                                }
                                Text(TimeMath.time(moment, place.zone, store.use24h), fontSize = 18.sp, fontWeight = FontWeight.Light)
                                val shift = TimeMath.dayShift(moment, place.zone, store.home)
                                if (shift != 0) Text(if (shift > 0) " +$shift d" else " −${-shift} d", fontSize = 11.sp, color = Palette.cream, fontWeight = FontWeight.SemiBold)
                            }
                            if (i < store.places.size - 1) HorizontalDivider(color = Palette.border, thickness = 0.5.dp)
                        }
                    }
                }
            }
            Button(onClick = { store.jump(moment); onDone() },
                colors = ButtonDefaults.buttonColors(containerColor = Palette.cream, contentColor = Palette.bg),
                modifier = Modifier.fillMaxWidth().padding(16.dp).height(52.dp)) {
                Text("Go to This Time", fontWeight = FontWeight.SemiBold, fontSize = 16.sp)
            }
        }
    }
}

@Composable
private fun DateCard(content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(Palette.tile), content = content)
}

@Composable
private fun QuickChip(title: String, modifier: Modifier, onClick: () -> Unit) {
    Box(modifier.height(36.dp).clip(RoundedCornerShape(50)).background(Palette.tile).clickable(onClick = onClick),
        contentAlignment = Alignment.Center) {
        Text(title, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = Palette.secondary, maxLines = 1)
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
