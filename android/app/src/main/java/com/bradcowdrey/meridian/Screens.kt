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

/** Rename a city (not My Location, which is named from where you are). */
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
                SwitchRow("24-Hour Time", store.use24h) { store.updateUse24h(it) }
                SwitchRow("Highlight Working Hours", store.showWorkHours) { store.updateShowWorkHours(it) }
                if (store.showWorkHours) {
                    Text("Each city follows the usual working days and hours where it is: Sunday to Thursday, 8 AM to 5 PM in Riyadh; Monday to Friday, 9 AM to 5 PM in Denver; shorter days in Ramadan and Spain's summer. To change a city's, tap its card, then Working Days & Hours.",
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
        title = { Text(place.name) },
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
