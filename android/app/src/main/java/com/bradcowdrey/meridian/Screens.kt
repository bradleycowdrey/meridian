package com.bradcowdrey.meridian

import android.content.Intent
import android.net.Uri
import android.widget.FrameLayout
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
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
private fun Screen(title: String, onBack: () -> Unit, backLabel: String = "Done", content: @Composable (PaddingValues) -> Unit) {
    Scaffold(
        containerColor = Palette.bg,
        topBar = {
            CenterAlignedTopAppBar(
                title = { Text(title, fontWeight = FontWeight.SemiBold) },
                navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.Filled.ArrowBack, "Back") } },
                actions = { TextButton(onClick = onBack) { Text(backLabel, color = Palette.cream, fontWeight = FontWeight.SemiBold) } },
                colors = TopAppBarDefaults.centerAlignedTopAppBarColors(containerColor = Palette.bg,
                    titleContentColor = Palette.primary, navigationIconContentColor = Palette.cream),
            )
        },
        content = content,
    )
}

/** Search by city, airport code (SFO), abbreviation (PST) or offset (UTC+5:30); tap to add. All offline. */
@Composable
fun AddCityScreen(store: Store, onDone: () -> Unit) {
    var query by remember { mutableStateOf(if (store.demo) "san" else "") }
    val results = remember(query) { CityDirectory.search(query) }
    val focus = remember { FocusRequester() }
    LaunchedEffect(Unit) { if (!store.demo) focus.requestFocus() }
    Screen("Add City", onDone, backLabel = "Cancel") { padding ->
        Column(Modifier.padding(padding)) {
            OutlinedTextField(query, { query = it }, singleLine = true, placeholder = { Text("City, SFO, PST, UTC+5…") },
                shape = RoundedCornerShape(12.dp), modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp).focusRequester(focus))
            if (!store.canAdd) Text("You can track up to ${Store.MAX_PLACES} cities. Remove one to add another.",
                color = Palette.muted, modifier = Modifier.padding(16.dp))
            else if (query.isBlank()) Text("Type a city, an airport code like SFO, a time zone like PST, or an offset like UTC+5:30.",
                fontSize = 14.sp, color = Palette.muted, modifier = Modifier.padding(16.dp))
            LazyColumn {
                items(results, key = { it.name + it.zoneId }) { entry ->
                    val added = store.contains(entry)
                    val zone = runCatching { java.time.ZoneId.of(entry.zoneId) }.getOrNull()
                    Row(Modifier.fillMaxWidth().clickable(enabled = !added && store.canAdd) { store.add(entry); onDone() }
                        .padding(horizontal = 20.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(entry.name, fontWeight = FontWeight.SemiBold)
                            Text(entry.region.replace("_", " "), fontSize = 13.sp, color = Palette.muted)
                        }
                        if (zone != null) Column(horizontalAlignment = Alignment.End) {
                            Text(TimeMath.time(store.now, zone, store.use24h), color = Palette.secondary)
                            Text(TimeMath.offsetLabel(TimeMath.offsetSeconds(zone, store.now)), fontSize = 13.sp, color = Palette.muted)
                        }
                        Spacer(Modifier.width(12.dp))
                        Icon(if (added) Icons.Filled.Check else Icons.Filled.Add, contentDescription = if (added) "Already added" else "Add",
                            tint = if (added) Palette.faint else Palette.cream)
                    }
                    HorizontalDivider(Modifier.padding(horizontal = 20.dp), color = Palette.border, thickness = 0.5.dp)
                }
            }
        }
    }
}

