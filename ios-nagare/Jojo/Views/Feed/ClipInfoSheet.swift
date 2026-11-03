import SwiftUI

/// Source & attribution sheet for a clip.
struct ClipInfoSheet: View {
    let clip: Clip
    var onShadowing: (() -> Void)?
    var onFullscreen: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AppModel.self) private var app
    @Environment(PlaybackCoordinator.self) private var coordinator
    @State private var showSpeaking = false
    @State private var showTranscriptReport = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: Spacing.m) {
                        ChannelAvatar(clip: clip, size: 48)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(clip.title).font(.headline)
                            Text(clip.channelName).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    FollowChannelButton(channelName: clip.channelName)
                    Button {
                        Haptics.light()
                        _ = app.toggleWatchLater(clip.id)
                    } label: {
                        Label(
                            app.isWatchLater(clip.id) ? "Remove from Later" : "Watch later",
                            systemImage: app.isWatchLater(clip.id) ? "bookmark.fill" : "bookmark"
                        )
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
                            Label("Watch fullscreen", systemImage: "arrow.up.left.and.arrow.down.right")
                        }
                    }
                }
                Section("Details") {
                    if let jlpt = clip.dominantJLPT {
                        LabeledContent("JLPT est.", value: jlpt)
                    }
                    LabeledContent("Category", value: clip.categoryKind.displayName)
                    LabeledContent("Difficulty", value: clip.difficulty)
                    LabeledContent("Length", value: formatClock(clip.durationSec))
                    LabeledContent("Lines", value: "\(clip.lines.count)")
                    if let mastery = app.seriesMastery().first(where: { $0.channelName == clip.channelName }),
                       mastery.seenUnique >= 5 {
                        LabeledContent("Your coverage", value: "\(mastery.percent)% of words from this channel")
                    }
                    let understood = ClipComprehension.measure(clip: clip) { app.wordState(for: $0) }
                    if understood.total > 0 {
                        LabeledContent("Understood now", value: "\(understood.percent)%")
                    }
                }
                Section {
                    if let url = clip.youtubeURL {
                        Button {
                            openURL(url)
                        } label: {
                            Label("Watch the original on YouTube", systemImage: "play.rectangle.fill")
                        }
                    } else {
                        Label("Preview clip with timed captions. The original video plugs in once a YouTube ID is added.", systemImage: "waveform")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Source")
                } footer: {
                    Text(clip.lines.first?.timing == "line" && clip.id.hasPrefix("cap-")
                         ? "Jojo streams this clip from its original public source. Subtitles for this clip come from the creator’s own uploaded captions, tokenized for study. All rights belong to the creators."
                         : "Jojo streams clips from their original public source and never re-hosts video. Learner subtitles are Jojo’s own transcript + translation, not third-party closed captions (e.g. Crunchyroll). All rights belong to the creators.")
                }
                Section {
                    Button {
                        coordinator.pauseForPopup()
                        showTranscriptReport = true
                    } label: {
                        Label("Report a transcript issue", systemImage: "flag")
                    }
                    .disabled(clip.lines.isEmpty)
                }
            }
            .navigationTitle("Clip info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showSpeaking) {
                SpeakingScenesView()
            }
            .sheet(isPresented: $showTranscriptReport, onDismiss: {
                coordinator.resumeAfterPopupIfNeeded()
            }) {
                TranscriptCorrectionSheet(clip: clip)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)
    }
}
