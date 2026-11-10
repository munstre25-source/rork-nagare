import SwiftUI
import SwiftData
import StoreKit

/// Every app preference, grouped. Opened from the gear on Profile so Profile stays about progress.
struct SettingsView: View {
    var onGiveFeedback: (() -> Void)? = nil
    var onAcquisitionSurvey: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                LearningSettingsCard()
                SettingsSectionsCard(onGiveFeedback: onGiveFeedback, onAcquisitionSurvey: onAcquisitionSurvey)
                Text("Jojo 流れ · Scroll, Listen, Flow into Japanese.")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, Spacing.s)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.hidden)
        .background(Color.canvas.ignoresSafeArea())
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
    }
}

/// Level, display and study-window choices that used to be scattered across sheets.
struct LearningSettingsCard: View {
    @Environment(AppModel.self) private var app
    @Query(sort: \SavedWord.addedAt, order: .reverse) private var words: [SavedWord]
    @AppStorage(PlayerPrefs.subtitlesHiddenKey) private var subtitlesHidden = false
    @AppStorage(PlayerPrefs.focusModeKey) private var focusMode = false
    @AppStorage(PlayerPrefs.jlptLevelKey) private var storedLevel = ""
    @AppStorage(PlayerPrefs.karaokeTextSizeKey) private var karaokeSize: Double = 1
    @AppStorage(PlayerPrefs.popupTextSizeKey) private var popupSize: Double = 1
    @AppStorage("jojo.reminderHour") private var reminderHour = 19
    @State private var pendingLevel: JLPTStep?
    @State private var tutorialReset = false
    @State private var showKnownWordImport = false

    private var level: JLPTStep {
        JLPTStep(rawValue: storedLevel) ?? JLPTStep.fallback(for: app.profile.readingLevel)
    }

