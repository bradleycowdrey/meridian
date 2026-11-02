package com.bradcowdrey.meridian

import android.content.Intent
import android.provider.CalendarContract
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.ui.layout.layout
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import java.time.Instant
import java.time.format.DateTimeFormatter
import java.util.Locale

/** One possible meeting time and how it is for each person in it. */
class Slot(val start: Instant, val end: Instant, val states: List<Slot.State>) {
    enum class State {
        WORKING, OFF, NIGHT;

        val color: Color
            get() = when (this) {
                WORKING -> Palette.cream.copy(alpha = 0.85f)
                OFF -> Palette.border
                NIGHT -> Palette.tile
            }
    }

    val working: Int get() = states.count { it == State.WORKING }

    companion object {
        /** Working for the whole meeting; else night if the sun is down there as it starts; else off. */
        fun state(place: Place, start: Instant, end: Instant, store: Store): State {
            if (store.isWorking(place, start) && store.isWorking(place, end.minusSeconds(60))) return State.WORKING
            val phase = Sun.phase(place, start)
            return if (phase is Sun.Phase.Night || phase == Sun.Phase.AllNight) State.NIGHT else State.OFF
        }
    }
}

object FindTime {
    val lengths = listOf(30, 60, 90, 120)

    /** "30 min", "1 hr", "1½ hr". */
    fun lengthLabel(minutes: Int): String =
        if (minutes < 60) "$minutes min" else if (minutes % 60 == 0) "${minutes / 60} hr" else "${minutes / 60}½ hr"

    /** "LIS" for Lisbon, "ANA" for Ana. */
    fun tag(place: Place): String = place.title.filter { it.isLetter() }.take(3).uppercase()

    /** "9 AM" or "09:00". */
    fun hourLabel(hour: Int, use24h: Boolean): String =
        if (use24h) "%02d:00".format(hour) else "${if (hour % 12 == 0) 12 else hour % 12}${TimeMath.THIN}${if (hour < 12) "AM" else "PM"}"

    val dayChip: DateTimeFormatter = DateTimeFormatter.ofPattern("EEE d", Locale.ENGLISH)

    /** Every person's time, ready to paste into an invite. */
    fun invite(store: Store, places: List<Place>, start: Instant, length: Int): String {
        val end = start.plusSeconds(length * 60L)
        val lines = mutableListOf("Meeting · ${lengthLabel(length)}")
        for (place in places) {
            val zone = place.zone
            lines += "${place.fullName}: ${TimeMath.fullDay(start, zone)}, ${TimeMath.time(start, zone, store.use24h)}–${TimeMath.time(end, zone, store.use24h)}" +
                " (${TimeMath.offsetLabel(TimeMath.offsetSeconds(zone, start))})"
        }
        lines += ""
        lines += "Times by Meridian: ${Palette.APP_PAGE}"
        return lines.joinToString("\n")
    }
}

/**
 * Find a Time: pick a day, a length and who's in it, and see when everyone is working (each city's
 * own working days and hours, its public holidays, and night), with the best times first. Tap a
 * time to add it to your calendar, share an invite with every city's time, or go there. As on the iPhone.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun FindTimeScreen(store: Store, onDone: () -> Unit) {
    val home = store.home
    val today = store.now.atZone(home).toLocalDate()
    // After work today, start with tomorrow.
    var day by remember { mutableStateOf(if (store.now.atZone(home).hour >= 17) today.plusDays(1) else today) }
    var length by remember { mutableIntStateOf(60) }
    var chosen by remember { mutableStateOf(store.visiblePlaces.map { it.id }.toSet()) }
    var slot by remember { mutableStateOf<Slot?>(null) }

    // The cards in the meeting, one per time zone and city (a person counts as their own).
    val people = store.places.filter { it.id in chosen }
    val dayStart = day.atStartOfDay(home).toInstant()
    // Every half-hour start on your day, scored by how many are working for the whole meeting.
    val slots = (0 until 48).map { i ->
        val start = dayStart.plusSeconds(i * 1800L)
        val end = start.plusSeconds(length * 60L)
        Slot(start, end, people.map { Slot.state(it, start, end, store) })
    }

    val picked = slot
    if (picked != null) {
        SlotScreen(store, picked, length, people, onClose = { slot = null }, onGo = { slot = null; onDone() })
    } else Screen("Find a Time", onDone) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState())
            .padding(start = 16.dp, end = 16.dp, bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            // The day: today, tomorrow, then two weeks.
            Row(Modifier.padding(top = 8.dp).bleed(16.dp).horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                (0 until 14).forEach { i ->
                    val date = today.plusDays(i.toLong())
                    PillChip(if (i == 0) "Today" else if (i == 1) "Tomorrow" else date.format(FindTime.dayChip), date == day) { day = date }
                }
            }
            LengthPicker(length) { length = it }
            Who(store, chosen) { chosen = it }
            BestTimes(store, slots, people.size) { slot = it }
            HourGrid(store, slots, people) { slot = it }
        }
    }
}

/** 30 min · 1 hr · 1½ hr · 2 hr, as one segmented control. */
@Composable
private fun LengthPicker(length: Int, set: (Int) -> Unit) {
    Row(Modifier.fillMaxWidth().height(36.dp).clip(RoundedCornerShape(50)).background(Palette.tile)
        .border(0.5.dp, Palette.border, RoundedCornerShape(50)).padding(2.dp)) {
        FindTime.lengths.forEach { minutes ->
            val on = minutes == length
            Box(Modifier.weight(1f).fillMaxHeight().clip(RoundedCornerShape(50)).background(if (on) Palette.cream else Color.Transparent)
                .clickable { set(minutes) }.semantics { selected = on }, contentAlignment = Alignment.Center) {
                Text(FindTime.lengthLabel(minutes), fontSize = 13.sp, fontWeight = FontWeight.SemiBold,
                    color = if (on) Palette.bg else Palette.secondary, maxLines = 1)
            }
        }
    }
}

