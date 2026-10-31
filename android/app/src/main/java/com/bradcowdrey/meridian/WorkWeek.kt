package com.bradcowdrey.meridian

import android.icu.util.IslamicCalendar
import java.time.DayOfWeek
import java.time.Instant

/**
 * Working days and hours for each city, the same as the Mac and iPhone apps: the usual week where
 * it is, unless that city has its own (set from its card). The usual week comes from research into
 * every country and territory in the city list (docs/working-hours.md lists sources, notes and
 * confidence): working days, the hours for each day, shorter hours in Ramadan, and summer
 * schedules. A zone with no country (UTC) works Monday to Friday in Settings' hours.
 * Days are numbered as on the Mac and iPhone: 1 is Sunday, 7 is Saturday.
 */
object WorkWeek {
    data class Hours(val start: Double, val end: Double)
    class Schedule(val week: List<Hours?>, val ramadan: Hours?, val summerMonths: Set<Int>, val summer: List<Hours?>?)

    fun schedule(zoneId: String): Schedule? = countryByZone[zoneId]?.let { schedules[it] }

    fun usualDays(zoneId: String): Set<Int> =
        schedule(zoneId)?.week?.let { w -> w.indices.filter { w[it] != null }.map { it + 1 }.toSet() } ?: setOf(2, 3, 4, 5, 6)

    /** The hours most days keep where the city is (9 to 5 in New York). */
    fun typicalHours(zoneId: String): Hours? =
        schedule(zoneId)?.week?.filterNotNull()?.groupingBy { it }?.eachCount()?.maxByOrNull { it.value }?.key

    /** 1 is Sunday ... 7 is Saturday. */
    fun dayNumber(day: DayOfWeek): Int = day.value % 7 + 1

    fun isWorkHour(hour: Int, start: Int, end: Int): Boolean = contains(hour.toDouble(), Hours(start.toDouble(), end.toDouble()))

    private fun contains(time: Double, h: Hours): Boolean {
        if (h.start == h.end || (h.start == 0.0 && h.end == 24.0)) return true
        return if (h.start <= h.end) time >= h.start && time < h.end else time >= h.start || time < h.end
    }

    /** This city's working hours on the day of this moment, or null on a day off. */
    fun hours(place: Place, at: Instant, start: Int, end: Int): Hours? {
        val local = at.atZone(place.zone)
        val weekday = dayNumber(local.dayOfWeek)
        val schedule = schedule(place.zoneId)
        var today: Hours? = if (schedule != null) {
            val week = (if (local.monthValue in schedule.summerMonths) schedule.summer else null) ?: schedule.week
            val day = week[weekday - 1]
            if (day != null && schedule.ramadan != null && isRamadan(at, place.zoneId)) schedule.ramadan else day
        } else if (weekday in 2..6) Hours(start.toDouble(), end.toDouble()) else null
        place.workDays?.let { days ->
            if (weekday !in days) return null
            if (today == null) today = typicalHours(place.zoneId) ?: Hours(start.toDouble(), end.toDouble())
        }
        val usual = today ?: return null
        if (place.workStart != null || place.workEnd != null)
            return Hours(place.workStart?.toDouble() ?: usual.start, place.workEnd?.toDouble() ?: usual.end)
        return usual
    }

    fun isWorking(place: Place, at: Instant, start: Int, end: Int): Boolean {
        val h = hours(place, at, start, end) ?: return false
        val local = at.atZone(place.zone)
        return contains(local.hour + local.minute / 60.0, h)
    }

    /** Ramadan (the ninth month of the Islamic calendar) on this day where the city is. */
    fun isRamadan(at: Instant, zoneId: String): Boolean = runCatching {
        val cal = IslamicCalendar(android.icu.util.TimeZone.getTimeZone(zoneId))
        cal.calculationType = IslamicCalendar.CalculationType.ISLAMIC_UMALQURA
        cal.timeInMillis = at.toEpochMilli()
        cal.get(android.icu.util.Calendar.MONTH) == IslamicCalendar.RAMADAN
    }.getOrDefault(false)

    private val names = listOf("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday")
    private val months = listOf("January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December")

    /** "Monday to Friday", "Sunday to Thursday", or the days listed. */
    fun describe(days: Set<Int>): String {
        val sorted = days.sorted()
        if (sorted.isEmpty()) return "No working days"
        if (sorted.size == 7) return "Every day"
        for (first in sorted) {
            val run = (0 until sorted.size).map { (first - 1 + it) % 7 + 1 }
            if (run.toSet() == days && sorted.size > 2) return "${names[first - 1]} to ${names[run.last() - 1]}"
        }
        return sorted.joinToString(", ") { names[it - 1] }
    }

    /** "Sunday to Thursday, 8 AM to 5 PM; Friday 9 AM to 1 PM": the usual week where the city is. */
    fun describeUsual(zoneId: String, use24h: Boolean): String {
        val schedule = schedule(zoneId)
        val typical = typicalHours(zoneId)
        if (schedule == null || typical == null) return "Monday to Friday, in the hours set in Settings"
        val main = schedule.week.indices.filter { schedule.week[it] == typical }.map { it + 1 }.toSet()
        val text = StringBuilder("${describe(main)}, ${label(typical, use24h)}")
        schedule.week.forEachIndexed { i, h -> if (h != null && h != typical) text.append("; ${names[i]} ${label(h, use24h)}") }
        schedule.ramadan?.let { text.append(". In Ramadan, ${label(it, use24h)}") }
        val summer = schedule.summer?.filterNotNull()?.firstOrNull()
        if (summer != null && schedule.summerMonths.isNotEmpty())
            text.append(". In ${schedule.summerMonths.sorted().joinToString(" and ") { months[it - 1] }}, ${label(summer, use24h)}")
        return text.toString()
    }

