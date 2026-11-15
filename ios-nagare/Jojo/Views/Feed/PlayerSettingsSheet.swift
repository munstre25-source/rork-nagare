import SwiftUI

/// Watch-time preferences that live on the device rather than in the learner profile.
enum PlayerPrefs {
    static let subtitlesHiddenKey = "jojo.subtitlesHidden"
    static let focusModeKey = "jojo.focusMode"
    static let jlptLevelKey = "jojo.jlptLevel"
    static let karaokeTextSizeKey = "jojo.karaokeTextSize"
    static let popupTextSizeKey = "jojo.popupTextSize"
    static let immersionKaraokeStyleKey = "jojo.immersionKaraokeStyle"
    static let immersionTextPaletteKey = "jojo.immersionTextPalette"

    /// Five steps from compact to large. Index 1 is the system default.
    static let sizes: [DynamicTypeSize] = [.medium, .large, .xLarge, .xxLarge, .xxxLarge]
    static let sizeLabels = ["S", "M", "L", "XL", "XXL"]

    static func typeSize(_ index: Double) -> DynamicTypeSize {
        sizes[min(max(0, Int(index.rounded())), sizes.count - 1)]
    }
}
nonisolated enum ImmersionKaraokeStyle: String, CaseIterable, Identifiable {
    case classic = "Classic"
    case amber = "Amber Contrast"

    var id: Self { self }
}

nonisolated enum ImmersionTextPalette: String, CaseIterable, Identifiable {
    case warmAmber = "Warm Amber"
    case sakuraPink = "Sakura Pink"
    case softCoral = "Soft Coral"
    case deepPlum = "Deep Plum"
    case forestTeal = "Forest Teal"
    case graphite = "Graphite"

    var id: Self { self }

    var hex: String {
        switch self {
        case .warmAmber: "#F4A340"
        case .sakuraPink: "#BE3F72"
        case .softCoral: "#E77E6A"
        case .deepPlum: "#72458E"
        case .forestTeal: "#26796F"
        case .graphite: "#343A43"
        }
    }

    var usesDarkInk: Bool { self == .warmAmber || self == .softCoral }
}

/// JLPT picker steps. The feed itself filters by the three reading bands.
nonisolated enum JLPTStep: String, CaseIterable, Identifiable, Sendable {
    case n5 = "N5", n4 = "N4", n3 = "N3", n2 = "N2", n1 = "N1"
    var id: String { rawValue }

    var readingLevel: ReadingLevel {
        switch self {
        case .n5, .n4: .beginner
        case .n3, .n2: .intermediate
        case .n1: .advanced
        }
    }

    var blurb: String {
        switch self {
        case .n5: "Greetings, simple sentences, slow speech."
        case .n4: "Everyday talk with basic grammar."
        case .n3: "Natural conversation at a calm pace."
        case .n2: "Dramas, interviews and fast speech."
        case .n1: "Anything — news, debate, slang."
        }
    }

    static func fallback(for level: ReadingLevel) -> JLPTStep {
        switch level {
        case .beginner: .n5
        case .intermediate: .n3
        case .advanced: .n1
        }
    }
}

/// The gear on the player: level, subtitle layers, text sizes, playback, and reporting a clip.
struct PlayerSettingsSheet: View {
    let clip: Clip
    var currentLine: Int = 0

    @Environment(AppModel.self) private var app
    @Environment(PlaybackCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PlayerPrefs.focusModeKey) private var focusMode = false
    @AppStorage(PlayerPrefs.jlptLevelKey) private var storedLevel = ""
    @AppStorage(PlayerPrefs.karaokeTextSizeKey) private var karaokeSize: Double = 1
    @AppStorage(PlayerPrefs.popupTextSizeKey) private var popupSize: Double = 1
    @AppStorage(PlayerPrefs.immersionKaraokeStyleKey) private var immersionStyle = ""
    @AppStorage(PlayerPrefs.immersionTextPaletteKey) private var immersionTextPalette = ImmersionTextPalette.warmAmber.rawValue

    @State private var pendingLevel: JLPTStep?
    @State private var correctionLine: Int?
    @State private var showsCorrection = false
    @State private var reportSent: String?

    private var level: JLPTStep {
        JLPTStep(rawValue: storedLevel) ?? JLPTStep.fallback(for: app.profile.readingLevel)
    }

