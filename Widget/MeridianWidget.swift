import SwiftUI
import WidgetKit

// The desktop / Notification Center widget. Built by scripts/build-app.sh into
// Meridian.app/Contents/PlugIns/MeridianWidget.appex together with
// Sources/Meridian/Shared/WidgetContent.swift, which holds the views and the data file format.

struct ClockEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct ClockProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClockEntry {
        ClockEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (ClockEntry) -> Void) {
        completion(ClockEntry(date: Date(), snapshot: context.isPreview ? .placeholder : .load()))
    }

    /// One entry per minute for the next hour; the app also asks for a reload when cities change.
    func getTimeline(in context: Context, completion: @escaping (Timeline<ClockEntry>) -> Void) {
        NSTimeZone.resetSystemTimeZone()   // pick up a time zone change on the Mac
        let snapshot = WidgetSnapshot.load()
        let start = Calendar.current.dateInterval(of: .minute, for: Date())?.start ?? Date()
        let entries = (0..<60).map { ClockEntry(date: start.addingTimeInterval(Double($0) * 60), snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

struct MeridianClocksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "MeridianClocks", provider: ClockProvider()) { entry in
            ClockEntryView(entry: entry)
        }
        .configurationDisplayName("Meridian")
        .description("Your cities and their times, in the order you set in Meridian.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct ClockEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ClockEntry

    var body: some View {
        WidgetClockView(snapshot: entry.snapshot, date: entry.date, family: family)
            .containerBackground(WidgetTone.bg, for: .widget)
    }
}

@main
struct MeridianWidgetBundle: WidgetBundle {
    var body: some Widget {
        MeridianClocksWidget()
    }
}
