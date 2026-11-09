import SwiftUI

/// Source & attribution sheet for a clip.
struct ClipInfoSheet: View {
    let clip: Clip
    var onShadowing: (() -> Void)?
    var onFullscreen: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AppModel.self) private var app
    @State private var showSpeaking = false
    @State private var showTranscriptReport = false

    var body: some View {
        NavigationStack {
            List {
                Section("Video") {
                    metadataField("Video", value: clip.title, systemImage: "play.rectangle")
                    metadataField("Channel", value: clip.channelName, systemImage: "person.crop.rectangle")
                    HStack(spacing: 12) {
                        ChannelAvatar(clip: clip, size: 42)
                        FollowChannelButton(channelName: clip.channelName)
                        Spacer(minLength: 0)
                        Button {
                            Haptics.light()
                            _ = app.toggleWatchLater(clip.id)
                        } label: {
                            Label(
                                app.isWatchLater(clip.id) ? "Saved" : "Later",
                                systemImage: app.isWatchLater(clip.id) ? "bookmark.fill" : "bookmark"
                            )
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 2)
                }

                Section("Playback") {
                    HStack(spacing: 28) {
                        detailMetric(
                            "Clip",
                            value: "\(formatClock(sourceStart)) – \(formatClock(sourceEnd))",
                            systemImage: "film"
                        )
                        detailMetric("Clip length", value: formatClock(clip.durationSec), systemImage: "clock")
                    }
                }

                Section("Difficulty") {
                    VStack(alignment: .leading, spacing: 6) {
                        Label(difficultyTitle, systemImage: "chart.bar")
                            .font(.headline)
                        Text(difficultyDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }

                Section("Topics") {
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        metadataChip(clip.categoryKind.displayName)
                    }
                }

                Section("Style") {
                    FlowLayout(spacing: 8, lineSpacing: 8) {
                        ForEach(styleTags, id: \.self) { metadataChip($0) }
                    }
                }

                Section("Practice") {
                    if let onShadowing {
                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onShadowing() }
                        } label: {
                            Label("Shadowing practice", systemImage: "mic.fill")
                        }
                    }
                    Button {
                        showSpeaking = true
                    } label: {
                        Label("Speaking scenes", systemImage: "bubble.left.and.bubble.right.fill")
                    }
                    if let onFullscreen {
                        Button {
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onFullscreen() }
                        } label: {
                            Label("Open focused player", systemImage: "arrow.up.left.and.arrow.down.right")
                        }
                    }
                }

                Section("Your progress") {
                    LabeledContent("Transcript lines", value: "\(clip.lines.count)")
                    if let mastery = app.seriesMastery().first(where: { $0.channelName == clip.channelName }),
                       mastery.seenUnique >= 5 {
                        LabeledContent("Channel coverage", value: "\(mastery.percent)%")
                    }
                    let understood = ClipComprehension.measure(clip: clip) { app.wordState(for: $0) }
                    if understood.total > 0 {
                        LabeledContent("Understood now", value: "\(understood.percent)%")
                    }
                }

                if let url = clip.youtubeURL {
                    Section {
                        Button {
                            openURL(url)
                        } label: {
                            HStack {
                                Spacer(minLength: 0)
                                Label("Watch full video", systemImage: "play.circle")
                                    .font(.headline)
                                Spacer(minLength: 0)
                            }
                            .frame(minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.jojoOrange)
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    if let url = clip.youtubeURL {
                        Button {
                            openURL(url)
                        } label: {
                            Label("Open original on YouTube", systemImage: "play.rectangle.fill")
                        }
                    } else {
                        Label("Preview clip with timed captions. The original video plugs in once a YouTube ID is added.", systemImage: "waveform")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Source")
                } footer: {
                    Text("Jojo streams the original public source and does not re-host the video. The clip range above is the excerpt used for this lesson.")
                }
                Section {
                    Button {
                        showTranscriptReport = true
                    } label: {
                        Label("Report a transcript issue", systemImage: "flag")
                    }
                    .disabled(clip.lines.isEmpty)
                }
            }
            .navigationTitle("Video details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showSpeaking) {
                SpeakingScenesView()
            }
            .sheet(isPresented: $showTranscriptReport) {
                TranscriptCorrectionSheet(clip: clip)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)
    }

    private var sourceStart: Double {
        max(0, clip.sourceStartSec ?? 0)
    }

    private var sourceEnd: Double {
        sourceStart + max(0, clip.durationSec)
    }

    private var difficultyTitle: String {
        if let jlpt = clip.dominantJLPT {
            return "\(jlpt) · \(clip.difficulty)"
        }
        return clip.difficulty
    }

    private var difficultyDescription: String {
        switch clip.difficultyKind {
        case .beginner:
            "Everyday expressions and short, straightforward sentences."
        case .intermediate:
            "Natural speech with a broader vocabulary and more connected ideas."
        case .advanced:
            "Fast or nuanced speech with less common vocabulary and grammar."
        }
    }

    private var styleTags: [String] {
        let transcriptStyles = Set(
            clip.lines
                .flatMap(\.tokens)
                .compactMap(\.formality)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .map { $0.capitalized }
        )
        if !transcriptStyles.isEmpty { return transcriptStyles.sorted() }

        switch clip.categoryKind {
        case .anime, .drama:
            return ["Scripted"]
        case .learning:
            return ["Instructional"]
        case .interview, .podcast:
            return ["Conversational"]
        case .kids:
            return ["Family"]
        case .variety, .vtuber, .gaming:
            return ["Casual"]
        }
    }

    private func metadataField(_ label: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(label, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    private func detailMetric(_ label: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(label, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body)
                .monospacedDigit()
                .fixedSize()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func metadataChip(_ value: String) -> some View {
        Text(value)
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.fieldFill, in: Capsule())
    }
}
