import SwiftUI

/// Changes only local presentation. The clip, playhead, and enriched lines stay intact.
struct SubtitleLearningControls: View {
    @Environment(AppModel.self) private var app
    @ScaledMetric(relativeTo: .caption) private var controlHeight: CGFloat = 56

    private var display: SubtitleDisplaySettings { app.profile.subtitleDisplay }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Menu {
                    ForEach(LearningMode.allCases) { mode in
                        Button {
                            app.setLearningMode(mode)
                            Haptics.selection()
                        } label: {
                            Label(mode.title, systemImage: display.learningMode == mode ? "checkmark" : mode.symbol)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: display.learningMode?.symbol ?? "slider.horizontal.3")
                        Text(display.learningMode?.title ?? "Custom")
                            .lineLimit(2)
                        Image(systemName: "chevron.down").font(.caption2)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 10)
                    .frame(minHeight: controlHeight)
                    .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1)
                    }
                }
                .accessibilityLabel("Learning mode, \(display.learningMode?.title ?? "Custom")")
                .accessibilityHint("Choose Beginner, Guided Immersion, or Full Immersion")

                aid("Furigana", symbol: "textformat.ja", value: display.furigana ? "On" : "Off",
                    active: display.furigana) { app.setShowFurigana(!display.furigana) }
                aid("Romaji", symbol: "textformat", value: display.romaji ? "On" : "Off",
                    active: display.romaji) { app.setShowRomaji(!display.romaji) }
                aid("English", symbol: "captions.bubble", value: display.english.title,
                    active: display.english != .hidden) { app.setEnglishVisibility(display.english.next) }
                aid("Tap Words", symbol: "hand.tap", value: display.tapWords ? "On" : "Off",
                    active: display.tapWords) { app.setTapWordsEnabled(!display.tapWords) }
            }
            .padding(.vertical, 2)
        }
        .frame(height: controlHeight + 4)
        .scrollBounceBehavior(.basedOnSize)
    }

    private func aid(_ title: String, symbol: String, value: String, active: Bool,
                     action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            VStack(spacing: 2) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                Text(title).font(.caption2.weight(.medium))
                Text(value).font(.caption2.weight(.semibold))
                    .foregroundStyle(active ? Color.accentColor : Color.secondary)
            }
            .foregroundStyle(active ? Color.primary : Color.secondary)
            .frame(minWidth: 58, minHeight: controlHeight)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(value)")
        .accessibilityHint(title == "English" ? "Cycles through On, Tap to reveal, and Hidden" : "Toggle \(title)")
    }
}
