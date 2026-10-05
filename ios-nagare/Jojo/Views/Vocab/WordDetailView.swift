import SwiftUI

/// Detail for a saved word: readings, definitions, context, SRS status, jump to clip.
struct WordDetailView: View {
    let word: SavedWord
    @Environment(AppModel.self) private var app
    @State private var playing: Clip?
    @State private var showSearch: Bool = false

    private var clip: Clip? { app.clip(id: word.contextClipId) }

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
                        ClipThumbnailButton(clip: clip) { playing = clip }
                    }
                }
                SectionTitle("Progress")
                VStack(spacing: 0) {
                    LabeledContent("Status", value: word.state.rawValue.capitalized)
                        .padding(Spacing.m)
                    Divider()
                    LabeledContent("Next review", value: word.dueAt <= Date() ? "Due now" : word.dueAt.formatted(.relative(presentation: .named)))
                        .padding(Spacing.m)
                    Divider()
                    LabeledContent("Added", value: word.addedAt.formatted(date: .abbreviated, time: .omitted))
                        .padding(Spacing.m)
                }
                .background(Color.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.cardStroke))

                Button {
                    showSearch = true
                } label: {
                    Label("Hear it in other clips", systemImage: "headphones")
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(Spacing.l)
        }
        .background(Color.canvas.ignoresSafeArea())
        .navigationTitle(word.surface)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear { app.hidesMainTabBar = true }
        .onDisappear { app.hidesMainTabBar = false }
        .fullScreenCover(item: $playing) { clip in
            ClipPlayerScreen(clip: clip, startLine: word.contextLineIndex, loopLine: true)
        }
        .sheet(isPresented: $showSearch) {
            SearchView(initialQuery: word.contextSurface.isEmpty ? word.surface : word.contextSurface)
        }
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
                .overlay { ClipPosterView(clip: clip, showsSymbol: false).allowsHitTesting(false) }
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
