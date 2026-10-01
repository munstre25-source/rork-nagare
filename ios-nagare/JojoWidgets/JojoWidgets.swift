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
    }
}

/// Home Screen + Lock Screen widget focused on streak, daily goal, and due cards.
struct JojoStreakWidget: Widget {
    let kind = "JojoStreakWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: JojoWidgetProvider()) { entry in
            JojoWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(red: 0.04, green: 0.04, blue: 0.04)
                }
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
    private let orange = Color(red: 1, green: 0.42, blue: 0)

    var body: some View {
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
                        .foregroundStyle(orange)
                    Spacer(minLength: 0)
                    Text("Jojo")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 0)
                Text(snapshot.headline)
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                Text(snapshot.headlineCaption)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text(snapshot.goalCaption)
                    .font(.caption2)
                    .foregroundStyle(snapshot.isGoalReached ? orange : .white.opacity(0.5))
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
                            .foregroundStyle(.white)
                    } icon: {
                        Image(systemName: "flame.fill").foregroundStyle(orange)
                    }
                    progressBar
                    Text(snapshot.goalCaption)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.65))
                    Spacer(minLength: 0)
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.stack.fill")
                            .foregroundStyle(orange)
                        Text(snapshot.dueCount > 0 ? "\(snapshot.dueCount) cards due" : "All caught up")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let surface = snapshot.teaserSurface {
                    VStack(spacing: 6) {
                        Text(surface)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        if let gloss = snapshot.teaserGloss {
                            Text(gloss)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.55))
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        Text(snapshot.dueCount > 0 ? "Review" : "Watch")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(orange)
                    }
                    .frame(width: 110)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 8)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(4)
        }
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(orange)
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
            updatedAt: .now
        )
    )
}