    var body: some View {
        NavigationStack {
            Form {
                levelSection
                subtitlesSection
                Section("Immersion karaoke") {
                    Picker("Word style", selection: Binding(
                        get: { ImmersionKaraokeStyle(rawValue: immersionStyle) ?? .classic },
                        set: { immersionStyle = $0.rawValue }
                    )) {
                        ForEach(ImmersionKaraokeStyle.allCases) { style in
                            Text(style.rawValue).tag(style)
                        }
                    }
                }
                if clip.isPortraitVideo,
                   ImmersionKaraokeStyle(rawValue: immersionStyle) == .amber {
                    Section("Portrait immersion word color") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            ForEach(ImmersionTextPalette.allCases) { palette in
                                Button {
                                    Haptics.selection()
                                    immersionTextPalette = palette.rawValue
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(palette.rawValue)
                                            .font(.caption.weight(.semibold))
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.8)
                                        HStack(spacing: 4) {
                                            ForEach(["魚", "を", "ボトル"], id: \.self) { sample in
                                                Text(sample)
                                                    .font(.system(size: sample == "ボトル" ? 11 : 13, weight: .bold))
                                                    .foregroundStyle(palette.usesDarkInk ? Color(hex: "#191919") : .white)
                                                    .lineLimit(1)
                                                    .minimumScaleFactor(0.65)
                                                    .frame(maxWidth: .infinity, minHeight: 28)
                                                    .background(Color(hex: palette.hex), in: RoundedRectangle(cornerRadius: 6))
                                            }
                                        }
                                        HStack {
                                            Text(palette.hex)
                                                .font(.caption2.monospaced())
                                                .foregroundStyle(.secondary)
                                            Spacer(minLength: 0)
                                            if immersionTextPalette == palette.rawValue {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.caption)
                                                    .foregroundStyle(Color.designOrange)
                                            }
                                        }
                                    }
                                    .padding(10)
                                    .background(Color.fieldFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .strokeBorder(
                                                immersionTextPalette == palette.rawValue ? Color.designOrange : Color.clear,
                                                lineWidth: 1.5
                                            )
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("\(palette.rawValue), \(palette.hex)")
                                .accessibilityAddTraits(immersionTextPalette == palette.rawValue ? .isSelected : [])
                            }
                        }
                    }
                }
                sizeSection
                playbackSection
                reportSection
            }
            .navigationTitle("Player settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert(
                "Switch to \(pendingLevel?.rawValue ?? "")?",
                isPresented: Binding(get: { pendingLevel != nil }, set: { if !$0 { pendingLevel = nil } })
            ) {
                Button("Cancel", role: .cancel) { pendingLevel = nil }
                Button("Switch") {
                    if let pendingLevel { apply(pendingLevel) }
                    pendingLevel = nil
                }
            } message: {
                Text("Your For You feed will reload with clips picked for this level.")
            }
            .alert("Thanks — report sent", isPresented: Binding(get: { reportSent != nil }, set: { if !$0 { reportSent = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(reportSent ?? "")
            }
            .sheet(isPresented: $showsCorrection) {
                TranscriptCorrectionSheet(clip: clip, lineIndex: correctionLine ?? currentLine)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: Sections

    private var levelSection: some View {
        Section {
            HStack(spacing: 6) {
                ForEach(JLPTStep.allCases) { step in
                    Button {
                        Haptics.selection()
                        guard step != level else { return }
                        pendingLevel = step
                    } label: {
                        Text(step.rawValue)
                            .font(.subheadline.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .foregroundStyle(step == level ? Color.white : Color.primary)
                            .background(
                                step == level ? Color.sakuraButton : Color.fieldFill,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(step == level ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        } header: {
            Text("Japanese level")
        } footer: {
            Text(level.blurb)
        }
    }

    private var subtitlesSection: some View {
        Section {
            Toggle(isOn: Binding(get: { app.profile.furiganaMode.showsAny }, set: { app.setShowFurigana($0) })) {
                Label("Furigana", systemImage: "textformat.size.smaller")
            }
            Toggle(isOn: Binding(get: { app.profile.showRomaji }, set: { app.setShowRomaji($0) })) {
                Label("Romaji", systemImage: "character.textbox")
            }
            Picker(selection: Binding(
                get: { app.profile.subtitleDisplay.english },
                set: { app.setEnglishVisibility($0) }
            )) {
                ForEach(EnglishVisibility.allCases) { option in
                    Text(option.title).tag(option)
                }
            } label: {
                Label("Translation", systemImage: "globe")
            }
            Toggle(isOn: Binding(get: { app.profile.tapWordsEnabled }, set: { app.setTapWordsEnabled($0) })) {
                Label("Tap words for meaning", systemImage: "hand.tap")
            }
        } header: {
            Text("Subtitles")
        } footer: {
            Text("Use the CC button on the player to show or hide subtitles. Spoken words light up as they're said.")
        }
    }

    private var sizeSection: some View {
        Section("Text size") {
            sizeRow("Subtitles", systemImage: "textformat", value: $karaokeSize)
            sizeRow("Dictionary card", systemImage: "rectangle.on.rectangle", value: $popupSize)
        }
    }

    private func sizeRow(_ title: String, systemImage: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                Text(PlayerPrefs.sizeLabels[min(max(0, Int(value.wrappedValue.rounded())), 4)])
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Slider(value: value, in: 0...4, step: 1) {
                Text(title)
            } minimumValueLabel: {
                Image(systemName: "textformat.size.smaller").foregroundStyle(.secondary)
            } maximumValueLabel: {
                Image(systemName: "textformat.size.larger").foregroundStyle(.secondary)
            }
            .tint(Color.sakuraButton)
            .onChange(of: value.wrappedValue) { _, _ in Haptics.selection() }
        }
    }

    private var playbackSection: some View {
        Section {
            Picker(selection: Binding(
                get: { coordinator.preferredRate },
                set: { target in
                    var guardCount = 0
                    while coordinator.preferredRate != target && guardCount < 3 {
                        coordinator.cycleRate()
                        guardCount += 1
                    }
                }
            )) {
                Text("0.5x").tag(0.5)
                Text("0.75x").tag(0.75)
                Text("1x").tag(1.0)
            } label: {
                Label("Speed", systemImage: "gauge.with.dots.needle.33percent")
            }
            Toggle(isOn: Binding(
                get: { coordinator.player?.loopRange != nil },
                set: { _ in
                    if coordinator.player == nil { coordinator.activate(clip) }
                    coordinator.player?.toggleLoopCurrentLine()
                }
            )) {
                Label("Loop current sentence", systemImage: "repeat.1")
            }
            Toggle(isOn: Binding(get: { app.profile.autoAdvanceEnabled }, set: { app.setAutoAdvanceEnabled($0) })) {
                Label("Play next clip automatically", systemImage: "forward.end")
            }
            Toggle(isOn: $focusMode) {
                Label("Focus mode", systemImage: "moon.circle")
            }
        } header: {
            Text("Playback")
        } footer: {
            Text("Focus mode hides the goal strip and celebration pop-ups while you watch.")
        }
    }

    private var reportSection: some View {
        Section("Something wrong?") {
            Button {
                correctionLine = currentLine
                showsCorrection = true
            } label: {
                Label("Incorrect transcript", systemImage: "text.badge.xmark")
            }
            Button {
                correctionLine = currentLine
                showsCorrection = true
            } label: {
                Label("Bad translation", systemImage: "globe.badge.chevron.backward")
            }
            Button {
                Task { await quickReport("Bad clip — audio, video or content problem") }
            } label: {
                Label("Bad clip", systemImage: "hand.thumbsdown")
            }
            Button {
                Task { await quickReport("Unavailable on YouTube") }
            } label: {
                Label("Unavailable on YouTube", systemImage: "play.slash")
            }
        }
    }

    // MARK: Actions

    private func apply(_ step: JLPTStep) {
        storedLevel = step.rawValue
        if app.profile.readingLevel != step.readingLevel {
            app.setReadingLevel(step.readingLevel)
        }
        Haptics.success()
        track("player_level_changed", props: ["level": step.rawValue])
    }

    @MainActor
    private func quickReport(_ issue: String) async {
        let message = [
            "Clip report: \(issue)",
            "Clip ID: \(clip.id)",
            "YouTube video ID: \(clip.videoId)",
            "Clip title: \(String(clip.title.prefix(140)))",
        ].joined(separator: "\n")
        let sent = await InsightsService.shared.submitFeedback(
            enjoyed: nil,
            category: "content",
            message: message,
            appUserId: app.purchases.appUserId,
            source: "manual"
        )
        track("clip_report_submitted", props: ["clip": clip.id, "issue": issue])
        reportSent = sent
            ? "We'll take a look at this clip."
            : "Couldn't reach the server. We'll keep improving clips either way."
    }
}

/// Gear button used on Shorts and in the landscape action row.
struct PlayerSettingsButton: View {
    let clip: Clip
    let player: (any ClipPlayer)?
    var tint: Color = .secondary
    var size: CGFloat = 15
    var width: CGFloat = 30
    var onPicture: Bool = false
    var onPresentationChange: (Bool) -> Void = { _ in }

    @Environment(PlaybackCoordinator.self) private var coordinator
    @State private var presented = false

    var body: some View {
        Button {
            Haptics.selection()
            presented = true
        } label: {
            Image(systemName: "gearshape")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: width, height: 44)
                .contentShape(Rectangle())
                .modifier(VideoControlSurface(onPicture: onPicture))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Player settings")
        .onChange(of: presented) { _, shown in
            onPresentationChange(shown)
            if shown { coordinator.pauseForPopup() } else { coordinator.resumeAfterPopupIfNeeded() }
        }
        .sheet(isPresented: $presented) {
            PlayerSettingsSheet(clip: clip, currentLine: player?.currentLineIndex ?? 0)
        }
    }
}

/// CC: removes every subtitle layer so only the video shows.
struct SubtitlesToggleButton: View {
    var tint: Color = .secondary
    var activeTint: Color = .designOrange
    var size: CGFloat = 15
    var width: CGFloat = 30
    var onPicture: Bool = false

    @AppStorage(PlayerPrefs.subtitlesHiddenKey) private var subtitlesHidden = false

    var body: some View {
        Button {
            Haptics.selection()
            withAnimation(.snappy) { subtitlesHidden.toggle() }
        } label: {
            Image(systemName: subtitlesHidden ? "captions.bubble" : "captions.bubble.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(subtitlesHidden ? tint : activeTint)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: width, height: 44)
                .contentShape(Rectangle())
                .modifier(VideoControlSurface(onPicture: onPicture))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(subtitlesHidden ? "Show subtitles" : "Hide subtitles")
        .accessibilityValue(subtitlesHidden ? "Off" : "On")
    }
}