    fun label(h: Hours, use24h: Boolean) = "${clock(h.start, use24h)} to ${clock(h.end, use24h)}"

    fun clock(time: Double, use24h: Boolean): String {
        val h = time.toInt(); val m = Math.round((time - h) * 60).toInt()
        if (use24h) return "%02d:%02d".format(h, m)
        val h12 = if (h % 12 == 0) 12 else h % 12
        return "$h12${if (m > 0) ":%02d".format(m) else ""}${TimeMath.THIN}${if (h % 24 < 12) "AM" else "PM"}"
    }

    // Data

    private fun parseHours(text: String): Hours? {
        val p = text.split("-")
        if (p.size != 2) return null
        val s = p[0].toDoubleOrNull() ?: return null
        val e = p[1].toDoubleOrNull() ?: return null
        return Hours(s, e)
    }

    private fun parseWeek(text: String) = text.trim().split(" ").map { parseHours(it) }

    val schedules: Map<String, Schedule> by lazy {
        TABLE.trim().lines().mapNotNull { line ->
            val f = line.split("|")
            if (f.size < 2) null else f[0] to Schedule(
                parseWeek(f[1]),
                f.getOrNull(2)?.let { parseHours(it) },
                f.getOrNull(3)?.split(",")?.mapNotNull { it.toIntOrNull() }?.toSet() ?: emptySet(),
                f.getOrNull(4)?.takeIf { it.isNotBlank() }?.let { parseWeek(it) })
        }.toMap()
    }

    val countryByZone: Map<String, String> by lazy {
        ZONES.split(Regex("\\s+")).mapNotNull { pair -> pair.split("=").takeIf { it.size == 2 }?.let { it[0] to it[1] } }.toMap()
    }

