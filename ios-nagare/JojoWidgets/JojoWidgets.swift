import WidgetKit
import SwiftUI

/// Timeline entry backed by the App Group retention snapshot.
struct JojoWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct JojoWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> JojoWidgetEntry {
        JojoWidgetEntry(
            date: Date(),
            snapshot: WidgetSnapshot(
                streak: 4,
                dailyGoalMinutes: 10,
                minutesWatchedToday: 3,
                dueCount: 8,
                totalWords: 36,
                teaserSurface: "美味しい",
                teaserGloss: "delicious; tasty",
                teaserReading: "おいしい",
                accent: "sakura",
                scheme: "dark",
                updatedAt: Date()
            )
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (JojoWidgetEntry) -> Void) {
        completion(JojoWidgetEntry(date: Date(), snapshot: WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<JojoWidgetEntry>) -> Void) {
        let entry = JojoWidgetEntry(date: Date(), snapshot: WidgetSnapshot.load())
        // Refresh periodically so "minutes left" / due counts stay honest between app opens.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

@main
struct JojoWidgets: WidgetBundle {
    var body: some Widget {
        JojoStreakWidget()
        ImmersionIslandWidget()
    }
}

/// Home Screen + Lock Screen widget focused on streak, daily goal, and due cards.
struct JojoStreakWidget: Widget {
    let kind = "JojoStreakWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: JojoWidgetProvider()) { entry in
            JojoWidgetView(entry: entry)
        }
        .configurationDisplayName("Jojo Progress")
        .description("Streak, daily goal, and cards due — tap to keep your flow.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .accessoryCircular,
            .accessoryRectangular,
        ])
    }
}

struct JojoWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: JojoWidgetEntry

    private var snapshot: WidgetSnapshot { entry.snapshot }
    private var paint: WidgetPaint { WidgetPaint(accent: snapshot.accent, scheme: snapshot.scheme) }

    var body: some View {
        content
            .containerBackground(for: .widget) {
                switch family {
                case .accessoryCircular, .accessoryRectangular:
                    AccessoryWidgetBackground()
                default:
                    paint.paper
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .systemSmall:
            small
        case .systemMedium:
            medium
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        default:
            small
        }
    }

    private var small: some View {
        Link(destination: snapshot.preferredDeepLink) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: snapshot.dueCount > 0 ? "rectangle.stack.fill" : "flame.fill")
                        .foregroundStyle(paint.accent)
                    Spacer(minLength: 0)
                    Text("Jojo")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(paint.muted)
                }
                Spacer(minLength: 0)
                Text(snapshot.headline)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(paint.ink)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                Text(snapshot.headlineCaption)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(paint.ink.opacity(0.72))
                Text(snapshot.goalCaption)
                    .font(.caption2)
                    .foregroundStyle(snapshot.isGoalReached ? paint.accent : paint.muted)
            }
            .padding(4)
        }
    }

    private var medium: some View {
        Link(destination: snapshot.preferredDeepLink) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text("\(snapshot.streak)-day streak")
                            .font(.headline)
                            .foregroundStyle(paint.ink)
                    } icon: {
                        Image(systemName: "flame.fill").foregroundStyle(paint.accent)
                    }
                    progressBar
                    Text(snapshot.goalCaption)
                        .font(.caption)
                        .foregroundStyle(paint.muted)
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.stack.fill")
                            .foregroundStyle(paint.accent)
                        Text(snapshot.dueCount > 0 ? "\(snapshot.dueCount) cards due" : "All caught up")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(paint.ink)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let surface = snapshot.teaserSurface {
                    VStack(spacing: 4) {
                        if let reading = snapshot.teaserReading {
                            Text(reading)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(paint.reading)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        Text(surface)
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(paint.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        if let gloss = snapshot.teaserGloss {
                            Text(gloss)
                                .font(.caption2)
                                .foregroundStyle(paint.muted)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        Text(snapshot.dueCount > 0 ? "Review" : "Watch")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(paint.accent)
                    }
                    .frame(width: 110)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 8)
                    .background(paint.chip, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(4)
        }
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(paint.ink.opacity(0.12))
                Capsule()
                    .fill(paint.accent)
                    .frame(width: max(6, proxy.size.width * snapshot.goalProgress))
            }
        }
        .frame(height: 6)
    }

    private var circular: some View {
        Link(destination: snapshot.preferredDeepLink) {
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 1) {
                    Image(systemName: snapshot.dueCount > 0 ? "rectangle.stack.fill" : "flame.fill")
                        .font(.caption2)
                    Text(snapshot.dueCount > 0 ? "\(snapshot.dueCount)" : "\(snapshot.streak)")
                        .font(.headline.weight(.bold))
                        .minimumScaleFactor(0.6)
                }
            }
        }
    }

    private var rectangular: some View {
        Link(destination: snapshot.preferredDeepLink) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Jojo · \(snapshot.streak)-day")
                    .font(.headline)
                Text(snapshot.dueCount > 0 ? "\(snapshot.dueCount) cards due" : snapshot.goalCaption)
                    .font(.caption)
            }
        }
    }
}

/// The six looks from Profile, painted without the app target.
struct WidgetPaint {
    var accentName: String
    var schemeName: String

    init(accent: String, scheme: String) {
        accentName = accent
        schemeName = scheme
    }

    var dark: Bool { schemeName != "light" }

    var paper: Color {
        guard !dark else { return Color(hex: 0x0B0816) }
        switch accentName {
        case "sakura": return Color(hex: 0xFFF5F8)
        case "plum": return Color(hex: 0xF6F1FF)
        default: return Color(hex: 0xFFF8F3)
        }
    }

    var accent: Color {
        switch (accentName, dark) {
        case ("sakura", false): return Color(hex: 0xFF4D8D)
        case ("sakura", true): return Color(hex: 0xFF7EB8)
        case ("plum", false): return Color(hex: 0x8B5CF6)
        case ("plum", true): return Color(hex: 0xC4B5FD)
        case (_, false): return Color(hex: 0xFF7A00)
        default: return Color(hex: 0xFFB020)
        }
    }

    var ink: Color {
        guard !dark else { return .white }
        switch accentName {
        case "sakura": return Color(hex: 0x1A1020)
        case "plum": return Color(hex: 0x1A1024)
        default: return Color(hex: 0x1C1208)
        }
    }

    var reading: Color {
        switch (accentName, dark) {
        case ("sakura", false): return Color(hex: 0xFF4D8D)
        case ("sakura", true): return Color(hex: 0xFFB7D8)
        case ("plum", false): return Color(hex: 0x8B5CF6)
        case ("plum", true): return Color(hex: 0xDDD6FE)
        case (_, false): return Color(hex: 0xFF7A00)
        default: return Color(hex: 0xFFD7A1)
        }
    }

    var muted: Color { ink.opacity(dark ? 0.55 : 0.5) }

    var chip: Color { dark ? Color.white.opacity(0.08) : accent.opacity(0.12) }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

#Preview(as: .systemSmall) {
    JojoStreakWidget()
} timeline: {
    JojoWidgetEntry(
        date: .now,
        snapshot: WidgetSnapshot(
            streak: 4,
            dailyGoalMinutes: 10,
            minutesWatchedToday: 3,
            dueCount: 8,
            totalWords: 36,
            teaserSurface: "美味しい",
            teaserGloss: "delicious",
            teaserReading: "おいしい",
            accent: "sakura",
            scheme: "dark",
            updatedAt: .now
        )
    )
}
