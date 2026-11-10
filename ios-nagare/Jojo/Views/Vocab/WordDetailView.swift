import SwiftUI

/// Detail for a saved word: readings, definitions, context, SRS status, jump to clip.
struct WordDetailView: View {
    @Bindable var word: SavedWord
    @Environment(AppModel.self) private var app
    @State private var playing: Clip?
    @State private var showSearch: Bool = false
    @State private var confirmRemove: Bool = false
    @Environment(\.dismiss) private var dismiss

    @State private var playingLine: Int = 0
    @State private var reinforcing: [(clip: Clip, line: Int)] = []

    private var clip: Clip? { app.clip(id: word.contextClipId) }

    private var exampleLines: [Line] {
        var seen: Set<String> = []
        let original = clip?.lines[safe: word.contextLineIndex]
        let related = reinforcing.compactMap { $0.clip.lines[safe: $0.line] }
        return ([original].compactMap { $0 } + related).filter {
            !$0.text.isEmpty && seen.insert($0.text).inserted
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                WordHeaderCard(
                    surface: word.surface,
                    readings: word.readings,
                    romaji: word.romaji,
                    pos: word.pos,
                    conjugationClass: word.conjugationClass,
                    jlpt: word.jlpt,
                    badge: word.occurrenceCount,
                    showFurigana: app.profile.showFurigana,
                    showRomaji: app.profile.showRomaji
                )
                SectionTitle("Definition")
                VStack(spacing: Spacing.s) {
                    ForEach(Array(word.displayDefinitions(mode: app.profile.dictionary).enumerated()), id: \.offset) { index, def in
                        DefinitionRow(number: index + 1, tag: word.conjugationClass ?? word.pos, text: def)
                    }
                }
                if !word.contextSentence.isEmpty {
                    SectionTitle("Context")
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        if !word.contextNote.isEmpty {
                            Text(word.contextNote)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        HighlightedSentence(sentence: word.contextSentence, target: word.contextSurface.isEmpty ? word.surface : word.contextSurface)
                        if let clip, let line = clip.lines[safe: word.contextLineIndex] {
                            Text(line.translation)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Color.translationText)
                        }
                    }
                    .padding(Spacing.l)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.cardStroke))
                    if let clip {
                        ClipThumbnailButton(clip: clip) { playing = clip; playingLine = word.contextLineIndex }
                    }
                }
                if !reinforcing.isEmpty {
                    SectionTitle("Meet it again")
                    VStack(spacing: Spacing.s) {
                        ForEach(reinforcing, id: \.clip.id) { hit in
                            Button {
                                Haptics.light()
                                playingLine = hit.line
                                playing = hit.clip
                            } label: {
                                HStack(spacing: Spacing.m) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(hit.clip.lines[safe: hit.line]?.text ?? hit.clip.title)
                                            .font(JojoFont.jp(16, relativeTo: .body))
                                            .foregroundStyle(.primary)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                        Text(hit.clip.channelName)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                    Spacer(minLength: Spacing.s)
                                    Image(systemName: "play.fill")
                                        .foregroundStyle(Color.designOrange)
                                }
                                .padding(Spacing.m)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.cardStroke))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Play a line with \(word.surface) from \(hit.clip.channelName)")
                        }
                    }
                }
                Button {
                    showSearch = true
                } label: {
                    Label("Find more videos", systemImage: "headphones")
                }
                .buttonStyle(PrimaryButtonStyle())

                if !exampleLines.isEmpty {
                    SectionTitle("Example sentences")
                    VStack(spacing: Spacing.s) {
                        ForEach(exampleLines, id: \.text) { line in
                            NavigationLink {
                                exampleDetail(line)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: Spacing.s) {
                                        Text(line.text).font(JojoFont.jp(16, relativeTo: .body))
                                        Text(line.translation).font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    .multilineTextAlignment(.leading)
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(Color.studyAccent)
                                }
                                .padding(Spacing.m)
                                .background(Color.card, in: .rect(cornerRadius: Radius.card))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                SectionTitle("My notes")
                TextField("Add a note about this word", text: $word.personalNote, axis: .vertical)
                    .lineLimit(3...8)
                    .padding(Spacing.m)
                    .background(Color.card, in: .rect(cornerRadius: Radius.card))
                    .accessibilityLabel("Personal word notes")

                SectionTitle("Review stats")
                VStack(spacing: 0) {
                    LabeledContent("Status", value: word.state.rawValue.capitalized)
                        .padding(Spacing.m)
                    Divider()
                    LabeledContent("Next review", value: word.state == .known ? "Optional practice" : (word.isDueForReview() ? "Due now" : word.dueAt.formatted(.relative(presentation: .named))))
                        .padding(Spacing.m)
                    Divider()
                    LabeledContent("Added", value: word.addedAt.formatted(date: .abbreviated, time: .omitted))
                        .padding(Spacing.m)
                    Divider()
                    LabeledContent("Last reviewed", value: word.lastReviewedAt?.formatted(date: .abbreviated, time: .omitted) ?? "Never")
                        .padding(Spacing.m)
                    Divider()
                    LabeledContent("Times seen", value: word.occurrenceCount.formatted())
                        .padding(Spacing.m)
                }
                .background(Color.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.cardStroke))

                Button(role: .destructive) {
                    confirmRemove = true
                } label: {
                    Label("Remove from my words", systemImage: "trash")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .tint(Color.againText)
            }
            .padding(Spacing.l)
        }
        .background(Color.canvas.ignoresSafeArea())
        .navigationTitle(word.surface)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            app.hidesMainTabBar = true
            reinforcing = app.clipsReinforcing(wordKey: word.key, excluding: word.contextClipId)
        }
        .onDisappear {
            app.save()
            app.hidesMainTabBar = false
        }
        .fullScreenCover(item: $playing) { clip in
            ClipPlayerScreen(clip: clip, startLine: playingLine, loopLine: true)
        }
        .confirmationDialog("Remove \(word.surface)?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove word", role: .destructive) {
                Haptics.warning()
                dismiss()
                // Delete after the pop so this view never renders a deleted model.
                let target = word
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    app.removeWord(target)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its review history goes too, on this iPhone and in your synced backup.")
        }
        .sheet(isPresented: $showSearch) {
            SearchView(initialQuery: word.surface, initialScope: .sentences)
        }
    }

    private func exampleDetail(_ line: Line) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.l) {
                HighlightedSentence(sentence: line.text, target: word.contextSurface.isEmpty ? word.surface : word.contextSurface)
                    .font(JojoFont.jp(24, relativeTo: .title2))
                    .accessibilityAddTraits(.isHeader)
                Text(line.translation)
                    .foregroundStyle(.secondary)
                Button {
                    SpeechService.shared.speak(line.text)
                } label: {
                    Label("Listen to sentence", systemImage: "speaker.wave.2")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.l)
        }
        .background(Color.canvas.ignoresSafeArea())
        .navigationTitle("Example sentence")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
    }
}

struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(.secondary)
    }
}

/// Big centered word card used by Review and Word detail.
struct WordHeaderCard: View {
    let surface: String
    let readings: [String]
    let romaji: String
    let pos: String
    let conjugationClass: String?
    let jlpt: String?
    var badge: Int?
    var showFurigana: Bool = true
    var showRomaji: Bool = true

    var body: some View {
        VStack(spacing: Spacing.s) {
            if showFurigana, !readings.isEmpty {
                Text(readings.joined(separator: " · "))
                    .font(JojoFont.jp(18, relativeTo: .subheadline))
                    .foregroundStyle(Color.translationText)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: Spacing.s) {
                Text(surface)
                    .font(JojoFont.jp(44, bold: true, relativeTo: .largeTitle))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Button {
                    SpeechService.shared.speak(surface)
                } label: {
                    Image(systemName: "speaker.wave.2").font(.title2).frame(width: 44, height: 44)
                }
                .tint(.primary)
                .accessibilityLabel("Play pronunciation")
            }
            if showRomaji, !romaji.isEmpty {
                Text(romaji)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.translationText)
                    .multilineTextAlignment(.center)
            }
            WordPills(pos: pos, conjugationClass: conjugationClass, jlpt: jlpt)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xl)
        .padding(.horizontal, Spacing.l)
        .background(Color.card, in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous).strokeBorder(Color.cardStroke))
        .overlay(alignment: .topTrailing) {
            if let badge {
                OccurrenceBadge(count: badge).padding(Spacing.m)
            }
        }
    }
}

/// Playable clip thumbnail — prefers a real still from the bundled clip, not an empty gradient.
struct ClipThumbnailButton: View {
    let clip: Clip
    var emphasizesPlay: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Color.bgElevatedDark
                .aspectRatio(emphasizesPlay ? 16 / 9 : 16 / 8, contentMode: .fit)
                .overlay { ClipVideoStill(clip: clip, showsPlay: false).allowsHitTesting(false) }
                .overlay {
                    Image(systemName: "play.fill")
                        .font(emphasizesPlay ? .title : .title2)
                        .foregroundStyle(.white)
                        .frame(width: emphasizesPlay ? 68 : 60, height: emphasizesPlay ? 68 : 60)
                        .background(.black.opacity(0.45), in: Circle())
                        .overlay(Circle().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        if emphasizesPlay {
                            Text("Watch in context")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white.opacity(0.85))
                        }
                        Text(clip.channelName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                    .padding(Spacing.m)
                }
                .overlay(alignment: .bottomTrailing) {
                    Text(formatClock(clip.durationSec))
                        .font(.caption.weight(.bold)).monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.black.opacity(0.5), in: Capsule())
                        .padding(Spacing.m)
                }
                .clipShape(.rect(cornerRadius: Radius.card, style: .continuous))
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Play clip \(clip.title)")
    }
}