/** Remove, reorder and rename (tap a city). */
@Composable
fun EditCitiesScreen(store: Store, onDone: () -> Unit) {
    var renaming by remember { mutableStateOf<Place?>(null) }
    Screen("Edit Cities", onDone) { padding ->
        LazyColumn(Modifier.padding(padding)) {
            items(store.places, key = { it.id }) { place ->
                Row(Modifier.fillMaxWidth().padding(start = 20.dp, end = 8.dp, top = 6.dp, bottom = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                    IconButton(onClick = { store.remove(place) }) { Icon(Icons.Filled.Delete, "Remove ${place.name}", tint = Color(0xFFFF6B6B)) }
                    Column(Modifier.weight(1f).clickable { renaming = place }.padding(vertical = 6.dp)) {
                        Text(place.name, fontWeight = FontWeight.SemiBold)
                        Text(TimeMath.offsetLabel(TimeMath.offsetSeconds(place.zone, store.now)), fontSize = 13.sp, color = Palette.muted)
                    }
                    Text(TimeMath.time(store.now, place.zone, store.use24h), color = Palette.secondary)
                    IconButton(onClick = { store.move(place, -1) }, enabled = place != store.places.first()) { Icon(Icons.Filled.KeyboardArrowUp, "Move up") }
                    IconButton(onClick = { store.move(place, 1) }, enabled = place != store.places.last()) { Icon(Icons.Filled.KeyboardArrowDown, "Move down") }
                }
                HorizontalDivider(Modifier.padding(horizontal = 20.dp), color = Palette.border, thickness = 0.5.dp)
            }
            item {
                Text(if (store.places.isEmpty()) "No cities. Tap + on the main screen to add one." else "Use the arrows to reorder. Tap a city to rename it.",
                    fontSize = 13.sp, color = Palette.muted, modifier = Modifier.padding(20.dp))
            }
        }
    }
    renaming?.let { place -> RenameDialog(place) { name -> if (name != null) store.rename(place, name); renaming = null } }
}

@Composable
fun RenameDialog(place: Place, onDone: (String?) -> Unit) {
    var name by remember { mutableStateOf(place.name) }
    AlertDialog(
        onDismissRequest = { onDone(null) },
        title = { Text("Rename City") },
        text = { OutlinedTextField(name, { name = it }, singleLine = true) },
        confirmButton = { TextButton(onClick = { onDone(name) }) { Text("Rename") } },
        dismissButton = { TextButton(onClick = { onDone(null) }) { Text("Cancel") } },
    )
}

@Composable
fun SettingsScreen(store: Store, onDone: () -> Unit) {
    val context = LocalContext.current
    fun open(url: String) = context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
    Screen("Settings", onDone) { padding ->
        Column(Modifier.padding(padding).verticalScroll(rememberScrollState()).padding(horizontal = 16.dp)) {
            Section("TIME") {
                SwitchRow("24-Hour Time", store.use24h) { store.setUse24h(it) }
                SwitchRow("Highlight Working Hours", store.showWorkHours) { store.setShowWorkHours(it) }
                if (store.showWorkHours) {
                    StepperRow("Work starts at ${TimeMath.hourLabel(store.workStart, store.use24h)}", { store.setWorkStart(store.workStart - 1) }, { store.setWorkStart(store.workStart + 1) })
                    StepperRow("Work ends at ${TimeMath.hourLabel(store.workEnd % 24, store.use24h)}", { store.setWorkEnd(store.workEnd - 1) }, { store.setWorkEnd(store.workEnd + 1) })
                }
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
        Switch(on, set, colors = SwitchDefaults.colors(checkedTrackColor = Palette.cream, checkedThumbColor = Palette.bg))
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
fun TermsScreen(onAgree: () -> Unit) {
    val context = LocalContext.current
    Column(Modifier.fillMaxSize().background(Palette.bg).systemBarsPadding().padding(28.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Spacer(Modifier.weight(1f))
        Image(painterResource(R.drawable.mark), contentDescription = null, modifier = Modifier.size(88.dp).clip(RoundedCornerShape(20.dp)))
        Spacer(Modifier.height(20.dp))
        Text("Terms of Use and Privacy", fontSize = 22.sp, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.height(16.dp))
        Text("Meridian is free and provided as is, without warranty. You use it at your own risk: always confirm meeting and travel times. Your cities stay on your phone.\n\nBy tapping I Agree and using Meridian, you agree to the Terms of Use and Privacy at bradcowdrey.com/legal.",
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
