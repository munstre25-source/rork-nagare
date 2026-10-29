import SwiftUI
import UIKit

/// "Bring your own video": paste a YouTube link and Jojo builds a tappable lesson from it.
/// Video plays through YouTube's embedded player; nothing is downloaded or stored.
struct ImmersionImportView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var link: String = ""
    @State private var playing: Clip?
    @FocusState private var fieldFocused: Bool

    private var store: ImmersionStore { app.immersion }
    private var trimmed: String { link.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var looksValid: Bool { YouTubeLink.videoId(from: trimmed) != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    intro
                    linkField
                    if let error = store.lastError {
                        errorBanner(error)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                    if !store.jobs.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Your videos")
                                .font(.headline)
                            ForEach(store.jobs) { job in
                                ImmersionJobRow(job: job) {
                                    if let clip = job.clip { playing = clip }
                                } onRetry: {
                                    Task { await store.retry(job) }
                                } onHide: {
                                    withAnimation(.snappy) { store.hide(job) }
                                }
                            }
                        }
                    }
                    footnote
                }
                .padding(20)
                .animation(.snappy, value: store.lastError)
                .animation(.snappy, value: store.jobs)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.studyPage.ignoresSafeArea())
            .navigationTitle("Your own video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .refreshable { await store.refresh() }
            .task { await store.refresh() }
            .onDisappear { store.clearError() }
            .fullScreenCover(item: $playing) { clip in
                ClipPlayerScreen(clip: clip, queue: store.readyClips)
                    .environment(app)
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Learn from any Japanese video")
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            Text("Paste a YouTube link. Jojo listens for the Japanese, writes the captions with readings and meanings, and syncs them to the video.")
                .font(.subheadline)
                .foregroundStyle(Color.studyMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var linkField: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "link")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField("youtube.com/watch?v=…", text: $link)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .focused($fieldFocused)
                    .onSubmit(submit)
                    .onChange(of: link) { _, _ in
                        if store.lastError != nil { store.clearError() }
                    }
                if link.isEmpty {
                    PasteButton(payloadType: String.self) { strings in
                        guard let first = strings.first else { return }
                        Task { @MainActor in link = first.trimmingCharacters(in: .whitespacesAndNewlines) }
                    }
                    .buttonBorderShape(.capsule)
                    .labelStyle(.titleOnly)
                    .tint(Color.designOrange)
                    .controlSize(.small)
                } else {
                    Button {
                        link = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .frame(width: 32, height: 32)
                    }
                    .accessibilityLabel("Clear link")
                }
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 52)
            .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(fieldFocused ? Color.designOrange : Color.cardStroke, lineWidth: fieldFocused ? 1.5 : 1)
            )

            Button(action: submit) {
                HStack(spacing: 8) {
                    if store.isSubmitting {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(store.isSubmitting ? "Sending…" : "Make it a lesson")
                }
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(
                    Color.designOrange.opacity(looksValid && !store.isSubmitting ? 1 : 0.45),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            }
            .buttonStyle(PressableStyle())
            .disabled(!looksValid || store.isSubmitting)
            .sensoryFeedback(.selection, trigger: store.isSubmitting)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color.designOrange)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.designOrange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var footnote: some View {
        Text("Works best with 1–20 minute videos where people speak Japanese. Live streams, private and members-only videos, and videos that block embedding can't be used. The video always plays from YouTube.")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func submit() {
        guard looksValid, !store.isSubmitting else {
            if !trimmed.isEmpty, !looksValid {
                Task { await store.submit(trimmed) } // Surfaces the "not a YouTube link" message.
            }
            return
        }
        let value = trimmed
        fieldFocused = false
        Task {
            if await store.submit(value) { link = "" }
        }
    }
}

/// One request: thumbnail, title, stage progress, and the right action for its state.
private struct ImmersionJobRow: View {
    let job: ImmersionJob
    let onOpen: () -> Void
    let onRetry: () -> Void
    let onHide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                thumbnail
                VStack(alignment: .leading, spacing: 4) {
                    Text(job.displayTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let channel = job.clip?.channelName ?? job.channelName, !channel.isEmpty {
                        Text(channel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    statusLine
                }
                Spacer(minLength: 0)
                Menu {
                    if let url = job.watchURL {
                        Link(destination: url) { Label("Open on YouTube", systemImage: "arrow.up.right.square") }
                    }
                    Button(role: .destructive, action: onHide) {
                        Label("Remove from list", systemImage: "eye.slash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("More options")
            }

            if job.isActive {
                ProgressView(value: job.stageProgress)
                    .tint(Color.designOrange)
                    .animation(.easeInOut(duration: 0.5), value: job.stageProgress)
            }

            if let message = job.errorMessage, job.phase == .failed || job.phase == .unprocessable || (job.isActive && job.attempts > 0) {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            actions
        }
        .padding(14)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.cardStroke))
    }

    @ViewBuilder
    private var actions: some View {
        switch job.phase {
        case .ready:
            Button(action: onOpen) {
                Label("Watch with captions", systemImage: "play.fill")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(Color.designOrange, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(PressableStyle())
        case .failed, .unprocessable:
            if job.canRetry {
                Button(action: onRetry) {
                    Label("Try again", systemImage: "arrow.clockwise")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .tint(Color.designOrange)
            }
        case .queued, .working:
            EmptyView()
        }
    }

    private var statusLine: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(job.stageLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(statusColor)
            if job.phase == .ready, job.clip?.lines.contains(where: { !$0.hasWordTiming }) == true {
                Text("· sentence sync")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var statusColor: Color {
        switch job.phase {
        case .ready: Color.spokenGreen
        case .failed, .unprocessable: Color.againText
        case .queued, .working: Color.designOrange
        }
    }

    private var thumbnail: some View {
        AsyncImage(url: URL(string: "https://i.ytimg.com/vi/\(job.videoId)/mqdefault.jpg")) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Color.bgElevatedDark.overlay {
                    Image(systemName: "play.rectangle.fill").foregroundStyle(.tertiary)
                }
            }
        }
        .frame(width: 96, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if let seconds = job.clip?.durationSec ?? job.videoDurationSec, seconds > 0 {
                Text(formatClock(seconds))
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 4))
                    .padding(4)
            }
        }
        .accessibilityHidden(true)
    }
}
