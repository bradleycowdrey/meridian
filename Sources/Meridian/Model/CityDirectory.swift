import Foundation

struct CityEntry: Identifiable, Hashable {
    let name: String
    let region: String
    let timeZoneID: String
    var aliases: [String] = []

    var id: String { "\(name)|\(timeZoneID)" }
}

/// Searchable list of cities: every IANA zone city, plus popular cities that share a zone,
/// airport codes, abbreviations (PST, CET) and UTC offsets.
enum CityDirectory {
    static let all: [CityEntry] = {
        var entries: [CityEntry] = TimeZone.knownTimeZoneIdentifiers.compactMap { id in
            let parts = id.split(separator: "/")
            guard parts.count >= 2, !["Etc", "SystemV", "US"].contains(String(parts[0])) else { return nil }
            let name = parts.last!.replacingOccurrences(of: "_", with: " ")
            return CityEntry(name: name, region: String(parts[0]), timeZoneID: id)
        }

        let extras: [(String, String, String, [String])] = [
            ("San Francisco", "United States", "America/Los_Angeles", ["SFO", "SF", "Bay Area"]),
            ("Seattle", "United States", "America/Los_Angeles", ["SEA"]),
            ("San Diego", "United States", "America/Los_Angeles", ["SAN"]),
            ("Las Vegas", "United States", "America/Los_Angeles", ["LAS"]),
            ("Portland", "United States", "America/Los_Angeles", ["PDX"]),
            ("Salt Lake City", "United States", "America/Denver", ["SLC"]),
            ("Austin", "United States", "America/Chicago", ["AUS"]),
            ("Dallas", "United States", "America/Chicago", ["DFW"]),
            ("Houston", "United States", "America/Chicago", ["IAH"]),
            ("Minneapolis", "United States", "America/Chicago", ["MSP"]),
            ("Boston", "United States", "America/New_York", ["BOS"]),
            ("Washington DC", "United States", "America/New_York", ["DC", "IAD", "DCA"]),
            ("Miami", "United States", "America/New_York", ["MIA"]),
            ("Atlanta", "United States", "America/New_York", ["ATL"]),
            ("Philadelphia", "United States", "America/New_York", ["PHL"]),
            ("Mumbai", "India", "Asia/Kolkata", ["BOM", "Bombay"]),
            ("Delhi", "India", "Asia/Kolkata", ["DEL", "New Delhi"]),
            ("Bengaluru", "India", "Asia/Kolkata", ["BLR", "Bangalore"]),
            ("Beijing", "China", "Asia/Shanghai", ["PEK"]),
            ("Shenzhen", "China", "Asia/Shanghai", ["SZX"]),
            ("Osaka", "Japan", "Asia/Tokyo", ["KIX"]),
            ("Tel Aviv", "Israel", "Asia/Jerusalem", ["TLV"]),
            ("Abu Dhabi", "United Arab Emirates", "Asia/Dubai", ["AUH"]),
            ("Barcelona", "Spain", "Europe/Madrid", ["BCN"]),
            ("Munich", "Germany", "Europe/Berlin", ["MUC"]),
            ("Frankfurt", "Germany", "Europe/Berlin", ["FRA"]),
            ("Milan", "Italy", "Europe/Rome", ["MXP"]),
            ("Geneva", "Switzerland", "Europe/Zurich", ["GVA"]),
            ("Edinburgh", "United Kingdom", "Europe/London", ["EDI"]),
            ("Manchester", "United Kingdom", "Europe/London", ["MAN"]),
            ("Cape Town", "South Africa", "Africa/Johannesburg", ["CPT"]),
            ("Rio de Janeiro", "Brazil", "America/Sao_Paulo", ["GIG", "Rio"]),
            ("Brisbane", "Australia", "Australia/Brisbane", ["BNE"]),
            ("Wellington", "New Zealand", "Pacific/Auckland", ["WLG"]),
            ("UTC", "Coordinated Universal Time", "UTC", ["GMT", "Zulu", "Z"]),
        ]
        entries += extras.compactMap { name, region, id, aliases in
            TimeZone(identifier: id) == nil ? nil : CityEntry(name: name, region: region, timeZoneID: id, aliases: aliases)
        }

        // Airport codes for cities that are already IANA zone names.
        let airports: [String: [String]] = [
            "Los Angeles": ["LAX"], "New York": ["JFK", "NYC", "LGA", "EWR"], "Chicago": ["ORD"],
            "Denver": ["DEN"], "Phoenix": ["PHX"], "Toronto": ["YYZ"], "Vancouver": ["YVR"],
            "Mexico City": ["MEX"], "Sao Paulo": ["GRU", "São Paulo"], "London": ["LHR", "LGW"],
            "Paris": ["CDG"], "Amsterdam": ["AMS"], "Berlin": ["BER"], "Madrid": ["MAD"],
            "Rome": ["FCO"], "Zurich": ["ZRH"], "Dublin": ["DUB"], "Lisbon": ["LIS"],
            "Stockholm": ["ARN"], "Warsaw": ["WAW"], "Istanbul": ["IST"], "Moscow": ["SVO"],
            "Dubai": ["DXB"], "Singapore": ["SIN"], "Hong Kong": ["HKG"], "Tokyo": ["HND", "NRT"],
            "Seoul": ["ICN"], "Shanghai": ["PVG"], "Bangkok": ["BKK"], "Jakarta": ["CGK"],
            "Manila": ["MNL"], "Sydney": ["SYD"], "Melbourne": ["MEL"], "Auckland": ["AKL"],
            "Johannesburg": ["JNB"], "Cairo": ["CAI"], "Lagos": ["LOS"], "Nairobi": ["NBO"],
            "Honolulu": ["HNL"], "Anchorage": ["ANC"], "Kolkata": ["CCU", "Calcutta"],
        ]
        entries = entries.map { entry in
            var entry = entry
            entry.aliases += airports[entry.name] ?? []
            return entry
        }
        return entries.sorted { $0.name < $1.name }
    }()

