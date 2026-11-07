import SwiftUI

/// People and groups on the list, and the clocks about to change.
extension CityStore {
    // MARK: People

    /// A card for a person in this card's city ("Ana", in Lisbon), right after it.
    func addPerson(_ name: String, at place: Place) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, canAdd, let i = places.firstIndex(where: { $0.id == place.id }) else { return }
        var person = place
        person.id = UUID()
        person.person = String(trimmed.prefix(40))
        if place.isMyLocation, let city = hereCity { person.name = city }
        places.insert(person, at: i + 1)
    }

    // MARK: Groups

    /// The groups made by hand on the list, A to Z.
    var customGroups: [String] {
        Array(Set(places.flatMap { $0.groups ?? [] })).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Every group on the list: the continents its cities are on (when grouping by continent),
    /// in a fixed order, then the custom groups A to Z. A custom group named like a continent merges.
    var groups: [String] {
        let continents: Set<String> = continentGroups ? Set(places.compactMap { Continent.name(for: $0) }) : []
        return Continent.ordered.filter { continents.contains($0) } + customGroups.filter { !continents.contains($0) }
    }

    /// The groups a card is in: its own, and its continent (when grouping by continent).
    func groups(of place: Place) -> [String] {
        var all = place.groups ?? []
        if continentGroups, let continent = Continent.name(for: place), !all.contains(continent) { all.append(continent) }
        return all
    }

    /// The cards the list shows: everyone, or one group.
    var visiblePlaces: [Place] {
        guard let group = groupFilter, groups.contains(group) else { return places }
        return places.filter { groups(of: $0).contains(group) }
    }

    func setGroups(_ groups: [String], for place: Place) {
        guard let i = places.firstIndex(where: { $0.id == place.id }) else { return }
        let clean = groups.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        places[i].groups = clean.isEmpty ? nil : Array(Set(clean)).sorted()
        if let filter = groupFilter, !self.groups.contains(filter) { groupFilter = nil }
    }

    // MARK: Clock changes

    /// Daylight-saving changes in the next two weeks, where any card is or where you are, with how
    /// far each city will be from you afterwards; the ones closed with × are left out.
    var clockChanges: [ClockChange] {
        let horizon = now.addingTimeInterval(14 * 86_400)
        var zones: [String: String] = [:]   // zone → a name for it
        for place in places where zones[place.timeZoneID] == nil { zones[place.timeZoneID] = place.name }
        zones[TimeZone.current.identifier] = zones[TimeZone.current.identifier] ?? "Your time zone"
        var changes: [ClockChange] = []
        for (id, name) in zones {
            guard let zone = TimeZone(identifier: id), let when = zone.nextDaylightSavingTimeTransition(after: now), when < horizon else { continue }
            let key = "\(id)|\(Int(when.timeIntervalSince1970))"
            guard !dismissedClockChanges.contains(key) else { continue }
            let before = zone.secondsFromGMT(for: when.addingTimeInterval(-60)), after = zone.secondsFromGMT(for: when.addingTimeInterval(60))
            let mine = TimeZone.current
            changes.append(ClockChange(key: key, name: name, zone: zone, date: when, shift: after - before,
                                       isMine: id == mine.identifier,
                                       gapBefore: before - mine.secondsFromGMT(for: when.addingTimeInterval(-60)),
                                       gapAfter: after - mine.secondsFromGMT(for: when.addingTimeInterval(60))))
        }
        return changes.sorted { $0.date < $1.date }
    }

    func dismiss(_ change: ClockChange) { dismissedClockChanges.insert(change.key) }
}

/// A city's clocks going forward or back soon.
struct ClockChange: Identifiable {
    let key: String
    let name: String
    let zone: TimeZone
    let date: Date
    /// Seconds the clocks move (+3600 forward, −3600 back).
    let shift: Int
    let isMine: Bool
    /// The city's offset from you, in seconds, just before and just after.
    let gapBefore: Int
    let gapAfter: Int
    var id: String { key }

    /// "London's clocks go back 1 hr on Sun 25 Oct at 2:00 AM."
    func headline(use24h: Bool) -> String {
        let local = date.addingTimeInterval(-60)   // the time on the clock as it changes
        let when = Self.day.string(from: local, zone: zone)
        // The clock's reading as it changes, on the old offset (2:00 AM back, 1:00 AM forward).
        let old = TimeZone(secondsFromGMT: zone.secondsFromGMT(for: date.addingTimeInterval(-60))) ?? zone
        let at = TimeMath.time(date, in: old, use24h: use24h)
        let amount = Self.hours(abs(shift))
        let whose = isMine ? "Your clocks" : "\(name)\u{2019}s clocks"
        return "\(whose) go \(shift > 0 ? "forward" : "back") \(amount) on \(when) at \(at)."
    }

    /// "Then 7 hr ahead of you (now 8)." when the gap changes.
    var detail: String? {
        guard !isMine || gapBefore != gapAfter else { return nil }
        guard gapBefore != gapAfter else { return "Still the same time apart from you." }
        func gap(_ s: Int) -> String { s == 0 ? "the same time as you" : "\(Self.hours(abs(s))) \(s > 0 ? "ahead of" : "behind") you" }
        return "Then \(gap(gapAfter)) (now \(gapBefore == 0 ? "the same" : Self.hours(abs(gapBefore))))."
    }

    static func hours(_ seconds: Int) -> String {
        let h = seconds / 3600, m = seconds % 3600 / 60
        return m == 0 ? "\(h) hr" : (h == 0 ? "\(m) min" : "\(h):\(String(format: "%02d", m)) hr")
    }

    private static let day = DayFormat()

    /// "Sun 25 Oct", in the city's zone.
    struct DayFormat {
        func string(from date: Date, zone: TimeZone) -> String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_GB")
            f.dateFormat = "EEE d MMM"
            f.timeZone = zone
            return f.string(from: date)
        }
    }
}