    /** Country | Sunday … Saturday hours ("-" off) | Ramadan hours | summer months | summer week. */
    private const val TABLE = """
AD|- 9-18 9-18 9-18 9-18 9-18 -
AE|- 9-18 9-18 9-18 9-18 9-18 -|9-15
AF|8-16 8-16 8-16 8-16 8-12 - 8-16|9-14
AG|- 8-16.5 8-16.5 8-16.5 8-16.5 8-16.5 -
AI|- 8-16 8-16 8-16 8-16 8-16 -
AL|- 8-16.5 8-16.5 8-16.5 8-16.5 8-16.5 -
AM|- 9-18 9-18 9-18 9-18 9-18 -
AO|- 8-17 8-17 8-17 8-17 8-17 -
AR|- 9-18 9-18 9-18 9-18 9-18 -
AS|- 7.5-16 7.5-16 7.5-16 7.5-16 7.5-16 -
AT|- 8-17 8-17 8-17 8-17 8-15 -
AU|- 9-17 9-17 9-17 9-17 9-17 -
AW|- 7.5-16.5 7.5-16.5 7.5-16.5 7.5-16.5 7.5-16.5 -
AX|- 8-16 8-16 8-16 8-16 8-16 -
AZ|- 9-18 9-18 9-18 9-18 9-18 -
BA|- 8-16 8-16 8-16 8-16 8-16 -
BB|- 8.25-16.5 8.25-16.5 8.25-16.5 8.25-16.5 8.25-16.5 -
BD|9-17 9-17 9-17 9-17 9-17 - -|9-15.5
BE|- 8.5-17.5 8.5-17.5 8.5-17.5 8.5-17.5 8.5-17.5 -
BF|- 7.5-16 7.5-16 7.5-16 7.5-16 7.5-16.5 -
BG|- 9-18 9-18 9-18 9-18 9-18 -
BH|8-17 8-17 8-17 8-17 8-17 - -|9-15
BI|- 7.5-15.5 7.5-15.5 7.5-15.5 7.5-15.5 7.5-15.5 -
BJ|- 8-18.5 8-18.5 8-18.5 8-18.5 8-18.5 -
BL|- 8-17 8-17 8-17 8-17 8-17 -
BM|- 9-17 9-17 9-17 9-17 9-17 -
BN|- 9-17 9-17 9-17 9-17 9-17 -|8-14
BO|- 8.5-18 8.5-18 8.5-18 8.5-18 8.5-18 -
BQ|- 7.5-16.5 7.5-16.5 7.5-16.5 7.5-16.5 7.5-16.5 -
BR|- 9-18 9-18 9-18 9-18 9-18 -
BS|- 9-17 9-17 9-17 9-17 9-17 -
BT|- 9-17 9-17 9-17 9-17 9-17 -
BW|- 7.5-16.5 7.5-16.5 7.5-16.5 7.5-16.5 7.5-16.5 -
BY|- 9-18 9-18 9-18 9-18 9-18 -
BZ|- 8-17 8-17 8-17 8-17 8-17 -
CA|- 9-17 9-17 9-17 9-17 9-17 -
CC|- 8-16.5 8-16.5 8-16.5 8-16.5 8-16.5 -
CD|- 8-16 8-16 8-16 8-16 8-16 -
CF|- 7.5-15.5 7.5-15.5 7.5-15.5 7.5-15.5 7.5-15.5 -
CG|- 8-16 8-16 8-16 8-16 8-16 -
CH|- 8-17.5 8-17.5 8-17.5 8-17.5 8-17.5 -
CI|- 8-17.5 8-17.5 8-17.5 8-17.5 8-17.5 -
CK|- 8-16 8-16 8-16 8-16 8-16 -
CL|- 9-18 9-18 9-18 9-18 9-17 -
CM|- 7.5-15.5 7.5-15.5 7.5-15.5 7.5-15.5 7.5-15.5 -
CN|- 9-18 9-18 9-18 9-18 9-18 -
CO|- 8-17.5 8-17.5 8-17.5 8-17.5 8-17.5 -
CR|- 8-17 8-17 8-17 8-17 8-17 -
CU|- 8-17 8-17 8-17 8-17 8-17 -
CV|- 8-16 8-16 8-16 8-16 8-16 -
CW|- 7.5-16.5 7.5-16.5 7.5-16.5 7.5-16.5 7.5-16.5 -
CX|- 8-16.5 8-16.5 8-16.5 8-16.5 8-16.5 -
CY|- 8-17 8-17 8-17 8-17 8-17 -
CZ|- 8-16.5 8-16.5 8-16.5 8-16.5 8-16.5 -
DE|- 8-17 8-17 8-17 8-17 8-16 -
DJ|7-14 7-14 7-14 7-14 7-14 - -
DK|- 8-16 8-16 8-16 8-16 8-15 -
DM|- 8-17 8-16 8-16 8-16 8-16 -
DO|- 8-17 8-17 8-17 8-17 8-17 -
DZ|8-16.5 8-16.5 8-16.5 8-16.5 8-16.5 - -|9.5-16
EC|- 8.5-17.5 8.5-17.5 8.5-17.5 8.5-17.5 8.5-17.5 -
EE|- 9-17 9-17 9-17 9-17 9-17 -
EG|9-17 9-17 9-17 9-17 9-17 - -|10-15
EH|- 8.5-16.5 8.5-16.5 8.5-16.5 8.5-16.5 8.5-16.5 -|9-15
ER|- 8-18 8-18 8-18 8-18 8-18 -
ES|- 9-19 9-19 9-19 9-19 8-15 -||7,8|- 8-15 8-15 8-15 8-15 8-15 -
ET|- 8.5-17.5 8.5-17.5 8.5-17.5 8.5-17.5 8.5-17.5 -
FI|- 8-16 8-16 8-16 8-16 8-16 -
FJ|- 8-16.5 8-16.5 8-16.5 8-16.5 8-16 -
FK|- 8-16.5 8-16.5 8-16.5 8-16.5 8-16.5 -
FM|- 8-17 8-17 8-17 8-17 8-17 -
FO|- 8-16 8-16 8-16 8-16 8-15 -
FR|- 9-18 9-18 9-18 9-18 9-18 -
GA|- 7.5-16.5 7.5-16.5 7.5-16.5 7.5-16.5 7.5-16.5 -
GB|- 9-17.5 9-17.5 9-17.5 9-17.5 9-17.5 -
GD|- 8-16 8-16 8-16 8-16 8-16 -
GE|- 9-18 9-18 9-18 9-18 9-18 -
GF|- 8-16.5 8-16.5 8-16.5 8-16.5 8-16.5 -
GG|- 9-17.5 9-17.5 9-17.5 9-17.5 9-17.5 -
GH|- 8-17 8-17 8-17 8-17 8-17 -
GI|- 9-17.5 9-17.5 9-17.5 9-17.5 9-17.5 -
GL|- 8-16 8-16 8-16 8-16 8-16 -
GM|- 8-16 8-16 8-16 8-16 8-12.5 -
GN|- 8-16.5 8-16.5 8-16.5 8-16.5 8-13 -
GP|- 7.5-16.5 7.5-16.5 7.5-16.5 7.5-16.5 7.5-16.5 -
GQ|- 8-16 8-16 8-16 8-16 8-16 -
GR|- 9-17 9-17 9-17 9-17 9-17 -
GS|- 8-16.5 8-16.5 8-16.5 8-16.5 8-16.5 -
GT|- 8-17 8-17 8-17 8-17 8-17 -
GU|- 8-17 8-17 8-17 8-17 8-17 -
GW|- 8-15 8-15 8-15 8-15 8-15 -
GY|- 8-16.5 8-16.5 8-16.5 8-16.5 8-16.5 -
HK|- 9-18 9-18 9-18 9-18 9-18 -
HN|- 8-17 8-17 8-17 8-17 8-17 -
HR|- 8-16 8-16 8-16 8-16 8-16 -
HT|- 8-16 8-16 8-16 8-16 8-16 -
HU|- 8-16.5 8-16.5 8-16.5 8-16.5 8-15 -
ID|- 8-17 8-17 8-17 8-17 8-17 -|8-16
IE|- 9-17.5 9-17.5 9-17.5 9-17.5 9-17.5 -
IL|9-18 9-18 9-18 9-18 9-18 9-13 -
IM|- 9-17.5 9-17.5 9-17.5 9-17.5 9-17.5 -
IN|- 9.5-18.5 9.5-18.5 9.5-18.5 9.5-18.5 9.5-18.5 -
IO|- 8-17 8-17 8-17 8-17 8-17 -
IQ|8-16 8-16 8-16 8-16 8-16 - -|9-14
IR|8-16 8-16 8-16 8-16 8-12 - 8-16|9-14
IS|- 9-17 9-17 9-17 9-17 9-17 -
IT|- 9-18 9-18 9-18 9-18 9-18 -
JE|- 9-17.5 9-17.5 9-17.5 9-17.5 9-17.5 -
JM|- 8.5-17 8.5-17 8.5-17 8.5-17 8.5-16 -
JO|8-17 8-17 8-17 8-17 8-17 - -|10-15
JP|- 9-18 9-18 9-18 9-18 9-18 -
KE|- 8-17 8-17 8-17 8-17 8-17 -
KG|- 9-18 9-18 9-18 9-18 9-18 -
KH|- 8-17 8-17 8-17 8-17 8-17 8-12
KI|- 8-16.25 8-16.25 8-16.25 8-16.25 8-16.25 -
KM|- 7.5-16 7.5-16 7.5-16 7.5-16 7.5-12.5 -
KN|- 8-16 8-16 8-16 8-16 8-16 -
KP|- 9-18 9-18 9-18 9-18 9-18 9-18
KR|- 9-18 9-18 9-18 9-18 9-18 -
KW|8-17 8-17 8-17 8-17 8-17 - -|10-14
KY|- 8.5-17 8.5-17 8.5-17 8.5-17 8.5-17 -
KZ|- 9-18 9-18 9-18 9-18 9-18 -
LA|- 8-16.5 8-16.5 8-16.5 8-16.5 8-16.5 -
LB|- 8-17 8-17 8-17 8-17 8-17 -
LC|- 8-16.5 8-16.5 8-16.5 8-16.5 8-16.5 -
LI|- 8-17 8-17 8-17 8-17 8-17 -
LK|- 8.5-17 8.5-17 8.5-17 8.5-17 8.5-17 -
LR|- 8-17 8-17 8-17 8-17 8-17 -
LS|- 8-16.5 8-16.5 8-16.5 8-16.5 8-16.5 -
LT|- 8-17 8-17 8-17 8-17 8-15.75 -
LU|- 8.5-17.5 8.5-17.5 8.5-17.5 8.5-17.5 8.5-17.5 -
LV|- 8.5-17 8.5-17 8.5-17 8.5-17 8.5-16 -
LY|8-16 8-16 8-16 8-16 8-16 - -|9-14
MA|- 8.5-16.5 8.5-16.5 8.5-16.5 8.5-16.5 8.5-16.5 -|9-15
MC|- 9-18 9-18 9-18 9-18 9-18 -
MD|- 8-17 8-17 8-17 8-17 8-17 -
ME|- 8-16 8-16 8-16 8-16 8-16 -
MF|- 8-17 8-17 8-17 8-17 8-17 -
MG|- 8-17 8-17 8-17 8-17 8-17 -
MH|- 8-17 8-17 8-17 8-17 8-17 -
MK|- 8-16 8-16 8-16 8-16 8-16 -
ML|- 7.5-16 7.5-16 7.5-16 7.5-16 7.5-12.5 -
MM|- 9-17 9-17 9-17 9-17 9-17 -
MN|- 9-18 9-18 9-18 9-18 9-18 -
MO|- 9-18 9-18 9-18 9-18 9-18 -
MP|- 7.5-16.5 7.5-16.5 7.5-16.5 7.5-16.5 7.5-16.5 -
MQ|- 7.5-16.5 7.5-16.5 7.5-16.5 7.5-16.5 7.5-16.5 -
MR|- 8-16 8-16 8-16 8-16 8-12 -
MS|- 8-16 8-16 8-16 8-16 8-16 -
MT|- 8-17 8-17 8-17 8-17 8-17 -||7,8|- 7.5-14 7.5-14 7.5-14 7.5-14 7.5-14 -
MU|- 8.5-16.25 8.5-16.25 8.5-16.25 8.5-16.25 8.5-16.25 -
MV|8-16 8-16 8-16 8-16 8-16 - -|9-13
MW|- 7.5-17 7.5-17 7.5-17 7.5-17 7.5-13 -
MX|- 9-18 9-18 9-18 9-18 9-18 -
MY|- 9-18 9-18 9-18 9-18 9-18 -|8-16.5
MZ|- 8-17 8-17 8-17 8-17 8-17 -
NA|- 8-17 8-17 8-17 8-17 8-17 -
NC|- 7.5-16.5 7.5-16.5 7.5-16.5 7.5-16.5 7.5-16.5 -
NE|- 7.5-17.5 7.5-17.5 7.5-17.5 7.5-17.5 7.5-12.5 -
NF|- 8.5-16.5 8.5-16.5 8.5-16.5 8.5-16.5 8.5-16.5 -
NG|- 8-17 8-17 8-17 8-17 8-17 -
NI|- 8-17 8-17 8-17 8-17 8-17 -
NL|- 8.5-17.5 8.5-17.5 8.5-17.5 8.5-17.5 8.5-17.5 -
NO|- 8-16 8-16 8-16 8-16 8-16 -||6,7,8|- 8-15 8-15 8-15 8-15 8-15 -
NP|- 9-17 9-17 9-17 9-17 9-17 -
NR|- 8-16.5 8-16.5 8-16.5 8-16.5 8-16.5 -
NU|- 8-16 8-16 8-16 8-16 8-16 -
NZ|- 8.5-17 8.5-17 8.5-17 8.5-17 8.5-17 -
OM|8-17 8-17 8-17 8-17 8-17 - -|9-15
PA|- 8-17 8-17 8-17 8-17 8-17 -
PE|- 9-18 9-18 9-18 9-18 9-18 -
PF|- 7.5-15.5 7.5-15.5 7.5-15.5 7.5-15.5 7.5-14.5 -
PG|- 8-16 8-16 8-16 8-16 8-16 -
PH|- 8-17 8-17 8-17 8-17 8-17 -
PK|- 9-17.5 9-17.5 9-17.5 9-17.5 9-17.5 -|9-15
PL|- 8-17 8-17 8-17 8-17 8-17 -
PM|- 8.5-17.5 8.5-17.5 8.5-17.5 8.5-17.5 8.5-17.5 -
PN|- 8-16 8-16 8-16 8-16 8-16 -
PR|- 8-17 8-17 8-17 8-17 8-17 -
PS|8-16 8-16 8-16 8-16 8-16 - -|9-14
PT|- 9-18 9-18 9-18 9-18 9-18 -
PW|- 8-17 8-17 8-17 8-17 8-17 -
PY|- 8-17 8-17 8-17 8-17 8-17 -
QA|8-17 8-17 8-17 8-17 8-17 - -|9-15
RE|- 8-16.5 8-16.5 8-16.5 8-16.5 8-16.5 -
RO|- 9-18 9-18 9-18 9-18 9-18 -
RS|- 8-16 8-16 8-16 8-16 8-16 -
RU|- 9-18 9-18 9-18 9-18 9-18 -
RW|- 9-17 9-17 9-17 9-17 9-17 -
SA|8-17 8-17 8-17 8-17 8-17 - -|10-16
SB|- 8-16.5 8-16.5 8-16.5 8-16.5 8-16.5 -
SC|- 8.5-16.5 8.5-16.5 8.5-16.5 8.5-16.5 8.5-16.5 -
SD|8-15 8-15 8-15 8-15 8-15 - -|9-14
SE|- 8-17 8-17 8-17 8-17 8-17 -
SG|- 9-18 9-18 9-18 9-18 9-18 -
SH|- 8.5-16 8.5-16 8.5-16 8.5-16 8.5-16 -
SI|- 8-16 8-16 8-16 8-16 8-16 -
SJ|- 8-16 8-16 8-16 8-16 8-16 -||6,7,8|- 8-15 8-15 8-15 8-15 8-15 -
SK|- 8-16.5 8-16.5 8-16.5 8-16.5 8-16.5 -
SL|- 8-17 8-17 8-17 8-17 8-17 -
SM|- 9-17 9-17 9-17 9-17 9-17 -
SN|- 8-17 8-17 8-17 8-17 8-17 -
SO|8-16 8-16 8-16 8-16 8-12 - 8-16
SR|- 7.5-15 7.5-15 7.5-15 7.5-15 7.5-15 -
SS|- 8-17 8-17 8-17 8-17 8-17 -
ST|- 7.5-15.5 7.5-15.5 7.5-15.5 7.5-15.5 7.5-15.5 -
SV|- 8-17 8-17 8-17 8-17 8-17 -
SX|- 8-16.5 8-16.5 8-16.5 8-16.5 8-16.5 -
SY|8-15.5 8-15.5 8-15.5 8-15.5 8-15.5 - -|9-14
SZ|- 8-16.75 8-16.75 8-16.75 8-16.75 8-16.75 -
TC|- 8.5-16.5 8.5-16.5 8.5-16.5 8.5-16.5 8.5-16 -
TD|- 7.5-15.5 7.5-15.5 7.5-15.5 7.5-15.5 7.5-12 -
TF|- 9-17 9-17 9-17 9-17 9-17 -
TG|- 7.5-17.5 7.5-17.5 7.5-17.5 7.5-17.5 7.5-17.5 -
TH|- 8.5-17.5 8.5-17.5 8.5-17.5 8.5-17.5 8.5-17.5 -
TJ|- 8-17 8-17 8-17 8-17 8-17 -
TK|- 8-16 8-16 8-16 8-16 8-16 -
TL|- 8-17.5 8-17.5 8-17.5 8-17.5 8-17.5 -
TM|- 9-18 9-18 9-18 9-18 9-18 -
TN|- 8-17 8-17 8-17 8-17 8-13 -|8-14.5|7,8|- 8-14.5 8-14.5 8-14.5 8-14.5 8-13.5 -
TO|- 8.5-16.5 8.5-16.5 8.5-16.5 8.5-16.5 8.5-16.5 -
TR|- 9-18 9-18 9-18 9-18 9-18 -
TT|- 8-16.25 8-16.25 8-16.25 8-16.25 8-16.25 -
TV|- 8-16 8-16 8-16 8-16 8-16 -
TW|- 9-18 9-18 9-18 9-18 9-18 -
TZ|- 8-17 8-17 8-17 8-17 8-17 -
UA|- 9-18 9-18 9-18 9-18 9-18 -
UG|- 8-17 8-17 8-17 8-17 8-17 -
UM|- 8-16.5 8-16.5 8-16.5 8-16.5 8-16.5 -
US|- 9-17 9-17 9-17 9-17 9-17 -
UY|- 9-18 9-18 9-18 9-18 9-18 -
UZ|- 9-18 9-18 9-18 9-18 9-18 -
VA|- 8-14 8-14 8-14 8-14 8-14 8-14
VC|- 8-16.25 8-16.25 8-16.25 8-16.25 8-16.25 -
VE|- 8-17 8-17 8-17 8-17 8-17 -
VG|- 8.5-16.5 8.5-16.5 8.5-16.5 8.5-16.5 8.5-16.5 -
VI|- 8-17 8-17 8-17 8-17 8-17 -
VN|- 8-17.5 8-17.5 8-17.5 8-17.5 8-17.5 -
VU|- 7.5-16.5 7.5-16.5 7.5-16.5 7.5-16.5 7.5-16.5 -
WF|- 7.5-15.5 7.5-15.5 7.5-15.5 7.5-15.5 7.5-15.5 -
WS|- 8-16.5 8-16.5 8-16.5 8-16.5 8-16.5 -
YE|8-15 8-15 8-15 8-15 8-15 - -|10-14
YT|- 7.5-16 7.5-16 7.5-16 7.5-16 7.5-16 -
ZA|- 8-17 8-17 8-17 8-17 8-17 -
ZM|- 8-17 8-17 8-17 8-17 8-17 -
ZW|- 8-16.5 8-16.5 8-16.5 8-16.5 8-16.5 -
"""

