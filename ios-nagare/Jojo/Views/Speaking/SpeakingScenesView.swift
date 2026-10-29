import SwiftUI

/// Situation-based speaking practice (konbini / station / restaurant) — Yomi-style scenes
/// on top of Jojo’s shadowing + speech scoring.
struct SpeakingScene: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let symbol: String
    let level: String
    let prompt: String
    let clerkLine: String
    let clerkReading: String
    let yourLine: String
    let yourReading: String
    let yourRomaji: String
    let english: String
}

enum SpeakingCatalog {
    static let scenes: [SpeakingScene] = [
        SpeakingScene(
            id: "konbini",
            title: "At the konbini",
            symbol: "storefront.fill",
            level: "N5",
            prompt: "Buy something at the counter.",
            clerkLine: "いらっしゃいませ。",
            clerkReading: "Irasshaimase.",
            yourLine: "これ、お願いします。",
            yourReading: "これ、おねがいします。",
            yourRomaji: "kore, onegai shimasu",
            english: "This one, please."
        ),
        SpeakingScene(
            id: "station",
            title: "At the station",
            symbol: "tram.fill",
            level: "N5",
            prompt: "Ask which platform.",
            clerkLine: "どちらへ行かれますか？",
            clerkReading: "Dochira e ikaremasu ka?",
            yourLine: "渋谷は何番線ですか？",
            yourReading: "しぶやはなんばんせんですか？",
            yourRomaji: "shibuya wa nan-bansen desu ka",
            english: "Which platform for Shibuya?"
        ),
        SpeakingScene(
            id: "restaurant",
            title: "At a restaurant",
            symbol: "fork.knife",
            level: "N4",
            prompt: "Order a meal.",
            clerkLine: "ご注文はお決まりですか？",
            clerkReading: "Go-chuumon wa okimari desu ka?",
            yourLine: "ラーメンを一つください。",
            yourReading: "らーめんをひとつください。",
            yourRomaji: "raamen o hitotsu kudasai",
            english: "One ramen, please."
        ),
    ]
}

struct SpeakingScenesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selected: SpeakingScene?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Hear a native line, say yours back, and see how close you got — the same loop as shadowing, packaged as real situations.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
                Section("Scenes") {
                    ForEach(SpeakingCatalog.scenes) { scene in
                        Button {
                            Haptics.selection()
                            selected = scene
                        } label: {
                            HStack(spacing: Spacing.m) {
                                Image(systemName: scene.symbol)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(Color.sakuraPink)
                                    .frame(width: 40, height: 40)
                                    .background(Color.sakuraPink.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(scene.title)
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                    Text("\(scene.level) · \(scene.prompt)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Speaking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selected) { scene in
                SpeakingScenePractice(scene: scene)
            }
        }
    }
}

struct SpeakingScenePractice: View {
    let scene: SpeakingScene
    @Environment(\.dismiss) private var dismiss

    @State private var phase: Phase = .hear
    @State private var heard: String = ""
    @State private var score: Int?
    @State private var listening = false
    @State private var note: String?

    private enum Phase { case hear, speak, result }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Spacing.l) {
                Label(scene.title, systemImage: scene.symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(Color.sakuraPink)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Clerk")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(scene.clerkLine)
                        .font(JojoFont.jp(26, bold: true, relativeTo: .title))
                    Text(scene.clerkReading)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        SpeechService.shared.speak(scene.clerkLine)
                    } label: {
                        Label("Hear the clerk", systemImage: "speaker.wave.2.fill")
                            .font(.subheadline.weight(.bold))
                    }
                }
                .padding(Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Your line")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    Text(scene.yourLine)
                        .font(JojoFont.jp(28, bold: true, relativeTo: .title))
                        .foregroundStyle(LearningInk.japanese)
                    Text("\(scene.yourReading) · \(scene.yourRomaji)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text(scene.english)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(Spacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))

                phaseBlock

                Spacer()
            }
            .padding(Spacing.l)
            .background(Color.canvas.ignoresSafeArea())
            .navigationTitle(scene.level)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var phaseBlock: some View {
        switch phase {
        case .hear:
            Button {
                SpeechService.shared.speak(scene.yourLine)
                phase = .speak
            } label: {
                Label("Hear your line, then speak", systemImage: "ear")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.sakuraButton)
        case .speak:
            Button {
                Task { await capture() }
            } label: {
                Label(listening ? "Listening…" : "Tap the mic and say it", systemImage: listening ? "waveform" : "mic.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.sakuraButton)
            .disabled(listening)
            if let note {
                Text(note).font(.footnote).foregroundStyle(.secondary)
            }
        case .result:
            VStack(alignment: .leading, spacing: 10) {
                if let score {
                    Text(score >= 70 ? "Nice — \(score)% recognition match" : "Keep going — \(score)% recognition match")
                        .font(.title3.weight(.black))
                        .foregroundStyle(score >= 70 ? LearningInk.known : Color.jojoOrange)
                    Text("How closely speech recognition's text matched the line. Not a pronunciation grade.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !heard.isEmpty {
                    Text("Heard: \(heard)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Try again") {
                        heard = ""
                        score = nil
                        phase = .speak
                    }
                    .buttonStyle(.bordered)
                    Button("Hear model") {
                        SpeechService.shared.speak(scene.yourLine)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.sakuraButton)
                }
            }
        }
    }

    private func capture() async {
        listening = true
        note = nil
        let result = await SpeechPractice.listen()
        listening = false
        switch result {
        case .heard(let text, _):
            heard = text
            score = SpeechScoring.score(heard: text, target: scene.yourLine)
            phase = .result
            Haptics.success()
        case .unavailable(let message):
            note = message
            Haptics.warning()
        }
    }
}