    private enum StudyWindow: Int, CaseIterable, Identifiable {
        case morning = 8, afternoon = 13, evening = 19, night = 22
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .morning: "Morning"
            case .afternoon: "Afternoon"
            case .evening: "Evening"
            case .night: "Night"
            }
        }
        var symbol: String {
            switch self {
            case .morning: "sunrise"
            case .afternoon: "sun.max"
            case .evening: "sunset"
            case .night: "moon.stars"
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header("Learning")
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: Spacing.m) {
                    Image(systemName: "graduationcap")
                        .foregroundStyle(Color.designOrangeDeep)
                        .frame(width: 28)
                    Text("Japanese level")
                    Spacer()
                    Text(level.rawValue).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    ForEach(JLPTStep.allCases) { step in
                        Button {
                            Haptics.selection()
                            if step != level { pendingLevel = step }
                        } label: {
                            Text(step.rawValue)
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .foregroundStyle(step == level ? Color.white : Color.primary)
                                .background(step == level ? Color.sakuraButton : Color.fieldFill,
                                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(step == level ? .isSelected : [])
                    }
                }
                Text(level.blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, 12)
            divider

            header("Display")
            toggle("captions.bubble", "Subtitles while watching",
                   Binding(get: { !subtitlesHidden }, set: { subtitlesHidden = !$0 }))
            divider
            toggle("moon.circle", "Focus mode", $focusMode)
            Text("Hides the goal strip and celebration pop-ups in the feed.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 52 + 4)
                .padding(.trailing, Spacing.l)
                .padding(.bottom, 8)
            divider
            sizeRow("textformat", "Subtitle size", $karaokeSize)
            divider
            sizeRow("rectangle.on.rectangle", "Dictionary card size", $popupSize)
            divider

            header("Notifications")
            toggle("bell", "Study & review reminders", Binding(
                get: { app.profile.remindersEnabled },
                set: { value in Task { await app.setReminders(value) } }
            ))
            if app.profile.remindersEnabled {
                divider
                VStack(alignment: .leading, spacing: 8) {
                    Text("Study window")
                        .font(.subheadline)
                    HStack(spacing: 6) {
                        ForEach(StudyWindow.allCases) { window in
                            let selected = reminderHour == window.rawValue
                            Button {
                                Haptics.selection()
                                reminderHour = window.rawValue
                                app.refreshAllReminders()
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: window.symbol)
                                        .font(.system(size: 15, weight: .semibold))
                                    Text(window.title)
                                        .font(.caption2.weight(.bold))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.8)
                                }
                                .frame(maxWidth: .infinity, minHeight: 54)
                                .foregroundStyle(selected ? Color.white : Color.primary)
                                .background(selected ? Color.sakuraButton : Color.fieldFill,
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }
                .padding(.leading, 52)
                .padding(.trailing, Spacing.l)
                .padding(.vertical, 10)
            }
            divider

            header("Backup & export")
            Button {
                showKnownWordImport = true
            } label: {
                rowLabel("square.and.arrow.down", "Import known words", value: nil)
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showKnownWordImport) { KnownWordImportSheet() }
            divider
            ShareLink(item: exportCSV, preview: SharePreview("Jojo words.csv")) {
                rowLabel("square.and.arrow.up", "Export words (CSV)", value: "\(words.count)")
            }
            .disabled(words.isEmpty)
            divider
            ShareLink(item: exportAnki, preview: SharePreview("Jojo words for Anki.txt")) {
                rowLabel("rectangle.stack", "Export for Anki", value: "TSV")
            }
            .disabled(words.isEmpty)
            divider
            Button {
                Haptics.selection()
                GuidanceCenter.shared.resetAll()
                tutorialReset = true
            } label: {
                rowLabel("arrow.counterclockwise", "Reset tutorial", value: tutorialReset ? "Done" : nil)
            }
            .buttonStyle(.plain)
        }
        .cardStyle()
        .alert(
            "Switch to \(pendingLevel?.rawValue ?? "")?",
            isPresented: Binding(get: { pendingLevel != nil }, set: { if !$0 { pendingLevel = nil } })
        ) {
            Button("Cancel", role: .cancel) { pendingLevel = nil }
            Button("Switch") {
                if let step = pendingLevel {
                    storedLevel = step.rawValue
                    if app.profile.readingLevel != step.readingLevel { app.setReadingLevel(step.readingLevel) }
                    Haptics.success()
                }
                pendingLevel = nil
            }
        } message: {
            Text("Your For You feed will reload with clips picked for this level.")
        }
    }

    private var divider: some View { Divider().padding(.leading, 52) }

    private func header(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.designOrange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.l)
            .padding(.top, Spacing.m)
            .padding(.bottom, 4)
    }

    private func toggle(_ symbol: String, _ title: String, _ isOn: Binding<Bool>) -> some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: symbol)
                .foregroundStyle(Color.designOrangeDeep)
                .frame(width: 28)
            Toggle(title, isOn: isOn).tint(Color.designOrange)
        }
        .padding(.horizontal, Spacing.l)
        .frame(minHeight: 54)
    }

    private func rowLabel(_ symbol: String, _ title: String, value: String?) -> some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: symbol)
                .foregroundStyle(Color.designOrangeDeep)
                .frame(width: 28)
            Text(title).foregroundStyle(.primary)
            Spacer()
            if let value { Text(value).foregroundStyle(.secondary) }
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, Spacing.l)
        .frame(minHeight: 54)
        .contentShape(Rectangle())
    }

    private func sizeRow(_ symbol: String, _ title: String, _ value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: Spacing.m) {
                Image(systemName: symbol)
                    .foregroundStyle(Color.designOrangeDeep)
                    .frame(width: 28)
                Text(title)
                Spacer()
                Text(PlayerPrefs.sizeLabels[min(max(0, Int(value.wrappedValue.rounded())), 4)])
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: 0...4, step: 1)
                .tint(Color.sakuraButton)
                .padding(.leading, 28 + Spacing.m)
                .accessibilityLabel(title)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, 10)
    }

    private static func field(_ text: String) -> String {
        let cleaned = text.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(cleaned)\""
    }

    private var exportCSV: String {
        var rows = ["word,reading,romaji,meaning,part_of_speech,jlpt,status,times_seen,sentence,added"]
        let formatter = ISO8601DateFormatter()
        for word in words {
            rows.append([
                word.surface, word.readings.first ?? "", word.romaji,
                word.definitions.prefix(3).joined(separator: "; "), word.pos, word.jlpt ?? "",
                word.state.title, "\(word.occurrenceCount)", word.contextSentence,
                formatter.string(from: word.addedAt),
            ].map(Self.field).joined(separator: ","))
        }
        return rows.joined(separator: "\n")
    }

    /// Front: word. Back: reading, meaning and the real sentence. Tab-separated for Anki import.
    private var exportAnki: String {
        words.map { word in
            let back = [word.readings.first ?? "", word.definitions.prefix(3).joined(separator: "; "), word.contextSentence]
                .filter { !$0.isEmpty }
                .joined(separator: "<br>")
            return "\(word.surface)\t\(back.replacingOccurrences(of: "\t", with: " "))"
        }
        .joined(separator: "\n")
    }
}