/** Who's in it: the groups as quick picks, and every card as a chip. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Who(store: Store, chosen: Set<String>, set: (Set<String>) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        val groups = store.groups
        if (groups.isNotEmpty()) {
            Row(Modifier.bleed(16.dp).horizontalScroll(rememberScrollState()).padding(horizontal = 16.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                val everyone = store.places.map { it.id }.toSet()
                PillChip("Everyone", chosen == everyone) { set(everyone) }
                groups.forEach { group ->
                    val ids = store.places.filter { it.groups?.contains(group) == true }.map { it.id }.toSet()
                    PillChip(group, chosen == ids) { set(ids) }
                }
            }
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            store.places.forEach { place ->
                val on = place.id in chosen
                Row(Modifier.heightIn(min = 32.dp).clip(RoundedCornerShape(50))
                    .background(if (on) Palette.cream.copy(alpha = 0.14f) else Palette.tile)
                    .border(0.5.dp, if (on) Palette.cream.copy(alpha = 0.5f) else Palette.border, RoundedCornerShape(50))
                    .clickable { set(if (on) chosen - place.id else chosen + place.id) }
                    .semantics { selected = on }
                    .padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                    Icon(if (on) Icons.Filled.Check else Icons.Filled.Add, contentDescription = null,
                        tint = if (on) Palette.primary else Palette.muted, modifier = Modifier.size(14.dp))
                    Spacer(Modifier.width(4.dp))
                    Text(place.title, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = if (on) Palette.primary else Palette.muted, maxLines = 1)
                }
            }
        }
    }
}

/** The best times: the longest runs where the most people are working, soonest first. */
@Composable
private fun BestTimes(store: Store, slots: List<Slot>, count: Int, pick: (Slot) -> Unit) {
    val all = slots.filter { it.start >= TimeMath.quarter(store.now) }
    val top = all.maxOfOrNull { it.working } ?: 0
    val runs = mutableListOf<MutableList<Slot>>()
    if (top > 0) for (s in all) {
        if (s.working != top) continue
        val last = runs.lastOrNull()?.lastOrNull()
        if (last != null && s.start.epochSecond - last.start.epochSecond == 1800L) runs.last().add(s) else runs.add(mutableListOf(s))
    }
    fun time(at: Instant) = TimeMath.time(at, store.home, store.use24h)
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text((if (count == 0) "Choose who's in it" else if (top == count) "Everyone's working" else if (top == 0) "No one's working then"
            else "Best: $top of $count working").uppercase(), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = Palette.muted)
        if (runs.isEmpty()) {
            Text(if (count == 0) "Tap the cities and people above." else "Try another day, or fewer people.", fontSize = 14.sp, color = Palette.muted)
        }
        runs.take(3).forEach { run ->
            val first = run.first()
            Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Palette.tile)
                .border(0.5.dp, Palette.border, RoundedCornerShape(12.dp)).clickable { pick(first) }.padding(14.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("${time(first.start)}–${time(run.last().end)}",
                        fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = Palette.primary)
                    Spacer(Modifier.height(2.dp))
                    Text(if (run.size == 1) "Your time" else "Your time · start any time from ${time(first.start)} to ${time(run.last().start)}", fontSize = 12.sp, color = Palette.muted)
                }
                Icon(Icons.Filled.KeyboardArrowRight, contentDescription = null, tint = Palette.faint)
            }
        }
    }
}

