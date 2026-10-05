import ActivityKit
import SwiftUI
import WidgetKit

/// The line being heard, in the Dynamic Island and on the lock screen.
struct ImmersionIslandWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ImmersionAttributes.self) { context in
            ImmersionLockScreen(state: context.state)
                .widgetURL(URL(string: "jojo://feed"))
        } dynamicIsland: { context in
            let paint = WidgetPaint(accent: context.state.accent, scheme: "dark")
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.surface)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(paint.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.minutesLeft == 0 ? "Done" : "\(context.state.minutesLeft)m")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(paint.accent)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        if !context.state.reading.isEmpty {
                            Text(context.state.reading)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(paint.reading)
                                .lineLimit(1)
                        }
                        if context.state.line != context.state.surface {
                            Text(context.state.line)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(paint.ink)
                                .lineLimit(2)
                        }
                        if !context.state.translation.isEmpty {
                            Text(context.state.translation)
                                .font(.caption)
                                .foregroundStyle(paint.muted)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Text(compactWord(context.state.surface))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(paint.accent)
                    .lineLimit(1)
            } compactTrailing: {
                Text(context.state.minutesLeft == 0 ? "✓" : "\(context.state.minutesLeft)m")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(paint.ink)
            } minimal: {
                Text(compactWord(String(context.state.surface.prefix(1))))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(paint.accent)
            }
            .widgetURL(URL(string: "jojo://feed"))
            .keylineTint(paint.accent)
        }
    }

    private func compactWord(_ text: String) -> String {
        String(text.prefix(4))
    }
}

private struct ImmersionLockScreen: View {
    let state: ImmersionAttributes.ContentState

    private var paint: WidgetPaint { WidgetPaint(accent: state.accent, scheme: "dark") }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Jojo")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(paint.accent)
                Spacer(minLength: 0)
                Text(state.minutesLeft == 0 ? "Goal done" : "\(state.minutesLeft) min left")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(paint.muted)
            }
            if !state.reading.isEmpty {
                Text(state.reading)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(paint.reading)
            }
            Text(state.line)
                .font(.title3.weight(.bold))
                .foregroundStyle(paint.ink)
                .lineLimit(2)
            if !state.translation.isEmpty {
                Text(state.translation)
                    .font(.subheadline)
                    .foregroundStyle(paint.muted)
                    .lineLimit(2)
            }
            Capsule()
                .fill(paint.ink.opacity(0.15))
                .frame(height: 4)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(paint.accent)
                            .frame(width: max(4, proxy.size.width * state.goalProgress))
                    }
                }
        }
        .padding(16)
        .activityBackgroundTint(paint.paper)
        .activitySystemActionForegroundColor(paint.accent)
    }
}
