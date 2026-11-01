import Foundation

/// National public holidays, offline (Resources/Data/holidays.tsv, from scripts/gen-data.py: five
/// years for every country the python-holidays project covers). A city on a holiday isn't working.
enum Holidays {
    /// Settings: count public holidays as days off (on unless turned off).
    static var counted: Bool {
        get { UserDefaults.standard.object(forKey: "countHolidays") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "countHolidays") }
    }

    /// The holiday's name on this local day in the city ("Thanksgiving Day"), or nil.
    static func name(for place: Place, at date: Date) -> String? {
        guard counted, let cc = place.country else { return nil }
        let d = place.calendar.dateComponents([.year, .month, .day], from: date)
        return name(country: cc, year: d.year ?? 0, month: d.month ?? 0, day: d.day ?? 0)
    }

    static func name(country: String, year: Int, month: Int, day: Int) -> String? {
        table[country]?[year * 10_000 + month * 100 + day]
    }

    /// The years the data covers (holidays outside them aren't known).
    static var years: ClosedRange<Int>? {
        let all = table.values.flatMap(\.keys).map { $0 / 10_000 }
        guard let lo = all.min(), let hi = all.max() else { return nil }
        return lo...hi
    }

    /// Country code → yyyymmdd → name.
    private static let table: [String: [Int: String]] = {
        guard let url = Bundle.main.url(forResource: "holidays", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        var map: [String: [Int: String]] = [:]
        for line in text.split(separator: "\n") {
            let p = line.split(separator: "\t", maxSplits: 2)
            guard p.count == 3, let day = Int(p[1]) else { continue }
            map[String(p[0]), default: [:]][day] = map[String(p[0])]?[day] ?? String(p[2])
        }
        return map
    }()
}

extension Place {
    /// The city's country code: its own, or its time zone's.
    var country: String? { countryCode ?? WorkWeek.countryByZone[timeZoneID] }
}
