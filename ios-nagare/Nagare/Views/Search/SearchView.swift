import SwiftUI

/// Search & Listen: find clips containing a word (kanji, kana or romaji). Matches are highlighted in
/// place and tappable, opening the same tap-to-understand popup.
struct SearchView: View {
    var initialQuery: String = ""

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""
    @State private var lookup = WordLookupController()
    @State private var playing: SearchHit?
    @FocusState private var isFocused: Bool

    private var hits: [SearchHit] { SearchMatcher.search(query, in: app.clips) }

    private let suggestions = ["天気", "たべる", "oishii", "大丈夫", "ことば", "ganbaru", "猫", "すごい"]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.l) {
                        searchField
                        if query.trimmingCharacters(in: .whitespaces).isEmpty {
                            suggestionsView
                        } else if hits.isEmpty {
                            VStack(spacing: Spacing.s) {
                                Image(systemName: "text.magnifyingglass").font(.largeTitle).foregroundStyle(.white.opacity(0.35))
                                Text("No clips say “\(query)” yet").font(.headline).foregroundStyle(.white)
                                Text("Try kana, kanji or romaji, e.g. たべ, 食べ or tabe.")
                                    .font(.subheadline).foregroundStyle(.white.opacity(0.55))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 50)
                        } else {
                            Text("\(hits.count) \(hits.count == 1 ? "moment" : "moments") in \(Set(hits.map(\.clip.id)).count) clips")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.6))
                                .padding(.horizontal, Spacing.l)
                            LazyVStack(spacing: Spacing.m) {
                                ForEach(hits) { hit in
                                    SearchHitCard(hit: hit, query: query) { playing = hit }
                                }
                            }
                            .padding(.horizontal, Spacing.l)
                        }
                    }
                    .padding(.vertical, Spacing.m)
                    .padding(.bottom, lookup.isPresented ? 360 : 0)
                }
                .scrollDismissesKeyboard(.interactively)
                if lookup.isPresented {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .onTapGesture { withAnimation(.snappy) { lookup.dismiss() } }
                        .transition(.opacity)
                    TapPopupCard()
                        .padding(.horizontal, Spacing.m)
                        .padding(.bottom, Spacing.m)
                        .gesture(DragGesture(minimumDistance: 12).onEnded { value in
                            if value.translation.height > 60 { withAnimation(.snappy) { lookup.dismiss() } }
                        })
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .background(Color.bgPlayer.ignoresSafeArea())
            .navigationTitle("Search & Listen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .toolbarBackground(Color.bgPlayer, for: .navigationBar)
        }
        .environment(lookup)
        .environment(\.colorScheme, .dark)
        .onAppear {
            if query.isEmpty { query = initialQuery }
            isFocused = initialQuery.isEmpty
        }
        .onChange(of: query) { _, _ in lookup.dismiss() }
        .fullScreenCover(item: $playing) { hit in
            ClipPlayerScreen(clip: hit.clip, startLine: hit.lineIndex, loopLine: true)
                .environment(app)
        }
    }

    private var searchField: some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.5))
            TextField("Search kanji, kana or romaji", text: $query)
                .focused($isFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .foregroundStyle(.white)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.white.opacity(0.5)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, Spacing.m)
        .frame(minHeight: 48)
        .background(Color.bgElevatedDark, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(.horizontal, Spacing.l)
    }

    private var suggestionsView: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("Try searching").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.6))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: Spacing.s)], alignment: .leading, spacing: Spacing.s) {
                ForEach(suggestions, id: \.self) { s in
                    Button {
                        Haptics.selection()
                        query = s
                    } label: {
                        Text(s)
                            .font(NagareFont.jp(16, relativeTo: .body))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color.bgElevatedDark, in: Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, Spacing.l)
    }
}

private struct SearchHitCard: View {
    let hit: SearchHit
    let query: String
    let onPlay: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack(spacing: Spacing.m) {
                Color.bgElevatedDark
                    .frame(width: 84, height: 52)
                    .overlay { GradientPoster(clip: hit.clip, showsSymbol: false).allowsHitTesting(false) }
                    .overlay { Image(systemName: "play.fill").foregroundStyle(.white) }
                    .clipShape(.rect(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(hit.clip.title).font(.subheadline.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
                    Text("\(hit.clip.channelName) · \(formatClock(hit.clip.lines[safe: hit.lineIndex]?.start ?? 0))")
                        .font(.caption).foregroundStyle(.white.opacity(0.55))
                }
                Spacer(minLength: 0)
                Button(action: onPlay) {
                    Image(systemName: "headphones")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Color.nagareOrange)
                        .frame(width: 44, height: 44)
                        .background(Color.nagareOrange.opacity(0.15), in: Circle())
                }
                .accessibilityLabel("Listen in context")
            }
            TranscriptLineView(clip: hit.clip, lineIndex: hit.lineIndex, spokenTokenIndex: nil, highlightSurface: query)
        }
        .padding(Spacing.m)
        .background(Color.bgSurfaceDark, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(Color.hairlineDark, lineWidth: 1))
    }
}