private struct KnownWordImportSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var result: String?

    private var headwords: [String] {
        var seen: Set<String> = []
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            let headword = line.prefix(while: { $0 != "\t" })
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .precomposedStringWithCompatibilityMapping
            return headword.isEmpty || !seen.insert(headword).inserted ? nil : headword
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 160)
                        .accessibilityLabel("Japanese headwords")
                } header: {
                    Text("Word list")
                } footer: {
                    Text("Paste up to 500 Japanese headwords, one per line. For tab-separated lists, put the Japanese word first.")
                }
                if let result { Text(result).font(.subheadline) }
                Button("Import as known") {
                    do {
                        let counts = try app.importKnownWords(headwords)
                        result = "Added \(counts.added) · Marked known \(counts.updated) · No dictionary match \(counts.unmatched)"
                    } catch {
                        result = "Couldn’t save the import. Please try again."
                    }
                }
                .disabled(headwords.isEmpty || headwords.count > 500)
            }
            .navigationTitle("Import known words")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// Appearance, playback, account and legal rows.
struct SettingsSectionsCard: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openURL) private var openURL
    @AppStorage(PlaybackDefaults.quickChecksKey) private var quickChecksEnabled = true
    @State private var showGoalPicker: Bool = false
    @State private var showManageSubs: Bool = false
    @State private var showCustomerCenter: Bool = false
    @State private var restoreMessage: String?
    @State private var confirmDeleteAccount: Bool = false
    @State private var showHelp: Bool = false
    @State private var showSubtitleHelp = false
    #if DEBUG
    @State private var confirmReset: Bool = false
    @State private var marketingScript: MarketingScript?
    #endif
    var onGiveFeedback: (() -> Void)? = nil
    var onAcquisitionSurvey: (() -> Void)? = nil

    private var planText: String? {
        guard let status = app.purchases.status else { return nil }
        let plan = status.productId.contains("year") ? "Yearly" : "Monthly"
        return status.isInTrial ? "\(plan) · Trial" : plan
    }

    var body: some View {
        VStack(spacing: 0) {
            settingsHeader("Appearance")
                .id("appearance")
            Menu {
                ForEach(AccentTheme.allCases) { theme in
                    Button(theme.title) { app.setTheme(theme) }
                }
            } label: {
                SettingsRowLabel(symbol: "paintpalette", title: "Theme", value: app.profile.theme.title)
            }
            Divider().padding(.leading, 52)
            Menu {
                ForEach(JojoScheme.allCases) { scheme in
                    Button(scheme.title) { app.setScheme(scheme) }
                }
            } label: {
                SettingsRowLabel(symbol: "circle.lefthalf.filled", title: "Appearance", value: app.profile.scheme.title)
            }
            Divider().padding(.leading, 52)
            GlowLevelRow()
            Divider().padding(.leading, 52)

            settingsHeader("Subtitles & reading")
            SettingsRow(symbol: "captions.bubble", title: "Subtitle help",
                        value: app.profile.subtitleDisplay.learningMode?.title ?? "Custom") {
                showSubtitleHelp = true
            }
            Divider().padding(.leading, 52)
            Menu {
                ForEach(DictionaryMode.allCases) { mode in
                    Button(mode.title) { app.setDictionaryMode(mode) }
                }
            } label: {
                SettingsRowLabel(symbol: "character.book.closed.ja", title: "Dictionary", value: app.profile.dictionary.title)
            }
            Divider().padding(.leading, 52)

            settingsHeader("Study focus")
            Menu {
                ForEach(VocabularyProgress.goalOptions, id: \.self) { goal in
                    Button("\(goal) words a day") { app.setDailyVocabularyGoal(goal) }
                }
            } label: {
                SettingsRowLabel(symbol: "chart.bar.fill", title: "Daily vocabulary target",
                                 value: "\(app.profile.dailyVocabularyGoal) words")
            }
            Divider().padding(.leading, 52)
            settingsToggle(symbol: "lock.open", title: "Match For You to my level",
                           isOn: Binding(get: { app.profile.gateContentByLevel }, set: { app.setGateContentByLevel($0) }))
            Divider().padding(.leading, 52)
            settingsToggle(symbol: "timer", title: "Daily progress on Explore",
                           isOn: Binding(
                            get: { !app.profile.hideDailyGoalBar },
                            set: { app.setHideDailyGoalBar(!$0) }
                           ))
            Divider().padding(.leading, 52)
            settingsToggle(symbol: "eye.slash", title: "Dim controls while watching",
                           isOn: Binding(
                            get: { app.profile.fadeWatchChrome },
                            set: { app.setFadeWatchChrome($0) }
                           ))
            Divider().padding(.leading, 52)

            settingsHeader("Playback")
            settingsToggle(symbol: "arrow.up.to.line", title: "Auto-scroll to next video",
                           isOn: Binding(
                            get: { app.profile.autoAdvanceEnabled },
                            set: { app.setAutoAdvanceEnabled($0) }
                           ))
            if app.profile.autoAdvanceEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Pause before next video")
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.1f s", app.profile.autoAdvancePauseSeconds))
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Binding(
                        get: { app.profile.autoAdvancePauseSeconds },
                        set: { app.setAutoAdvancePause($0) }
                    ), in: 0...3, step: 0.5)
                    .tint(Color.sakuraPink)
                }
                .padding(.leading, 52)
                .padding(.trailing, 16)
                .padding(.vertical, 8)
            }
            Divider().padding(.leading, 52)
            settingsToggle(symbol: "checkmark.message", title: "Pause for quick checks after videos",
                           isOn: $quickChecksEnabled)
            Divider().padding(.leading, 52)

            #if DEBUG
            settingsHeader("Debug · Marketing")
            SettingsRow(symbol: "play.circle", title: "1 · Sakura dark neon") {
                marketingScript = .coreSakuraDarkNeon
            }
            Divider().padding(.leading, 52)
            SettingsRow(symbol: "play.circle", title: "2 · Sakura dark") {
                marketingScript = .coreSakuraDarkOff
            }
            Divider().padding(.leading, 52)
            SettingsRow(symbol: "play.circle", title: "3 · Amber dark neon") {
                marketingScript = .coreAmberDarkNeon
            }
            Divider().padding(.leading, 52)
            SettingsRow(symbol: "play.circle", title: "4 · Amber dark") {
                marketingScript = .coreAmberDarkOff
            }
            Divider().padding(.leading, 52)
            SettingsRow(symbol: "film", title: "5 · Full app tour") {
                marketingScript = .fullTour
            }
            Divider().padding(.leading, 52)
            SettingsRow(symbol: "arrow.uturn.backward", title: "Reset demo data", tint: .red, iconTint: .red) { confirmReset = true }
            Divider().padding(.leading, 52)
            #endif

            SettingsRow(symbol: "lightbulb", title: "How Jojo works") { showHelp = true }
            Divider().padding(.leading, 52)
            if let onGiveFeedback {
                SettingsRow(symbol: "bubble.left.and.bubble.right", title: "Feedback") {
                    onGiveFeedback()
                }
                Divider().padding(.leading, 52)
            }
            if let onAcquisitionSurvey {
                SettingsRow(symbol: "megaphone", title: "How did you find Jojo?",
                            value: AcquisitionSource(rawValue: app.profile.acquisitionSource)?.title ?? "Answer") {
                    onAcquisitionSurvey()
                }
                Divider().padding(.leading, 52)
            }

            settingsHeader("Account")
            SettingsRow(symbol: "target", title: "Daily goal", value: "\(app.profile.dailyGoalMinutes) min") { showGoalPicker = true }
            Divider().padding(.leading, 52)
            SettingsRow(symbol: "star", title: "Manage Subscription", value: planText) {
                if app.purchases.isConfigured { showCustomerCenter = true } else { showManageSubs = true }
            }
            Divider().padding(.leading, 52)
            SettingsRow(symbol: "clock.arrow.circlepath", title: "Restore Purchases") {
                Task {
                    let outcome = await app.purchases.restore()
                    switch outcome {
                    case .success: restoreMessage = "Your Jojo Pro access is active."
                    case .cancelled, .pending: break
                    case .failed(let message): restoreMessage = message
                    }
                }
            }
            Divider().padding(.leading, 52)
            SettingsRow(symbol: "trash", title: "Delete All Data", tint: .red, iconTint: .red) { confirmDeleteAccount = true }
            Divider().padding(.leading, 52)

            settingsHeader("Legal & support")
            HStack(spacing: Spacing.m) {
                Image(systemName: "chart.bar.xaxis")
                    .foregroundStyle(Color.designOrangeDeep)
                    .frame(width: 28)
                AnalyticsConsentToggle()
            }
            .padding(.horizontal, Spacing.l)
            .frame(minHeight: 54)
            Divider().padding(.leading, 52)
            if let support = StoreConstants.supportURL {
                SettingsRow(symbol: "questionmark.circle", title: "Support") { openURL(support) }
                Divider().padding(.leading, 52)
            }
            if let privacy = StoreConstants.privacyURL {
                SettingsRow(symbol: "hand.raised", title: "Privacy Policy") { openURL(privacy) }
                Divider().padding(.leading, 52)
            }
            if let terms = StoreConstants.termsURL {
                SettingsRow(symbol: "doc.text", title: "Terms of Use") { openURL(terms) }
                Divider().padding(.leading, 52)
            }
            SettingsRow(symbol: "envelope", title: "Email support", value: StoreConstants.supportEmail) {
                if let mail = URL(string: "mailto:\(StoreConstants.supportEmail)?subject=Jojo%20Support") {
                    openURL(mail)
                }
            }
        }
        .cardStyle()
        .navigationDestination(isPresented: $showHelp) { HelpView(onGiveFeedback: onGiveFeedback) }
        #if DEBUG
        .fullScreenCover(item: $marketingScript) { script in
            MarketingShowcaseView(initialScript: script, accent: app.profile.theme, autoBegin: false)
        }
        .confirmationDialog("Reset demo data?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset words & history", role: .destructive) { app.resetDemoData() }
        } message: {
            Text("Your saved words and watch history return to the starter set.")
        }
        #endif
        .sheet(isPresented: $showGoalPicker) { DailyGoalSheet() }
        .sheet(isPresented: $showSubtitleHelp, onDismiss: {
            app.completeSubtitleSetup()
        }) {
            SubtitleLearningSettingsSheet()
        }
        .manageSubscriptionsSheet(isPresented: $showManageSubs)
        .sheet(isPresented: $showCustomerCenter) { JojoCustomerCenter() }
        .alert("Restore Purchases", isPresented: Binding(get: { restoreMessage != nil }, set: { if !$0 { restoreMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(restoreMessage ?? "")
        }
        .confirmationDialog("Delete all data?", isPresented: $confirmDeleteAccount, titleVisibility: .visible) {
            Button("Delete All Data", role: .destructive) { app.deleteAllUserData() }
        } message: {
            Text("This permanently erases words, decks, watch history, and settings on this device, deletes the synced vocab, speaking practice, and video requests stored for this device, and returns you to onboarding. To cancel Jojo Pro, use Manage Subscription or Settings → Apple ID → Subscriptions.")
        }
    }

    private func settingsHeader(_ title: String) -> some View {
            Text(title.uppercased())
            .font(.caption.weight(.bold))
            .foregroundStyle(Color.designOrange)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Spacing.l)
            .padding(.top, Spacing.m)
            .padding(.bottom, 4)
    }

    private func settingsToggle(symbol: String, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: Spacing.m) {
            Image(systemName: symbol)
                .foregroundStyle(Color.designOrangeDeep)
                .frame(width: 28)
            Toggle(title, isOn: isOn).tint(Color.designOrange)
        }
        .padding(.horizontal, Spacing.l)
        .frame(minHeight: 54)
    }
}
