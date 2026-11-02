import SwiftUI

/// Shadowing practice: listen → mute & speak → compare with TTS model.
struct ShadowingOverlay: View {
    let clip: Clip
    @Environment(PlaybackCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss

    @State private var lineIndex: Int = 0
    @State private var phase: Phase = .listen
    @State private var wasMuted: Bool = false
    @State private var heard: String = ""
    @State private var score: Int?
    @State private var listenNote: String?
    @State private var listening = false
    @State private var history: [PracticeAttemptRow] = []
    @State private var historyTask: Task<Void, Never>?

    private enum Phase: String {
        case listen, practice, compare
    }

    private var line: Line? { clip.lines[safe: lineIndex] }

    var body: some View {
        NavigationStack {
            VStack(spacing: Spacing.l) {
                progress
                if let line {
                    card(line)
                    phaseControls(line)
                } else {
                    Text("No lines in this clip.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(Spacing.l)
            .background(Color.watchBackground.ignoresSafeArea())
            .navigationTitle("Shadowing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { finish() }
                }
            }
        }
        .onAppear {
            wasMuted = coordinator.isMuted
            lineIndex = coordinator.player(for: clip)?.currentLineIndex ?? 0
            playListen()
            track("shadowing_started", props: ["clip": clip.id])
        }
        .onDisappear {
            coordinator.player?.setLoop(nil)
            if coordinator.isMuted != wasMuted { coordinator.toggleMute() }
            coordinator.player?.setRate(coordinator.preferredRate)
        }
        .presentationDetents([.medium, .large])
    }

    private var progress: some View {
        HStack {
            Text("Line \(lineIndex + 1)/\(max(clip.lines.count, 1))")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Text(phaseLabel)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.jojoOrange)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.jojoOrangeSoft, in: Capsule())
        }
    }

    private var phaseLabel: String {
        switch phase {
        case .listen: "1 · Listen"
        case .practice: "2 · Your turn"
        case .compare: "3 · Compare"
        }
    }

    private func card(_ line: Line) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text(line.text)
                .font(JojoFont.jp(28, bold: true, relativeTo: .title))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if phase != .practice {
                Text(line.translation)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.translationText)
            } else {
                Text("Say it out loud — translation hidden.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.cardStroke))
    }

    private func phaseControls(_ line: Line) -> some View {
        VStack(spacing: Spacing.m) {
            switch phase {
            case .listen:
                Button {
                    playListen()
                } label: {
                    Label("Play again", systemImage: "speaker.wave.2.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                Button {
                    enterPractice()
                } label: {
                    Label("I heard it — my turn", systemImage: "mic.fill")
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered)
            case .practice:
                if listening {
                    Text("Listening… say the line.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if let listenNote {
                    Text(listenNote)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button {
                    Task { await capture(line) }
                } label: {
                    Label(listening ? "Listening" : "Say the line", systemImage: "mic.fill")
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(listening)
            case .compare:
                if let score {
                    VStack(spacing: 4) {
                        Text("Recognition match")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(score >= 70 ? "\(score)% — that landed." : "\(score)% — try the line once more.")
                            .font(.headline)
                            .foregroundStyle(score >= 70 ? Color.spokenGreen : Color.designOrange)
                            .contentTransition(.numericText())
                    }
                    .accessibilityElement(children: .combine)
                }
                if !heard.isEmpty {
                    VStack(spacing: 2) {
                        Text("Recognized as")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                        Text(heard)
                            .font(JojoFont.jp(18, relativeTo: .body))
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Text("Compares speech recognition's text with the line. It isn't a pronunciation grade.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if !history.isEmpty {
                    historyStrip
                }
                Button {
                    SpeechService.shared.speak(line.text)
                    Haptics.selection()
                } label: {
                    Label("Hear the line", systemImage: "waveform")
                }
                .buttonStyle(PrimaryButtonStyle())
                Button {
                    nextLine()
                } label: {
                    Label(lineIndex + 1 >= clip.lines.count ? "Finish" : "Next line", systemImage: "arrow.right")
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private func playListen() {
        phase = .listen
        if coordinator.isMuted { coordinator.toggleMute() }
        guard let player = coordinator.player(for: clip) ?? {
            coordinator.activate(clip, autoplay: false)
            return coordinator.player(for: clip)
        }() else { return }
        guard let line = clip.lines[safe: lineIndex] else { return }
        let range = max(0, line.start - 0.2)...min(player.duration, line.end + 0.35)
        player.setRate(0.85)
        player.setLoop(range)
        player.seek(to: range.lowerBound)
        player.play()
    }

    private func enterPractice() {
        phase = .practice
        heard = ""
        score = nil
        listenNote = nil
        coordinator.pause()
        if !coordinator.isMuted { coordinator.toggleMute() }
        Haptics.medium()
        guard let line = clip.lines[safe: lineIndex] else { return }
        Task { await capture(line) }
    }

    private func capture(_ line: Line) async {
        guard !line.text.isEmpty else { return }
        listening = true
        listenNote = nil
        let result = await SpeechPractice.listen()
        listening = false
        switch result {
        case .heard(let text, let onDevice):
            DailyPlanProgress.mark(.speak)
            heard = text
            let similarity = SpeechScoring.score(heard: text, target: line.text)
            score = similarity
            phase = .compare
            Haptics.success()
            record(line: line, heard: text, similarity: similarity, onDevice: onDevice)
        case .unavailable(let message):
            listenNote = message
        }
    }

    private func nextLine() {
        if lineIndex + 1 >= clip.lines.count {
            finish()
            return
        }
        lineIndex += 1
        history = []
        playListen()
    }

    /// Last attempts on this line, newest first. Synced under the learner's anonymous user.
    private var historyStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Your recent tries")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(Array(history.prefix(5).enumerated()), id: \.offset) { _, attempt in
                    Text("\(attempt.similarity)%")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(attempt.similarity >= 70 ? Color.spokenGreen : Color.designOrange)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.card, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.cardStroke))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Saves the attempt, then reloads this line's history. Failures are silent: practice works offline.
    private func record(line: Line, heard: String, similarity: Int, onDevice: Bool) {
        let api = UserDataAPI.shared
        guard api.isConfigured, !line.text.isEmpty else { return }
        let attempt = PracticeAttemptRow(
            id: nil,
            clipId: String(clip.id.prefix(120)),
            lineIndex: lineIndex,
            targetText: String(line.text.prefix(400)),
            recognizedText: String(heard.prefix(400)),
            similarity: similarity,
            scoringMethod: "recognition_similarity",
            locale: "ja-JP",
            onDevice: onDevice,
            createdAt: nil
        )
        // Show this try immediately; the server list replaces it once saved.
        history.insert(attempt, at: 0)
        let clipId = attempt.clipId
        let index = lineIndex
        historyTask?.cancel()
        historyTask = Task {
            do {
                try await api.recordPractice(attempt)
                let rows = try await api.practiceHistory(clipId: clipId, lineIndex: index)
                guard !Task.isCancelled, index == lineIndex else { return }
                history = rows
            } catch {
                // Offline: keep the local list for this session.
            }
        }
    }

    private func finish() {
        track("shadowing_finished", props: ["clip": clip.id, "lines": String(lineIndex + 1)])
        dismiss()
    }
}
