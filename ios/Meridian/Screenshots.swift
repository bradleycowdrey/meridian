import SwiftUI
import WidgetKit

/// Screenshot mode, used by CI in the iOS Simulator (and for App Store screenshots):
///   -screenshots            demo cities, nothing saved
///   -screen <name>          main (default), travel, edit, add, settings, terms, widgets
///   -render-widgets         also save every widget face to Documents/widgets/*.png
/// Inert unless launched with -screenshots.
enum Screenshots {
    static let isActive = CommandLine.arguments.contains("-screenshots")
    static var screen: String {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "-screen"), i + 1 < args.count else { return "main" }
        return args[i + 1]
    }

    @MainActor
    static func run(store: CityStore) async {
        guard isActive, CommandLine.arguments.contains("-render-widgets") else { return }
        let snapshot = WidgetSnapshot(cities: store.places.map { .init(name: $0.name, timeZoneID: $0.timeZoneID) },
                                      use24h: store.use24h)
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("widgets")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // iPhone 16 Pro widget sizes, in points.
        let faces: [(String, WidgetFamily, CGSize)] = [
            ("small", .systemSmall, CGSize(width: 170, height: 170)),
            ("medium", .systemMedium, CGSize(width: 364, height: 170)),
            ("large", .systemLarge, CGSize(width: 364, height: 382)),
            ("lock-inline", .accessoryInline, CGSize(width: 234, height: 26)),
            ("lock-circular", .accessoryCircular, CGSize(width: 76, height: 76)),
            ("lock-rectangular", .accessoryRectangular, CGSize(width: 172, height: 76)),
        ]
        for (name, family, size) in faces {
            let view: AnyView
            switch family {
            case .accessoryInline, .accessoryCircular, .accessoryRectangular:
                view = AnyView(AccessoryClockView(snapshot: snapshot, date: store.now, family: family)
                    .foregroundStyle(.white)
                    .frame(width: size.width, height: size.height)
                    .background(family == .accessoryCircular ? Color.white.opacity(0.18) : .clear,
                                in: family == .accessoryCircular ? AnyShape(Circle()) : AnyShape(Rectangle()))
                    .background(Color.black))
            default:
                view = AnyView(WidgetClockView(snapshot: snapshot, date: store.now, family: family)
                    .frame(width: size.width, height: size.height)
                    .background(WidgetTone.bg)
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous)))
            }
            let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
            renderer.scale = 3
            if let data = renderer.uiImage?.pngData() {
                try? data.write(to: dir.appendingPathComponent("\(name).png"))
            }
        }
        try? "done".write(to: dir.appendingPathComponent("done.txt"), atomically: true, encoding: .utf8)
    }
}

/// Screenshot mode's "widgets" screen: the Home Screen and Lock Screen widgets, live, on one page
/// (for the App Store listing).
struct WidgetShowcase: View {
    @EnvironmentObject private var store: CityStore

    private var snapshot: WidgetSnapshot {
        WidgetSnapshot(cities: store.places.map { .init(name: $0.name, timeZoneID: $0.timeZoneID) }, use24h: store.use24h)
    }

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 8) {
                Text("Widgets for your Home Screen and Lock Screen")
                    .font(.title2.weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.cream)
                Text("Your cities, in the order you set.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 24)
            face(.systemLarge, CGSize(width: 364, height: 382))
            HStack(alignment: .top, spacing: 24) {
                face(.systemSmall, CGSize(width: 170, height: 170))
                VStack(alignment: .leading, spacing: 14) {
                    accessory(.accessoryInline, CGSize(width: 170, height: 26))
                    accessory(.accessoryRectangular, CGSize(width: 170, height: 72))
                    accessory(.accessoryCircular, CGSize(width: 72, height: 72))
                        .background(Color.white.opacity(0.18), in: Circle())
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
    }

    private func face(_ family: WidgetFamily, _ size: CGSize) -> some View {
        WidgetClockView(snapshot: snapshot, date: store.now, family: family)
            .frame(width: size.width, height: size.height)
            .background(WidgetTone.bg)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.border, lineWidth: 0.5))
    }

    private func accessory(_ family: WidgetFamily, _ size: CGSize) -> some View {
        AccessoryClockView(snapshot: snapshot, date: store.now, family: family)
            .foregroundStyle(.white)
            .frame(width: size.width, height: size.height, alignment: .leading)
    }
}
