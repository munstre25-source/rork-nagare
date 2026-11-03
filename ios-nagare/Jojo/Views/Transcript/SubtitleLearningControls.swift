import SwiftUI

/// A one-time invitation in the karaoke area, plus a one-tap furigana chip.
/// Regular controls live behind the captions button.
struct SubtitleLearningControls: View {
    let isActive: Bool

    @Environment(AppModel.self) private var app
    @State private var showsSettings = false

    private var showsSetup: Bool {
        isActive && app.profile.onboardingCompleted
            && GuidanceCenter.shared.state.isTourFinished
            && !app.profile.subtitleSetupCompleted
    }

    var body: some View {
        HStack(spacing: 8) {
            if showsSetup {
                Button {
                    Haptics.selection()
                    showsSettings = true
                } label: {
                    Label("Choose your subtitle help", systemImage: "slider.horizontal.3")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .frame(minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Opens learning modes and reading assistance")

                Spacer(minLength: 0)

                Button {
                    Haptics.selection()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        app.completeSubtitleSetup()
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Keep my subtitle settings")
                .accessibilityHint("Dismiss setup. Subtitle help is always available in Profile.")
            } else if isActive {
                Spacer(minLength: 0)
                FuriganaModeChip()
            }
        }
        .sheet(isPresented: $showsSettings, onDismiss: {
            app.completeSubtitleSetup()
        }) {
            SubtitleLearningSettingsSheet()
        }
    }
}

/// Cycles furigana On → Unknown only → Off without leaving the karaoke panel.
struct FuriganaModeChip: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Button {
            Haptics.selection()
            withAnimation(.easeInOut(duration: 0.15)) {
                app.cycleFuriganaMode()
            }
        } label: {
            Text(app.profile.furiganaMode.shortLabel)
                .font(JojoFont.jp(14, bold: true, relativeTo: .caption))
                .foregroundStyle(app.profile.furiganaMode == .off ? .secondary : Color.accentColor)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Furigana")
        .accessibilityValue(app.profile.furiganaMode.title)
        .accessibilityHint("Cycles furigana on, unknown words only, or off")
    }
}

/// Shared by the compact playback button and Profile. Changes reuse the saved display preferences.
struct SubtitleLearningSettingsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    private var display: SubtitleDisplaySettings { app.profile.subtitleDisplay }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(LearningMode.allCases) { mode in
                        modeRow(mode)
                    }
                } header: {
                    Text("Learning mode")
                } footer: {
                    Text("Start with a mode, then adjust the help below. You can change this anytime in Profile → Subtitles & reading.")
                }

                Section("Reading assistance") {
                    Picker("Furigana above Japanese", selection: Binding(
                        get: { app.profile.furiganaMode },
                        set: { app.setFuriganaMode($0) }
                    )) {
                        ForEach(FuriganaMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    Toggle("Romaji under words", isOn: Binding(
                        get: { app.profile.showRomaji },
                        set: { app.setShowRomaji($0) }
                    ))
                    Picker("English", selection: Binding(
                        get: { display.english },
                        set: { app.setEnglishVisibility($0) }
                    )) {
                        Text("Always visible").tag(EnglishVisibility.shown)
                        Text("Tap to reveal").tag(EnglishVisibility.onTap)
                        Text("Hidden").tag(EnglishVisibility.hidden)
                    }
                    Toggle("Tap words to look up", isOn: Binding(
                        get: { app.profile.tapWordsEnabled },
                        set: { app.setTapWordsEnabled($0) }
                    ))
                }

                Section {
                    Picker("Subtitle language", selection: Binding(
                        get: { app.profile.subtitles },
                        set: { app.setSubtitleMode($0) }
                    )) {
                        ForEach(SubtitleMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                } footer: {
                    Text("Your choices are saved automatically for every clip.")
                }
            }
            .navigationTitle("Subtitle help")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func modeRow(_ mode: LearningMode) -> some View {
        let selected = display.learningMode == mode
        return Button {
            Haptics.selection()
            app.setLearningMode(mode)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: mode.symbol)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(mode.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(summary(for: mode))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 4)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func summary(for mode: LearningMode) -> String {
        switch mode {
        case .beginner: "Furigana, romaji and English visible."
        case .guided: "Furigana, with English when you tap."
        case .advanced: "Japanese only. Tap words for help."
        }
    }
}
