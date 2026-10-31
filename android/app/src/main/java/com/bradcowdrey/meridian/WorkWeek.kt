package com.bradcowdrey.meridian

import java.time.DayOfWeek
import java.time.Instant

/**
 * Working days and hours for each city, the same as the Mac and iPhone apps: the usual week where
 * the city is, unless that city has its own (set from its card). Weekends come from the Unicode
 * CLDR (v45) week data mapped from time zone to country, plus: India and Uganda Saturday and
 * Sunday (offices work Monday to Friday); Bangladesh, the Maldives and Palestine Friday and
 * Saturday; Brunei Friday and Sunday. Every other zone: Saturday and Sunday. Hours default to
 * Settings. Days are numbered as on the Mac and iPhone: 1 is Sunday, 7 is Saturday.
 */
object WorkWeek {
    private val weekendByZone: Map<String, Set<Int>> = mapOf(
        // Sunday and Friday: Brunei
        "Asia/Brunei" to setOf(1, 6),
        // Thursday and Friday: Afghanistan
        "Asia/Kabul" to setOf(5, 6),
        // Friday: Iran
        "Asia/Tehran" to setOf(6),
        // Friday and Saturday: Algeria, Bahrain, Bangladesh, Egypt, Iraq, Israel, Jordan, Kuwait, Libya, Maldives, Oman, Palestine, Qatar, Saudi Arabia, Sudan, Syria, Yemen
        "Africa/Algiers" to setOf(6, 7),
        "Africa/Cairo" to setOf(6, 7),
        "Africa/Khartoum" to setOf(6, 7),
        "Africa/Tripoli" to setOf(6, 7),
        "Asia/Aden" to setOf(6, 7),
        "Asia/Amman" to setOf(6, 7),
        "Asia/Baghdad" to setOf(6, 7),
        "Asia/Bahrain" to setOf(6, 7),
        "Asia/Dacca" to setOf(6, 7),
        "Asia/Damascus" to setOf(6, 7),
        "Asia/Dhaka" to setOf(6, 7),
        "Asia/Gaza" to setOf(6, 7),
        "Asia/Hebron" to setOf(6, 7),
        "Asia/Jerusalem" to setOf(6, 7),
        "Asia/Kuwait" to setOf(6, 7),
        "Asia/Muscat" to setOf(6, 7),
        "Asia/Qatar" to setOf(6, 7),
        "Asia/Riyadh" to setOf(6, 7),
        "Asia/Tel_Aviv" to setOf(6, 7),
        "Indian/Maldives" to setOf(6, 7),    )
    private val standardWeekend = setOf(1, 7)

    fun usualDays(zoneId: String): Set<Int> = (1..7).toSet() - (weekendByZone[zoneId] ?: standardWeekend)

    /** 1 is Sunday ... 7 is Saturday. */
    fun dayNumber(day: DayOfWeek): Int = day.value % 7 + 1

    fun isWorkHour(hour: Int, start: Int, end: Int): Boolean {
        if (start == end || (start == 0 && end == 24)) return true
        return if (start <= end) hour in start until end else hour >= start || hour < end
    }

    fun isWorking(place: Place, at: Instant, start: Int, end: Int): Boolean {
        val local = at.atZone(place.zone)
        if (dayNumber(local.dayOfWeek) !in (place.workDays ?: usualDays(place.zoneId))) return false
        return isWorkHour(local.hour, place.workStart ?: start, place.workEnd ?: end)
    }

    private val names = listOf("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday")

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
}
