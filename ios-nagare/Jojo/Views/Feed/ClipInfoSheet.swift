import SwiftUI

/// Source & attribution sheet for a clip.
struct ClipInfoSheet: View {
    let clip: Clip
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var reported: Bool = false

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
                }
                Section("Details") {
                    LabeledContent("Category", value: clip.categoryKind.displayName)
                    LabeledContent("Difficulty", value: clip.difficulty)
                    LabeledContent("Length", value: formatClock(clip.durationSec))
                    LabeledContent("Lines", value: "\(clip.lines.count)")
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
                    // External platforms (Crunchyroll, Netflix, etc.) own their streams and
                    // closed captions. Jojo only embeds YouTube (or similar) URLs the creators
                    // already published, and draws its own learner transcript — never scraped
                    // licensed captions or re-hosted video. Keep this note if sources change.
                    Text("Jojo streams clips from their original public source and never re-hosts video. Learner subtitles are Jojo’s own transcript + translation, not third-party closed captions (e.g. Crunchyroll). All rights belong to the creators.")
                }
                Section {
                    Button(role: .destructive) {
                        reported = true
                        Haptics.success()
                        track("clip_reported", props: ["clip": clip.id])
                    } label: {
                        Label(reported ? "Thanks, we'll take a look" : "Report a problem with this clip", systemImage: reported ? "checkmark.circle.fill" : "flag")
                    }
                    .disabled(reported)
                }
            }
            .navigationTitle("Clip info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationContentInteraction(.scrolls)
    }
}
