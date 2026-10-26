import AppIntents
import SwiftUI
import WidgetKit

// The Meridian widget, for the Mac (desktop and Notification Center; built by scripts/build-app.sh
// into Meridian.app/Contents/PlugIns/MeridianWidget.appex) and the iPhone (Home and Lock Screen;
// built from ios/project.yml). Sources/Meridian/Shared/WidgetContent.swift holds the views and
// the data file format; WidgetCities.swift the Edit Widget city picker.

struct ClockEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct ClockProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ClockEntry {
        ClockEntry(date: Date(), snapshot: .placeholder)
    }

    func snapshot(for configuration: ClockConfiguration, in context: Context) async -> ClockEntry {
        ClockEntry(date: Date(), snapshot: context.isPreview && configuration.followApp ? .placeholder : configuration.snapshot())
    }

    /// One entry per minute for the next hour; the app also asks for a reload when cities change.
    func timeline(for configuration: ClockConfiguration, in context: Context) async -> Timeline<ClockEntry> {
        NSTimeZone.resetSystemTimeZone()   // pick up a time zone change on the Mac
        let snapshot = configuration.snapshot()
        let start = Calendar.current.dateInterval(of: .minute, for: Date())?.start ?? Date()
        let entries = (0..<60).map { ClockEntry(date: start.addingTimeInterval(Double($0) * 60), snapshot: snapshot) }
        return Timeline(entries: entries, policy: .atEnd)
    }
}

struct MeridianClocksWidget: Widget {
    #if os(iOS)
    static let families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge,
                                           .accessoryInline, .accessoryCircular, .accessoryRectangular]
    #else
    static let families: [WidgetFamily] = [.systemSmall, .systemMedium, .systemLarge]
    #endif

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "MeridianClocks", intent: ClockConfiguration.self, provider: ClockProvider()) { entry in
            ClockEntryView(entry: entry)
        }
        .configurationDisplayName("Meridian")
        .description("Your cities and their times. Edit the widget to choose its own cities.")
        .supportedFamilies(Self.families)
        .contentMarginsDisabled()
    }
}

struct ClockEntryView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ClockEntry

    var body: some View {
        #if os(iOS)
        switch family {
        case .accessoryInline, .accessoryCircular, .accessoryRectangular:
            AccessoryClockView(snapshot: entry.snapshot, date: entry.date, family: family)
                .containerBackground(for: .widget) {
                    if family == .accessoryCircular { AccessoryWidgetBackground() }
                }
        default:
            clock
        }
        #else
        clock
        #endif
    }

    private var clock: some View {
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