/**
 * The day hour by hour (your time): a cell per person, bright while they're working, dim when
 * they're off, dark at night where they are.
 */
@Composable
private fun HourGrid(store: Store, slots: List<Slot>, people: List<Place>, pick: (Slot) -> Unit) {
    val hourly = slots.filterIndexed { i, _ -> i % 2 == 0 }
    Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("You", Modifier.width(62.dp), fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = Palette.muted)
            people.forEach {
                Text(FindTime.tag(it), Modifier.weight(1f), fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = Palette.muted,
                    textAlign = TextAlign.Center, maxLines = 1, overflow = TextOverflow.Clip)
            }
            Spacer(Modifier.width(30.dp))
        }
        hourly.forEach { s ->
            val label = FindTime.hourLabel(s.start.atZone(store.home).hour, store.use24h)
            val all = s.working == people.size && people.isNotEmpty()
            Row(Modifier.fillMaxWidth().alpha(if (s.end <= store.now) 0.35f else 1f).clickable { pick(s) }
                .semantics(mergeDescendants = true) { contentDescription = "$label, ${s.working} of ${people.size} working" },
                horizontalArrangement = Arrangement.spacedBy(4.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(label, Modifier.width(62.dp), fontSize = 12.sp, color = if (all) Palette.primary else Palette.muted, maxLines = 1)
                s.states.forEach { state ->
                    Box(Modifier.weight(1f).height(24.dp).clip(RoundedCornerShape(4.dp)).background(state.color))
                }
                Text("${s.working}/${people.size}", Modifier.width(30.dp), fontSize = 11.sp, color = Palette.faint, textAlign = TextAlign.End, maxLines = 1)
            }
        }
        Row(Modifier.padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(14.dp)) {
            Legend(Slot.State.WORKING.color, "Working")
            Legend(Slot.State.OFF.color, "Off")
            Legend(Slot.State.NIGHT.color, "Night")
        }
    }
}

@Composable
private fun Legend(color: Color, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(12.dp).clip(RoundedCornerShape(2.dp)).background(color).border(0.5.dp, Palette.border, RoundedCornerShape(2.dp)))
        Spacer(Modifier.width(5.dp))
        Text(text, fontSize = 12.sp, color = Palette.muted)
    }
}

/** A capsule chip, cream when it's the one chosen (the days, the groups). */
@Composable
fun PillChip(title: String, on: Boolean, onClick: () -> Unit) {
    Box(Modifier.heightIn(min = 34.dp).clip(RoundedCornerShape(50)).background(if (on) Palette.cream else Palette.tile)
        .border(0.5.dp, Palette.border, RoundedCornerShape(50)).clickable(onClick = onClick).semantics { selected = on }
        .padding(horizontal = 14.dp), contentAlignment = Alignment.Center) {
        Text(title, fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = if (on) Palette.bg else Palette.secondary, maxLines = 1)
    }
}

/**
 * A chosen time: each person's time and how it is for them, then Add to Calendar, Share Invite,
 * Copy Invite or Go to This Time.
 */
