import SwiftUI

/// Shadowing practice: listen → mute & speak → compare with TTS model.
struct ShadowingOverlay: View {
    let clip: Clip
    @Environment(PlaybackCoordinator.self) private var coordinator
    @Environment(\.dismiss) private var dismiss

    @State private var lineIndex: Int = 0
    @State private var phase: Phase = .listen
    @State private var wasMuted: Bool = false

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
            .background(Color.canvas.ignoresSafeArea())
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
                    .font(.body)
                    .foregroundStyle(.secondary)
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
                Text("Speak now. Video is muted.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    enterCompare(line)
                } label: {
                    Label("I said it — compare", systemImage: "ear")
                }
                .buttonStyle(PrimaryButtonStyle())
            case .compare:
                Button {
                    SpeechService.shared.speak(line.text)
                    Haptics.selection()
                } label: {
                    Label("Hear model again", systemImage: "waveform")
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
        coordinator.pause()
        if !coordinator.isMuted { coordinator.toggleMute() }
        Haptics.medium()
    }

    private func enterCompare(_ line: Line) {
        phase = .compare
        coordinator.pause()
        SpeechService.shared.speak(line.text)
        Haptics.success()
    }

    private func nextLine() {
        if lineIndex + 1 >= clip.lines.count {
            finish()
            return
        }
        lineIndex += 1
        playListen()
    }

    private func finish() {
        track("shadowing_finished", props: ["clip": clip.id, "lines": String(lineIndex + 1)])
        dismiss()
    }
}
