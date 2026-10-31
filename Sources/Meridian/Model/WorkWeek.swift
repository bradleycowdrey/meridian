import Foundation

/// Working days and hours for each city: the usual week where the city is, unless that city has
/// its own (set from its card on iPhone and Android, or in Settings → Cities on the Mac).
///
/// Weekends come from the Unicode CLDR (v45) week data, which Apple and Android use for their
/// calendars, mapped from time zone to country, plus:
/// - India and Uganda: Saturday and Sunday (CLDR has the legal rest day, Sunday; offices work
///   Monday to Friday).
/// - Bangladesh, the Maldives and Palestine: Friday and Saturday; Brunei: Friday and Sunday.
/// Every other time zone: Saturday and Sunday. Working hours default to those in Settings.
/// Weekdays are numbered as in Calendar: 1 is Sunday, 7 is Saturday.
enum WorkWeek {
    static let weekendByZone: [String: Set<Int>] = [
        // Sunday and Friday: Brunei
        "Asia/Brunei": [1, 6],
        // Thursday and Friday: Afghanistan
        "Asia/Kabul": [5, 6],
        // Friday: Iran
        "Asia/Tehran": [6],
        // Friday and Saturday: Algeria, Bahrain, Bangladesh, Egypt, Iraq, Israel, Jordan, Kuwait, Libya, Maldives, Oman, Palestine, Qatar, Saudi Arabia, Sudan, Syria, Yemen
        "Africa/Algiers": [6, 7],
        "Africa/Cairo": [6, 7],
        "Africa/Khartoum": [6, 7],
        "Africa/Tripoli": [6, 7],
        "Asia/Aden": [6, 7],
        "Asia/Amman": [6, 7],
        "Asia/Baghdad": [6, 7],
        "Asia/Bahrain": [6, 7],
        "Asia/Dacca": [6, 7],
        "Asia/Damascus": [6, 7],
        "Asia/Dhaka": [6, 7],
        "Asia/Gaza": [6, 7],
        "Asia/Hebron": [6, 7],
        "Asia/Jerusalem": [6, 7],
        "Asia/Kuwait": [6, 7],
        "Asia/Muscat": [6, 7],
        "Asia/Qatar": [6, 7],
        "Asia/Riyadh": [6, 7],
        "Asia/Tel_Aviv": [6, 7],
        "Indian/Maldives": [6, 7],    ]
    static let standardWeekend: Set<Int> = [1, 7]

    /// The usual working days in a time zone.
    static func usualDays(zoneID: String) -> Set<Int> {
        Set(1...7).subtracting(weekendByZone[zoneID] ?? standardWeekend)
    }

    /// Is this hour within the working hours start..<end (start after end runs overnight; equal,
    /// or 0 to 24, means all day)?
    static func isWorkHour(_ hour: Int, start: Int, end: Int) -> Bool {
        if start == end || (start == 0 && end == 24) { return true }
        return start <= end ? (hour >= start && hour < end) : (hour >= start || hour < end)
    }

    /// Is it a working day and hour in this city at this moment?
    static func isWorking(_ place: Place, at date: Date, start: Int, end: Int) -> Bool {
        let cal = place.calendar
        let days = place.workDays ?? usualDays(zoneID: place.timeZoneID)
        guard days.contains(cal.component(.weekday, from: date)) else { return false }
        return isWorkHour(cal.component(.hour, from: date), start: place.workStart ?? start, end: place.workEnd ?? end)
    }

    /// "Monday to Friday", "Sunday to Thursday", or the days listed ("Monday, Wednesday").
    static func describe(_ days: Set<Int>) -> String {
        let names = Calendar(identifier: .gregorian).weekdaySymbols   // Sunday first
        let sorted = days.sorted()
        guard !sorted.isEmpty else { return "No working days" }
        if sorted.count == 7 { return "Every day" }
        // A run of days, allowing it to wrap past Saturday (e.g. Saturday to Wednesday).
        for first in sorted {
            let run = (0..<sorted.count).map { (first - 1 + $0) % 7 + 1 }
            if Set(run) == days, sorted.count > 2 { return "\(names[first - 1]) to \(names[run.last! - 1])" }
        }
        return sorted.map { names[$0 - 1] }.joined(separator: ", ")
    }
}