@Composable
private fun SlotScreen(store: Store, slot: Slot, length: Int, places: List<Place>, onClose: () -> Unit, onGo: () -> Unit) {
    BackHandler(onBack = onClose)
    val context = LocalContext.current
    val clipboard = LocalClipboardManager.current
    var start by remember { mutableStateOf(slot.start) }
    val end = start.plusSeconds(length * 60L)
    val home = store.home
    val invite = FindTime.invite(store, places, start, length)
    var copied by remember { mutableStateOf(false) }
    LaunchedEffect(copied) { if (copied) { delay(1800); copied = false } }

    /** "Working", "Off hours", "Thanksgiving Day", with "Wed" when it's another day there. */
    fun status(place: Place): String {
        val work = if (store.isWorking(place, start)) "Working" else WorkWeek.offLabel(place, start, store.workStart, store.workEnd) ?: "Off"
        val shift = TimeMath.dayShift(start, place.zone, home)
        val city = if (place.person != null) "${place.name} · " else ""
        return city + work + (if (shift == 0) "" else " · ${TimeMath.weekday(start, place.zone)}")
    }

    Screen("Meeting Time", onClose) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState())
            .padding(start = 16.dp, end = 16.dp, bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            FindCard {
                Column(Modifier.padding(16.dp)) {
                    Text("${TimeMath.time(start, home, store.use24h)}–${TimeMath.time(end, home, store.use24h)}",
                        fontSize = 34.sp, fontWeight = FontWeight.Light, color = Palette.primary, maxLines = 1)
                    Spacer(Modifier.height(4.dp))
                    Text("${TimeMath.fullDay(start, home)} · your time · ${FindTime.lengthLabel(length)}", fontSize = 14.sp, color = Palette.muted)
                    Spacer(Modifier.height(12.dp))
                    // Start 15 minutes earlier or later.
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text("Start", Modifier.weight(1f), color = Palette.secondary)
                        OutlinedButton(onClick = { start = start.minusSeconds(900) }, contentPadding = PaddingValues(0.dp),
                            modifier = Modifier.size(width = 44.dp, height = 34.dp)) { Text("−") }
                        Spacer(Modifier.width(8.dp))
                        OutlinedButton(onClick = { start = start.plusSeconds(900) }, contentPadding = PaddingValues(0.dp),
                            modifier = Modifier.size(width = 44.dp, height = 34.dp)) { Text("+") }
                    }
                }
            }
            if (places.isNotEmpty()) FindCard {
                Column(Modifier.padding(horizontal = 16.dp, vertical = 4.dp)) {
                    places.forEachIndexed { i, place ->
                        Row(Modifier.fillMaxWidth().padding(vertical = 10.dp).semantics(mergeDescendants = true) {},
                            verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(place.title, fontWeight = FontWeight.SemiBold, color = Palette.primary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Text(status(place), fontSize = 12.sp, maxLines = 1, overflow = TextOverflow.Ellipsis,
                                    color = if (store.isWorking(place, start)) Palette.secondary else Palette.muted)
                            }
                            Spacer(Modifier.width(8.dp))
                            Text("${TimeMath.time(start, place.zone, store.use24h)}–${TimeMath.time(end, place.zone, store.use24h)}",
                                fontSize = 15.sp, color = Palette.primary, maxLines = 1, softWrap = false)
                        }
                        if (i < places.size - 1) HorizontalDivider(color = Palette.border, thickness = 0.5.dp)
                    }
                }
            }
            FindCard {
                ActionRow(Icons.Filled.DateRange, "Add to Calendar") {
                    // The calendar app's own new-event screen, filled in: no calendar permission needed.
                    val intent = Intent(Intent.ACTION_INSERT).setData(CalendarContract.Events.CONTENT_URI)
                        .putExtra(CalendarContract.EXTRA_EVENT_BEGIN_TIME, start.toEpochMilli())
                        .putExtra(CalendarContract.EXTRA_EVENT_END_TIME, end.toEpochMilli())
                        .putExtra(CalendarContract.Events.TITLE, "Meeting")
                        .putExtra(CalendarContract.Events.DESCRIPTION, invite)
                    runCatching { context.startActivity(intent) }.onFailure {
                        android.widget.Toast.makeText(context, "No calendar app to add it to", android.widget.Toast.LENGTH_SHORT).show()
                    }
                }
                HorizontalDivider(Modifier.padding(start = 52.dp), color = Palette.border, thickness = 0.5.dp)
                ActionRow(Icons.Filled.Share, "Share Invite…") {
                    context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain")
                        .putExtra(Intent.EXTRA_SUBJECT, "Meeting, ${TimeMath.fullDay(start, home)}").putExtra(Intent.EXTRA_TEXT, invite), "Share Invite"))
                }
                HorizontalDivider(Modifier.padding(start = 52.dp), color = Palette.border, thickness = 0.5.dp)
                ActionRow(Icons.Filled.Check, if (copied) "Copied" else "Copy Invite") {
                    clipboard.setText(AnnotatedString(invite)); copied = true
                }
                HorizontalDivider(Modifier.padding(start = 52.dp), color = Palette.border, thickness = 0.5.dp)
                ActionRow(Icons.Filled.Refresh, "Go to This Time") { store.jump(start); onGo() }
            }
        }
    }
}

@Composable
private fun ActionRow(icon: ImageVector, label: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, contentDescription = null, tint = Palette.cream, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(16.dp))
        Text(label, color = Palette.cream)
    }
}

@Composable
private fun FindCard(content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(Palette.tile)
        .border(0.5.dp, Palette.border, RoundedCornerShape(16.dp)), content = content)
}

/**
 * Lets a horizontally scrolling row run to the screen's edges from inside padded content, so a
 * cut-off chip at the edge reads as "scroll for more" (as on the iPhone).
 */
fun Modifier.bleed(horizontal: androidx.compose.ui.unit.Dp): Modifier = this.then(
    androidx.compose.ui.Modifier.layout { measurable, constraints ->
        val extra = horizontal.roundToPx() * 2
        val placeable = measurable.measure(constraints.copy(
            minWidth = (constraints.minWidth + extra).coerceAtLeast(0),
            maxWidth = if (constraints.hasBoundedWidth) constraints.maxWidth + extra else constraints.maxWidth))
        layout(placeable.width - extra, placeable.height) { placeable.place(-extra / 2, 0) }
    })
