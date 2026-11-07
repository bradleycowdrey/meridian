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

    /// The groups made by hand, in the user's order.
    var customGroups: [String] { groupOrder }

    /// A continent's automatic group (a custom group named like one is custom).
    func isContinent(_ g: String) -> Bool { Continent.ordered.contains(g) && !groupOrder.contains(g) }

    /// The continents the list's cities are on (when grouping by continent).
    private var presentContinents: Set<String> {
        continentGroups ? Set(places.compactMap { Continent.name(for: $0) }) : []
    }

    /// How many continent chips there could be (0 when grouping by continent is off).
    var continentChipCount: Int { presentContinents.count }

    /// Every group the chips show: the custom groups in order, then the continents (when the list
    /// spans two or more), in a fixed order. A custom group named like a continent merges.
    var chipGroups: [String] {
        let present = presentContinents
        guard present.count >= 2 else { return groupOrder }
        return groupOrder + Continent.ordered.filter { present.contains($0) && !groupOrder.contains($0) }
    }

    /// Every group on the list (for older callers).
    var groups: [String] { chipGroups }

    /// The groups a card is in: its own, and its continent (when grouping by continent).
    func groups(of place: Place) -> [String] {
        var all = place.groups ?? []
        if continentGroups, let continent = Continent.name(for: place), !all.contains(continent) { all.append(continent) }
        return all
    }

    /// How many cards are in a group.
    func groupCount(_ g: String) -> Int { places.filter { groups(of: $0).contains(g) }.count }

    /// The cards the list shows: everyone, or one group (which may have none yet).
    var visiblePlaces: [Place] {
        guard let group = groupFilter, chipGroups.contains(group) else { return places }
        return places.filter { groups(of: $0).contains(group) }
    }

    /// "  Design   Team " -> "Design Team", at most 30 characters.
    nonisolated static func normalizedGroupName(_ raw: String) -> String {
        let words = raw.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        return String(words.joined(separator: " ").prefix(30))
    }

    /// Why a name can't be used for a new group (or for renaming `old`), or nil when it can.
    func groupNameProblem(_ raw: String, renaming old: String? = nil) -> String? {
        let name = Self.normalizedGroupName(raw)
        if name.isEmpty { return "Enter a name." }
        let lower = name.lowercased()
        if lower == "all" || lower == "everyone" { return "\u{201C}All\u{201D} already means every city." }
        if Continent.ordered.contains(where: { $0.lowercased() == lower }) { return "Continents are grouped automatically." }
        if let existing = groupOrder.first(where: { $0 != old && $0.lowercased() == lower }) {
            return "There\u{2019}s already a group called \(existing)."
        }
        if old == nil && groupOrder.count >= CityStore.maxGroups { return "You can have up to \(CityStore.maxGroups) groups." }
        return nil
    }

    /// Makes an empty group; returns its name, or nil when the name can't be used.
    @discardableResult func createGroup(_ raw: String) -> String? {
        guard groupNameProblem(raw) == nil else { return nil }
        let name = Self.normalizedGroupName(raw)
        groupOrder.append(name)
        return name
    }

    /// Renames a group on every card, in the order and in the filter.
    @discardableResult func renameGroup(_ old: String, to raw: String) -> Bool {
        let new = Self.normalizedGroupName(raw)
        if new == old { return true }
        guard groupNameProblem(raw, renaming: old) == nil else { return false }
        let list = places.map { place -> Place in
            guard let groups = place.groups, groups.contains(old) else { return place }
            var renamed = place
            renamed.groups = Array(Set(groups.map { $0 == old ? new : $0 })).sorted()
            return renamed
        }
        if list != places { places = list }
        if let i = groupOrder.firstIndex(of: old) { groupOrder[i] = new } else { groupOrder.append(new) }
        if groupFilter == old { groupFilter = new }
        return true
    }

    /// Deletes a group; its cities stay on the list.
    func deleteGroup(_ g: String) {
        let list = places.map { place -> Place in
            guard let groups = place.groups, groups.contains(g) else { return place }
            var changed = place
            let rest = groups.filter { $0 != g }
            changed.groups = rest.isEmpty ? nil : rest
            return changed
        }
        if list != places { places = list }
        groupOrder.removeAll { $0 == g }
        validateFilter()
    }

    func moveGroups(from source: IndexSet, to destination: Int) {
        groupOrder.move(fromOffsets: source, toOffset: destination)
    }

    /// Puts exactly these cards in a group (and takes the rest out).
    func setMembers(_ ids: Set<UUID>, of g: String) {
        let list = places.map { place -> Place in
            var mine = place.groups ?? []
            let want = ids.contains(place.id)
            guard mine.contains(g) != want else { return place }
            if want { mine.append(g) } else { mine.removeAll { $0 == g } }
            var changed = place
            changed.groups = mine.isEmpty ? nil : Array(Set(mine)).sorted()
            return changed
        }
        if list != places { places = list }
        if !groupOrder.contains(g) { groupOrder.append(g) }
    }

    func setGroups(_ groups: [String], for place: Place) {
        guard let i = places.firstIndex(where: { $0.id == place.id }) else { return }
        let clean = groups.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        places[i].groups = clean.isEmpty ? nil : Array(Set(clean)).sorted()
        for g in clean where !groupOrder.contains(g) { groupOrder.append(g) }
        validateFilter()
    }

    /// A filter whose group has gone goes back to every city (and VoiceOver says so).
    func validateFilter() {
        guard let filter = groupFilter, !chipGroups.contains(filter) else { return }
        groupFilter = nil
        UIAccessibility.post(notification: .announcement, argument: "Showing all cities")
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
