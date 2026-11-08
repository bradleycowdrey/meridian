package com.bradcowdrey.meridian

import android.content.Intent
import android.provider.CalendarContract
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.ScrollableState
import androidx.compose.foundation.Image
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.ui.layout.layout
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.DateRange
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Share
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalClipboardManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.buildAnnotatedString
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
                // As on the iPhone: working a pale sky blue (#DDEAFA, the hour tiles' hue, a little brighter than the old white 0.85),
                // off a mid grey, night near the card with a hairline edge and a small moon (SlotCell), so night never
                // depends on brightness alone. On the card (#141414): working 3.7:1 against off, off 3.3:1 against night (off
                // against night was 1.9:1 at white 0.30 / 0.12), the night cell's edge 3.9:1 against the card.
                WORKING -> Color(0xFFDDEAFA)
                OFF -> white(0.42f)
                NIGHT -> white(0.08f)
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

    /** "SF" for San Francisco, "NY" for New York, "LIS" for Lisbon: the same short names as the Lock Screen widgets.
     *  A person keeps the first three letters of their name ("Ana Lopez" is "ANA"), as on iOS: initials are ambiguous for people. */
    fun tag(place: Place): String =
        if (place.person == null) TimeMath.shortTag(place.name) else place.title.filter { it.isLetter() }.take(3).uppercase()

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
    var chosen by remember { mutableStateOf(store.visiblePlaces.map { it.id }.toSet().ifEmpty { store.places.map { it.id }.toSet() }) }
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
            .padding(start = 16.dp, end = 16.dp, bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            // The day: today, tomorrow, then two weeks.
            val days = rememberScrollState()
            Row(Modifier.padding(top = 8.dp).bleed(16.dp).fadeEnd(days).horizontalScroll(days).padding(horizontal = 16.dp),
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
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun LengthPicker(length: Int, set: (Int) -> Unit) {
    SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
        FindTime.lengths.forEachIndexed { i, minutes ->
            SegmentedButton(
                selected = minutes == length,
                onClick = { set(minutes) },
                shape = SegmentedButtonDefaults.itemShape(index = i, count = FindTime.lengths.size),
                colors = SegmentedButtonDefaults.colors(
                    activeContainerColor = Color.White, activeContentColor = Color.Black, activeBorderColor = white(0.2f),
                    inactiveContainerColor = Color.Transparent, inactiveContentColor = Color.White, inactiveBorderColor = white(0.2f),
                ),
                icon = {},
            ) {
                Text(FindTime.lengthLabel(minutes), fontSize = 15.sp, fontWeight = FontWeight.Medium, maxLines = 1)
            }
        }
    }
}

/** Who's in it: the groups as quick picks, and every card as a chip. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Who(store: Store, chosen: Set<String>, set: (Set<String>) -> Unit) {
    GlassCard("Who", Icons.Filled.Person) {
        // The chips' groups in the same order, leaving out empty ones.
        val groups = store.chipGroups.filter { store.groupCount(it) > 0 }
        if (groups.isNotEmpty()) {
            val scroll = rememberScrollState()
            Row(Modifier.bleed(14.dp).fadeEnd(scroll).horizontalScroll(scroll).padding(horizontal = 14.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                val everyone = store.places.map { it.id }.toSet()
                PillChip("Everyone", chosen == everyone) { set(everyone) }
                groups.forEach { group ->
                    val ids = store.places.filter { group in store.groupsOf(it) }.map { it.id }.toSet()
                    PillChip(group, chosen == ids) { set(ids) }
                }
            }
        }
        FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            store.places.forEach { place ->
                val on = place.id in chosen
                PillChip(place.title, on, icon = if (on) Icons.Filled.Check else Icons.Filled.Add) {
                    set(if (on) chosen - place.id else chosen + place.id)
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
    GlassCard(if (count == 0) "Choose who's in it" else if (top == count) "Everyone's working" else if (top == 0) "No one's working then"
        else "Best: $top of $count working", Icons.Filled.CheckCircle, spacing = 0.dp) {
        if (runs.isEmpty()) {
            Text(if (count == 0) "Tap the cities and people above." else "Try another day, or fewer people.", fontSize = 15.sp,
                color = white(0.6f), modifier = Modifier.padding(top = 10.dp))
        }
        runs.take(3).forEachIndexed { i, run ->
            val first = run.first()
            if (i > 0) HorizontalDivider(color = white(0.2f))
            Row(Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable { pick(first) }.padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f)) {
                    Text("${time(first.start)}–${time(run.last().end)}", style = tnum, fontSize = 20.sp, color = Palette.primary)
                    Spacer(Modifier.height(2.dp))
                    // The range bound with no-break spaces: a wrap moves "from 10:00 PM to 11:30 PM" whole (a lone "11:30 PM" was left on line 2).
                    Text(if (run.size == 1) "Your time" else "Your time · start any time from\u00A0${time(first.start)}\u00A0to\u00A0${time(run.last().start)}",
                        fontSize = 13.sp, color = white(0.7f))
                }
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = white(0.5f))
            }
        }
    }
}

/**
 * The day hour by hour (your time): a cell per person, bright while they're working, dim when
 * they're off, dark at night where they are.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun HourGrid(store: Store, slots: List<Slot>, people: List<Place>, pick: (Slot) -> Unit) {
    val hourly = slots.filterIndexed { i, _ -> i % 2 == 0 }
    // The best run: the longest stretch of hours still ahead with the most people working (the first, if tied).
    val ahead = hourly.indices.filter { hourly[it].end > store.now }
    val most = ahead.maxOfOrNull { hourly[it].working } ?: 0
    var best = IntRange.EMPTY
    if (most > 0) {
        var runStart = -1
        for (i in hourly.indices) {
            val hit = hourly[i].end > store.now && hourly[i].working == most
            if (hit && runStart < 0) runStart = i
            if (runStart >= 0 && (!hit || i == hourly.lastIndex)) {
                val run = runStart..(if (hit) i else i - 1)
                if (run.count() > best.count()) best = run
                runStart = -1
            }
        }
    }
    // The count column grows with the font size, so "10/12" never clips at large text.
    val countW = (34f * LocalDensity.current.fontScale.coerceAtMost(1.6f)).dp
    GlassCard("Every hour", Glyphs.grid) {
        // The key first, right under the title, where the eye starts (it sat below the grid, under the fold).
        // A FlowRow, so at large text "Night" moves to a second line instead of clipping (iOS falls back to a VStack).
        FlowRow(horizontalArrangement = Arrangement.spacedBy(14.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Legend(Slot.State.WORKING, "Working")
            Legend(Slot.State.OFF, "Off")
            Legend(Slot.State.NIGHT, "Night")
        }
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            // The column names at 12 sp, white 0.7 (were 11 sp at 0.6: Material's floor), the grid's only key to who is who.
            Row(Modifier.padding(bottom = 2.dp), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                Text("You", Modifier.width(62.dp), fontSize = 12.sp, fontWeight = FontWeight.Medium, color = white(0.7f))
                people.forEach {
                    // 11 sp once the cells get narrow (7+ people), and never cut mid-letter.
                    Text(FindTime.tag(it), Modifier.weight(1f), fontSize = if (people.size > 6) 11.sp else 12.sp, fontWeight = FontWeight.Medium,
                        color = white(0.7f), textAlign = TextAlign.Center, maxLines = 1, softWrap = false, overflow = TextOverflow.Visible)
                }
                Spacer(Modifier.width(countW))
            }
            var i = 0
            while (i < hourly.size) {
                if (i == best.first && !best.isEmpty()) {
                    // The best run, outlined in white just outside its rows.
                    val run = best
                    Column(Modifier.drawWithContent {
                        drawContent()
                        val out = 2.dp.toPx()
                        val line = 1.5.dp.toPx()
                        drawRoundRect(Color.White, topLeft = Offset(-out + line / 2, -out + line / 2),
                            size = Size(size.width + 2 * out - line, size.height + 2 * out - line),
                            cornerRadius = CornerRadius(8.dp.toPx()), style = Stroke(width = line))
                    }, verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        for (k in run) HourRow(store, hourly[k], people, pick)
                    }
                    i = run.last + 1
                } else {
                    HourRow(store, hourly[i], people, pick)
                    i++
                }
            }
        }
    }
}

/** How strong a past hour's cells are in the Every hour grid: 0.9, as on iOS (working 3.5:1 against off, off 3.0:1 (2.96) against night, plus night's edge and moon). */
private const val PAST_ALPHA = 0.9f

/** One hour of the grid: your hour, a cell per person, and how many are working. */
@Composable
private fun HourRow(store: Store, s: Slot, people: List<Place>, pick: (Slot) -> Unit) {
    val label = FindTime.hourLabel(s.start.atZone(store.home).hour, store.use24h)
    val all = s.working == people.size && people.isNotEmpty()
    // Past hours dim their cells only; the hour label and count stay readable (they are still tappable).
    val past = s.end <= store.now
    val countW = (34f * LocalDensity.current.fontScale.coerceAtMost(1.6f)).dp
    Row(Modifier.fillMaxWidth().clickable { pick(s) }
        .semantics(mergeDescendants = true) { contentDescription = "$label, ${s.working} of ${people.size} working" },
        horizontalArrangement = Arrangement.spacedBy(2.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(label, Modifier.width(62.dp), style = tnum, fontSize = 13.sp, color = if (all) Palette.primary else white(0.6f), maxLines = 1)
        s.states.forEach { state ->
            // Past cells a little dimmer (the hour label marks past too); who was working still reads.
            SlotCell(state, Modifier.weight(1f).height(22.dp).alpha(if (past) PAST_ALPHA else 1f))
        }
        Text("${s.working}/${people.size}", Modifier.width(countW), style = tnum, fontSize = 12.sp, color = white(0.6f), textAlign = TextAlign.End, maxLines = 1, softWrap = false)
    }
}

/** One person's cell in an hour of the grid (and in its key): Night with a hairline edge and a small moon, as on the iPhone. */
@Composable
private fun SlotCell(state: Slot.State, modifier: Modifier, moon: androidx.compose.ui.unit.Dp = 10.dp) {
    val shape = RoundedCornerShape(6.dp)
    Box(modifier.clip(shape).background(state.color)
        .then(if (state == Slot.State.NIGHT) Modifier.border(0.75.dp, white(0.35f), shape) else Modifier),
        contentAlignment = Alignment.Center) {
        if (state == Slot.State.NIGHT) Image(painterResource(R.drawable.ic_moon), contentDescription = null,
            colorFilter = ColorFilter.tint(white(0.5f)), modifier = Modifier.size(moon))
    }
}

@Composable
private fun Legend(state: Slot.State, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        SlotCell(state, Modifier.size(14.dp), moon = 9.dp)
        Spacer(Modifier.width(5.dp))
        Text(text, fontSize = 13.sp, color = white(0.7f))
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

    // "9:00 AM–10:00 AM" with small raised AM and PM, so the range fits large; it may wrap only after the dash.
    val (startClock, startSuffix) = TimeMath.clock(start, home, store.use24h)
    val (endClock, endSuffix) = TimeMath.clock(end, home, store.use24h)
    // The thin space before AM/PM is a break point, so a word joiner holds each time together;
    // the zero-width space after the dash is the one place the range may wrap.
    val range = buildAnnotatedString {
        append(clockText(startClock, startSuffix?.let { "\u2060" + it })); append("–\u200B"); append(clockText(endClock, endSuffix?.let { "\u2060" + it }))
    }

    Screen("Meeting Time", onClose, back = true) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().verticalScroll(rememberScrollState())
            .padding(start = 16.dp, end = 16.dp, bottom = 32.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            GlassCard(null, null, spacing = 4.dp) {
                // Regular, not Thin (hairline 2 pt strokes blurred at arm's length), as on the iPhone.
                Text(range, fontSize = 44.sp, lineHeight = 48.sp, fontWeight = FontWeight.Normal, color = Palette.primary,
                    modifier = Modifier.semantics { contentDescription = "${TimeMath.time(start, home, store.use24h)} to ${TimeMath.time(end, home, store.use24h)}" })
                Text("${TimeMath.fullDay(start, home)} · your time · ${FindTime.lengthLabel(length)}", fontSize = 15.sp, color = white(0.6f))
                Spacer(Modifier.height(6.dp))
                // Start 15 minutes earlier or later.
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Start", Modifier.weight(1f), color = white(0.85f))
                    OutlinedButton(onClick = { start = start.minusSeconds(900) }, contentPadding = PaddingValues(0.dp),
                        modifier = Modifier.size(width = 44.dp, height = 34.dp), border = BorderStroke(1.dp, white(0.3f)),
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = Palette.primary)) { Text("−") }
                    Spacer(Modifier.width(8.dp))
                    OutlinedButton(onClick = { start = start.plusSeconds(900) }, contentPadding = PaddingValues(0.dp),
                        modifier = Modifier.size(width = 44.dp, height = 34.dp), border = BorderStroke(1.dp, white(0.3f)),
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = Palette.primary)) { Text("+") }
                }
            }
            if (places.isNotEmpty()) GlassCard(null, null, padding = 0.dp, spacing = 0.dp) {
                Column(Modifier.padding(horizontal = 14.dp, vertical = 4.dp)) {
                    places.forEachIndexed { i, place ->
                        Row(Modifier.fillMaxWidth().padding(vertical = 10.dp).semantics(mergeDescendants = true) {},
                            verticalAlignment = Alignment.CenterVertically) {
                            Column(Modifier.weight(1f)) {
                                Text(place.title, fontSize = 17.sp, fontWeight = FontWeight.Medium, color = Palette.primary, maxLines = 1, overflow = TextOverflow.Ellipsis)
                                Text(status(place), fontSize = 13.sp, maxLines = 1, overflow = TextOverflow.Ellipsis, color = white(0.7f))
                            }
                            Spacer(Modifier.width(8.dp))
                            Text("${TimeMath.time(start, place.zone, store.use24h)}–${TimeMath.time(end, place.zone, store.use24h)}",
                                style = tnum, fontSize = 15.sp, color = Palette.primary, maxLines = 1, softWrap = false)
                        }
                        if (i < places.size - 1) HorizontalDivider(color = white(0.2f))
                    }
                }
            }
            GlassCard(null, null, padding = 0.dp, spacing = 0.dp) {
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
                HorizontalDivider(Modifier.padding(start = 52.dp), color = white(0.2f))
                ActionRow(Icons.Filled.Share, "Share Invite…") {
                    context.startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType("text/plain")
                        .putExtra(Intent.EXTRA_SUBJECT, "Meeting, ${TimeMath.fullDay(start, home)}").putExtra(Intent.EXTRA_TEXT, invite), "Share Invite"))
                }
                HorizontalDivider(Modifier.padding(start = 52.dp), color = white(0.2f))
                ActionRow(Icons.Filled.Check, if (copied) "Copied" else "Copy Invite") {
                    clipboard.setText(AnnotatedString(invite)); copied = true
                }
                HorizontalDivider(Modifier.padding(start = 52.dp), color = white(0.2f))
                ActionRow(Icons.Filled.Refresh, "Go to This Time") { store.jump(start); onGo() }
            }
        }
    }
}

@Composable
private fun ActionRow(icon: ImageVector, label: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(horizontal = 16.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, contentDescription = null, tint = Palette.primary, modifier = Modifier.size(20.dp))
        Spacer(Modifier.width(16.dp))
        Text(label, fontSize = 17.sp, color = Palette.primary)
    }
}

/**
 * A horizontal chip row's trailing 24 dp fades to clear (one two-colour band, only while there is more to scroll), so a
 * chip cut by the screen's edge reads as "more", never as a clipped word ("Sat 1", "Asi", "+ Ne"). As iOS chipRowFade.
 * Put it after [bleed] and before the scroll modifier, so it covers the row's full width.
 */
fun Modifier.fadeEnd(state: ScrollableState, width: androidx.compose.ui.unit.Dp = 24.dp): Modifier = this
    .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
    .drawWithContent {
        drawContent()
        if (!state.canScrollForward) return@drawWithContent
        val w = width.toPx().coerceAtMost(size.width)
        val x0 = size.width - w
        drawRect(Brush.horizontalGradient(listOf(Color.Black, Color.Transparent), startX = x0, endX = size.width),
            topLeft = Offset(x0, 0f), size = Size(w, size.height), blendMode = BlendMode.DstIn)
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
