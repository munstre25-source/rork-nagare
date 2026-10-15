import SwiftUI

/// Watched / Saved / Later shelves — Yomi-style Library separate from the infinite feed.
struct LibraryView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    /// Feed presents Library as a focused destination; a standalone tab does not need a close button.
    var presentedModally: Bool = false
    @State private var shelf: LibraryShelf = .watched
    @State private var playing: Clip?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                picker
                let clips = app.libraryClips(shelf: shelf)
                if clips.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: Spacing.m) {
                            ForEach(clips) { clip in
                                LibraryClipRow(clip: clip, shelf: shelf) {
                                    playing = clip
                                }
                            }
                        }
                        .padding(Spacing.l)
                    }
                }
            }
            .background(Color.canvas.ignoresSafeArea())
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if presentedModally {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.body.weight(.semibold))
                        }
                        .accessibilityLabel("Close Library")
                    }
                }
            }
            .fullScreenCover(item: $playing) { clip in
                ClipPlayerScreen(clip: clip)
            }
        }
    }

    private var picker: some View {
        HStack(spacing: 6) {
            ForEach(LibraryShelf.allCases) { item in
                Button {
                    Haptics.selection()
                    withAnimation(.snappy) { shelf = item }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 14, weight: .semibold))
                        Text(item.title)
                            .font(.caption2.weight(.bold))
                    }
                    .foregroundStyle(shelf == item ? Color.sakuraPink : .secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        shelf == item ? Color.sakuraPink.opacity(0.14) : Color.clear,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }
                .accessibilityAddTraits(shelf == item ? .isSelected : [])
            }
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, Spacing.s)
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.m) {
            Spacer()
            Image(systemName: shelf.symbol)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(Color.sakuraPink)
            Text(shelf.subtitle)
                .font(.headline)
            Text(emptyCopy)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyCopy: String {
        switch shelf {
        case .watched: "Finish a clip in Feed and it lands here."
        case .saved: "Heart a clip to keep it in Saved."
        case .later: "Bookmark a clip for Later from the clip menu."
        }
    }
}

private struct LibraryClipRow: View {
    let clip: Clip
    let shelf: LibraryShelf
    let onPlay: () -> Void
    @Environment(AppModel.self) private var app

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: Spacing.m) {
                ClipPosterView(clip: clip, showsSymbol: false)
                    .frame(width: 96, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(clip.title)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        if let jlpt = clip.dominantJLPT {
                            Text("\(jlpt) est.")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.sakuraPink)
                        }
                        Text(clip.channelName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Menu {
                    if shelf != .saved {
                        Button(app.isFavorite(clip.id) ? "Unsave" : "Save") {
                            _ = app.toggleFavorite(clip.id)
                        }
                    }
                    if shelf != .later {
                        Button(app.isWatchLater(clip.id) ? "Remove from Later" : "Watch later") {
                            _ = app.toggleWatchLater(clip.id)
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                }
            }
            .padding(12)
            .background(Color.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Color.cardStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