    static func search(_ query: String) -> [CityEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return [] }
        let lower = q.lowercased()

        var results: [(Int, CityEntry)] = []
        for entry in all {
            let name = entry.name.lowercased()
            if entry.aliases.contains(where: { $0.lowercased() == lower }) {
                results.append((0, entry))
            } else if name.hasPrefix(lower) {
                results.append((1, entry))
            } else if name.contains(lower) || entry.aliases.contains(where: { $0.lowercased().hasPrefix(lower) }) {
                results.append((2, entry))
            } else if entry.region.lowercased().hasPrefix(lower) {
                results.append((3, entry))
            }
        }
        var ranked = results.sorted { ($0.0, $0.1.name) < ($1.0, $1.1.name) }.map(\.1)

        // "PST", "CET", "IST"... (not offsets like "GMT+5", handled below, and not UTC/GMT,
        // which already have a city entry)
        let offset = offsetZone(q)
        if offset == nil, q.count <= 5, !["UTC", "GMT"].contains(q.uppercased()),
           let zone = TimeZone(abbreviation: q.uppercased()) {
            ranked.insert(CityEntry(name: q.uppercased(), region: zone.identifier, timeZoneID: zone.identifier), at: 0)
        }
        // "UTC+5", "GMT-3", "+9"
        if let zone = offset {
            ranked.insert(CityEntry(name: TimeMath.offsetLabel(seconds: zone.secondsFromGMT()), region: "Fixed offset, no daylight saving", timeZoneID: zone.identifier), at: 0)
        }
        return Array(ranked.prefix(40))
    }

    private static func offsetZone(_ query: String) -> TimeZone? {
        var text = query.uppercased().replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "−", with: "-")
        for prefix in ["UTC", "GMT"] where text.hasPrefix(prefix) { text.removeFirst(prefix.count) }
        guard let sign = text.first, sign == "+" || sign == "-" else { return nil }
        let parts = text.dropFirst().split(separator: ":")
        guard let hours = Int(parts.first ?? ""), hours <= 14 else { return nil }
        let minutes = parts.count > 1 ? Int(parts[1]) ?? -1 : 0
        guard (0...59).contains(minutes), parts.count <= 2 else { return nil }
        let seconds = (hours * 3600 + minutes * 60) * (sign == "-" ? -1 : 1)
        return TimeZone(secondsFromGMT: seconds)
    }
}