    /** Time zone = country (ISO 3166), from the Unicode CLDR. */
    private const val ZONES = """
Africa/Abidjan=CI Africa/Accra=GH Africa/Addis_Ababa=ET Africa/Algiers=DZ Africa/Asmara=ER Africa/Asmera=ER
Africa/Bamako=ML Africa/Bangui=CF Africa/Banjul=GM Africa/Bissau=GW Africa/Blantyre=MW Africa/Brazzaville=CG
Africa/Bujumbura=BI Africa/Cairo=EG Africa/Casablanca=MA Africa/Ceuta=ES Africa/Conakry=GN Africa/Dakar=SN
Africa/Dar_es_Salaam=TZ Africa/Djibouti=DJ Africa/Douala=CM Africa/El_Aaiun=EH Africa/Freetown=SL Africa/Gaborone=BW
Africa/Harare=ZW Africa/Johannesburg=ZA Africa/Juba=SS Africa/Kampala=UG Africa/Khartoum=SD Africa/Kigali=RW
Africa/Kinshasa=CD Africa/Lagos=NG Africa/Libreville=GA Africa/Lome=TG Africa/Luanda=AO Africa/Lubumbashi=CD
Africa/Lusaka=ZM Africa/Malabo=GQ Africa/Maputo=MZ Africa/Maseru=LS Africa/Mbabane=SZ Africa/Mogadishu=SO
Africa/Monrovia=LR Africa/Nairobi=KE Africa/Ndjamena=TD Africa/Niamey=NE Africa/Nouakchott=MR Africa/Ouagadougou=BF
Africa/Porto-Novo=BJ Africa/Sao_Tome=ST Africa/Timbuktu=ML Africa/Tripoli=LY Africa/Tunis=TN Africa/Windhoek=NA
America/Adak=US America/Anchorage=US America/Anguilla=AI America/Antigua=AG America/Araguaina=BR America/Argentina/Buenos_Aires=AR
America/Argentina/Catamarca=AR America/Argentina/ComodRivadavia=AR America/Argentina/Cordoba=AR America/Argentina/Jujuy=AR America/Argentina/La_Rioja=AR America/Argentina/Mendoza=AR
America/Argentina/Rio_Gallegos=AR America/Argentina/Salta=AR America/Argentina/San_Juan=AR America/Argentina/San_Luis=AR America/Argentina/Tucuman=AR America/Argentina/Ushuaia=AR
America/Aruba=AW America/Asuncion=PY America/Atikokan=CA America/Atka=US America/Bahia=BR America/Bahia_Banderas=MX
America/Barbados=BB America/Belem=BR America/Belize=BZ America/Blanc-Sablon=CA America/Boa_Vista=BR America/Bogota=CO
America/Boise=US America/Buenos_Aires=AR America/Cambridge_Bay=CA America/Campo_Grande=BR America/Cancun=MX America/Caracas=VE
America/Catamarca=AR America/Cayenne=GF America/Cayman=KY America/Chicago=US America/Chihuahua=MX America/Ciudad_Juarez=MX
America/Coral_Harbour=CA America/Cordoba=AR America/Costa_Rica=CR America/Creston=CA America/Cuiaba=BR America/Curacao=CW
America/Danmarkshavn=GL America/Dawson=CA America/Dawson_Creek=CA America/Denver=US America/Detroit=US America/Dominica=DM
America/Edmonton=CA America/Eirunepe=BR America/El_Salvador=SV America/Ensenada=MX America/Fort_Nelson=CA America/Fort_Wayne=US
America/Fortaleza=BR America/Glace_Bay=CA America/Godthab=GL America/Goose_Bay=CA America/Grand_Turk=TC America/Grenada=GD
America/Guadeloupe=GP America/Guatemala=GT America/Guayaquil=EC America/Guyana=GY America/Halifax=CA America/Havana=CU
America/Hermosillo=MX America/Indiana/Indianapolis=US America/Indiana/Knox=US America/Indiana/Marengo=US America/Indiana/Petersburg=US America/Indiana/Tell_City=US
America/Indiana/Vevay=US America/Indiana/Vincennes=US America/Indiana/Winamac=US America/Indianapolis=US America/Inuvik=CA America/Iqaluit=CA
America/Jamaica=JM America/Jujuy=AR America/Juneau=US America/Kentucky/Louisville=US America/Kentucky/Monticello=US America/Knox_IN=US
America/Kralendijk=BQ America/La_Paz=BO America/Lima=PE America/Los_Angeles=US America/Louisville=US America/Lower_Princes=SX
America/Maceio=BR America/Managua=NI America/Manaus=BR America/Marigot=MF America/Martinique=MQ America/Matamoros=MX
America/Mazatlan=MX America/Mendoza=AR America/Menominee=US America/Merida=MX America/Metlakatla=US America/Mexico_City=MX
America/Miquelon=PM America/Moncton=CA America/Monterrey=MX America/Montevideo=UY America/Montreal=CA America/Montserrat=MS
America/Nassau=BS America/New_York=US America/Nipigon=CA America/Nome=US America/Noronha=BR America/North_Dakota/Beulah=US
America/North_Dakota/Center=US America/North_Dakota/New_Salem=US America/Nuuk=GL America/Ojinaga=MX America/Panama=PA America/Pangnirtung=CA
America/Paramaribo=SR America/Phoenix=US America/Port-au-Prince=HT America/Port_of_Spain=TT America/Porto_Acre=BR America/Porto_Velho=BR
America/Puerto_Rico=PR America/Punta_Arenas=CL America/Rainy_River=CA America/Rankin_Inlet=CA America/Recife=BR America/Regina=CA
America/Resolute=CA America/Rio_Branco=BR America/Rosario=AR America/Santa_Isabel=MX America/Santarem=BR America/Santiago=CL
America/Santo_Domingo=DO America/Sao_Paulo=BR America/Scoresbysund=GL America/Shiprock=US America/Sitka=US America/St_Barthelemy=BL
America/St_Johns=CA America/St_Kitts=KN America/St_Lucia=LC America/St_Thomas=VI America/St_Vincent=VC America/Swift_Current=CA
America/Tegucigalpa=HN America/Thule=GL America/Thunder_Bay=CA America/Tijuana=MX America/Toronto=CA America/Tortola=VG
America/Vancouver=CA America/Virgin=VI America/Whitehorse=CA America/Winnipeg=CA America/Yakutat=US America/Yellowknife=CA
Antarctica/Macquarie=AU Antarctica/South_Pole=NZ Arctic/Longyearbyen=SJ Asia/Aden=YE Asia/Almaty=KZ Asia/Amman=JO
Asia/Anadyr=RU Asia/Aqtau=KZ Asia/Aqtobe=KZ Asia/Ashgabat=TM Asia/Ashkhabad=TM Asia/Atyrau=KZ
Asia/Baghdad=IQ Asia/Bahrain=BH Asia/Baku=AZ Asia/Bangkok=TH Asia/Barnaul=RU Asia/Beirut=LB
Asia/Bishkek=KG Asia/Brunei=BN Asia/Calcutta=IN Asia/Chita=RU Asia/Choibalsan=MN Asia/Chongqing=CN
Asia/Chungking=CN Asia/Colombo=LK Asia/Dacca=BD Asia/Damascus=SY Asia/Dhaka=BD Asia/Dili=TL
Asia/Dubai=AE Asia/Dushanbe=TJ Asia/Famagusta=CY Asia/Gaza=PS Asia/Harbin=CN Asia/Hebron=PS
Asia/Ho_Chi_Minh=VN Asia/Hong_Kong=HK Asia/Hovd=MN Asia/Irkutsk=RU Asia/Istanbul=TR Asia/Jakarta=ID
Asia/Jayapura=ID Asia/Jerusalem=IL Asia/Kabul=AF Asia/Kamchatka=RU Asia/Karachi=PK Asia/Kashgar=CN
Asia/Kathmandu=NP Asia/Katmandu=NP Asia/Khandyga=RU Asia/Kolkata=IN Asia/Krasnoyarsk=RU Asia/Kuala_Lumpur=MY
Asia/Kuching=MY Asia/Kuwait=KW Asia/Macao=MO Asia/Macau=MO Asia/Magadan=RU Asia/Makassar=ID
Asia/Manila=PH Asia/Muscat=OM Asia/Nicosia=CY Asia/Novokuznetsk=RU Asia/Novosibirsk=RU Asia/Omsk=RU
Asia/Oral=KZ Asia/Phnom_Penh=KH Asia/Pontianak=ID Asia/Pyongyang=KP Asia/Qatar=QA Asia/Qostanay=KZ
Asia/Qyzylorda=KZ Asia/Rangoon=MM Asia/Riyadh=SA Asia/Saigon=VN Asia/Sakhalin=RU Asia/Samarkand=UZ
Asia/Seoul=KR Asia/Shanghai=CN Asia/Singapore=SG Asia/Srednekolymsk=RU Asia/Taipei=TW Asia/Tashkent=UZ
Asia/Tbilisi=GE Asia/Tehran=IR Asia/Tel_Aviv=IL Asia/Thimbu=BT Asia/Thimphu=BT Asia/Tokyo=JP
Asia/Tomsk=RU Asia/Ujung_Pandang=ID Asia/Ulaanbaatar=MN Asia/Ulan_Bator=MN Asia/Urumqi=CN Asia/Ust-Nera=RU
Asia/Vientiane=LA Asia/Vladivostok=RU Asia/Yakutsk=RU Asia/Yangon=MM Asia/Yekaterinburg=RU Asia/Yerevan=AM
Atlantic/Azores=PT Atlantic/Bermuda=BM Atlantic/Canary=ES Atlantic/Cape_Verde=CV Atlantic/Faeroe=FO Atlantic/Faroe=FO
Atlantic/Jan_Mayen=SJ Atlantic/Madeira=PT Atlantic/Reykjavik=IS Atlantic/South_Georgia=GS Atlantic/St_Helena=SH Atlantic/Stanley=FK
Australia/ACT=AU Australia/Adelaide=AU Australia/Brisbane=AU Australia/Broken_Hill=AU Australia/Canberra=AU Australia/Currie=AU
Australia/Darwin=AU Australia/Eucla=AU Australia/Hobart=AU Australia/LHI=AU Australia/Lindeman=AU Australia/Lord_Howe=AU
Australia/Melbourne=AU Australia/NSW=AU Australia/North=AU Australia/Perth=AU Australia/Queensland=AU Australia/South=AU
Australia/Sydney=AU Australia/Tasmania=AU Australia/Victoria=AU Australia/West=AU Australia/Yancowinna=AU Brazil/Acre=BR
Brazil/DeNoronha=BR Brazil/East=BR Brazil/West=BR Canada/Atlantic=CA Canada/Central=CA Canada/East-Saskatchewan=CA
Canada/Eastern=CA Canada/Mountain=CA Canada/Newfoundland=CA Canada/Pacific=CA Canada/Saskatchewan=CA Canada/Yukon=CA
Chile/Continental=CL Chile/EasterIsland=CL Europe/Amsterdam=NL Europe/Andorra=AD Europe/Astrakhan=RU Europe/Athens=GR
Europe/Belfast=GB Europe/Belgrade=RS Europe/Berlin=DE Europe/Bratislava=SK Europe/Brussels=BE Europe/Bucharest=RO
Europe/Budapest=HU Europe/Busingen=DE Europe/Chisinau=MD Europe/Copenhagen=DK Europe/Dublin=IE Europe/Gibraltar=GI
Europe/Guernsey=GG Europe/Helsinki=FI Europe/Isle_of_Man=IM Europe/Istanbul=TR Europe/Jersey=JE Europe/Kaliningrad=RU
Europe/Kiev=UA Europe/Kirov=RU Europe/Kyiv=UA Europe/Lisbon=PT Europe/Ljubljana=SI Europe/London=GB
Europe/Luxembourg=LU Europe/Madrid=ES Europe/Malta=MT Europe/Mariehamn=AX Europe/Minsk=BY Europe/Monaco=MC
Europe/Moscow=RU Europe/Nicosia=CY Europe/Oslo=NO Europe/Paris=FR Europe/Podgorica=ME Europe/Prague=CZ
Europe/Riga=LV Europe/Rome=IT Europe/Samara=RU Europe/San_Marino=SM Europe/Sarajevo=BA Europe/Saratov=RU
Europe/Simferopol=UA Europe/Skopje=MK Europe/Sofia=BG Europe/Stockholm=SE Europe/Tallinn=EE Europe/Tirane=AL
Europe/Tiraspol=MD Europe/Ulyanovsk=RU Europe/Uzhgorod=UA Europe/Vaduz=LI Europe/Vatican=VA Europe/Vienna=AT
Europe/Vilnius=LT Europe/Volgograd=RU Europe/Warsaw=PL Europe/Zagreb=HR Europe/Zaporozhye=UA Europe/Zurich=CH
Indian/Antananarivo=MG Indian/Chagos=IO Indian/Christmas=CX Indian/Cocos=CC Indian/Comoro=KM Indian/Kerguelen=TF
Indian/Mahe=SC Indian/Maldives=MV Indian/Mauritius=MU Indian/Mayotte=YT Indian/Reunion=RE Mexico/BajaNorte=MX
Mexico/BajaSur=MX Mexico/General=MX Pacific/Apia=WS Pacific/Auckland=NZ Pacific/Bougainville=PG Pacific/Chatham=NZ
Pacific/Chuuk=FM Pacific/Easter=CL Pacific/Efate=VU Pacific/Enderbury=KI Pacific/Fakaofo=TK Pacific/Fiji=FJ
Pacific/Funafuti=TV Pacific/Galapagos=EC Pacific/Gambier=PF Pacific/Guadalcanal=SB Pacific/Guam=GU Pacific/Honolulu=US
Pacific/Johnston=US Pacific/Kanton=KI Pacific/Kiritimati=KI Pacific/Kosrae=FM Pacific/Kwajalein=MH Pacific/Majuro=MH
Pacific/Marquesas=PF Pacific/Midway=UM Pacific/Nauru=NR Pacific/Niue=NU Pacific/Norfolk=NF Pacific/Noumea=NC
Pacific/Pago_Pago=AS Pacific/Palau=PW Pacific/Pitcairn=PN Pacific/Pohnpei=FM Pacific/Ponape=FM Pacific/Port_Moresby=PG
Pacific/Rarotonga=CK Pacific/Saipan=MP Pacific/Samoa=AS Pacific/Tahiti=PF Pacific/Tarawa=KI Pacific/Tongatapu=TO
Pacific/Truk=FM Pacific/Wake=UM Pacific/Wallis=WF Pacific/Yap=FM US/Alaska=US US/Aleutian=US
US/Arizona=US US/Central=US US/East-Indiana=US US/Eastern=US US/Hawaii=US US/Indiana-Starke=US
US/Michigan=US US/Mountain=US US/Pacific=US US/Pacific-New=US US/Samoa=AS
"""
}
