import SwiftUI

/// Common grammar patterns a learner can hunt for. Matched against the transcript text, so no server data is needed.
nonisolated enum ExploreGrammar: String, CaseIterable, Identifiable, Sendable {
    case teiru, tai, nai, masu, te, kara, kedo, deshou, tara, nakereba

    var id: String { rawValue }

    var title: String {
        switch self {
        case .teiru: "〜ている"
        case .tai: "〜たい"
        case .nai: "〜ない"
        case .masu: "〜ます / ました"
        case .te: "〜てください"
        case .kara: "〜から"
        case .kedo: "〜けど"
        case .deshou: "〜でしょう"
        case .tara: "〜たら"
        case .nakereba: "〜なきゃ"
        }
    }

    var gloss: String {
        switch self {
        case .teiru: "ongoing action"
        case .tai: "want to"
        case .nai: "negative"
        case .masu: "polite verbs"
        case .te: "please do"
        case .kara: "because / from"
        case .kedo: "but"
        case .deshou: "probably"
        case .tara: "if / when"
        case .nakereba: "have to"
        }
    }

    private var needles: [String] {
        switch self {
        case .teiru: ["ている", "でいる", "てる", "てます", "ています"]
        case .tai: ["たい", "たく"]
        case .nai: ["ない", "なかった"]
        case .masu: ["ます", "ました", "ません"]
        case .te: ["てください", "でください", "てくれ", "て下さい"]
        case .kara: ["から"]
        case .kedo: ["けど", "けれど"]
        case .deshou: ["でしょう", "だろう", "でしょ"]
        case .tara: ["たら", "だら"]
        case .nakereba: ["なきゃ", "なければ", "なくちゃ", "ないと"]
        }
    }

    func matches(_ clip: Clip) -> Bool {
        clip.lines.contains { line in
            let text = line.text
            return needles.contains { text.contains($0) }
        }
    }
}

nonisolated enum WatchedFilter: String, CaseIterable, Identifiable, Sendable {
    case any, unwatched, watched
    var id: String { rawValue }
    var title: String {
        switch self {
        case .any: "All"
        case .unwatched: "Not watched"
        case .watched: "Watched"
        }
    }
}

/// Everything the Explore grid can be narrowed by.
nonisolated struct ExploreFilters: Equatable, Sendable {
    var difficulty: Difficulty?
    var grammar: ExploreGrammar?
    var topic: ClipCategory?
    var source: SourceType?
    var watched: WatchedFilter = .any

    init(difficulty: Difficulty? = nil) {
        self.difficulty = difficulty
    }

    var activeCount: Int {
        [difficulty != nil, grammar != nil, topic != nil, source != nil, watched != .any].filter { $0 }.count
    }

    func matches(_ clip: Clip, finishedClipIds: Set<String>) -> Bool {
        guard difficulty == nil || clip.difficultyKind == difficulty,
              topic == nil || clip.categoryKind == topic,
              source == nil || clip.categoryKind.sourceType == source else { return false }
        switch watched {
        case .any:
            break
        case .watched:
            guard finishedClipIds.contains(clip.id) else { return false }
        case .unwatched:
            guard !finishedClipIds.contains(clip.id) else { return false }
        }
        if let grammar, !grammar.matches(clip) { return false }
        return true
    }
}

struct ExploreFiltersSheet: View {
    @Binding var filters: ExploreFilters
    var lockedDifficulty: Difficulty?
    var lockTopic: Bool
    /// How many clips the draft would show, for the Apply button.
    let count: (ExploreFilters) -> Int
    var onApply: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var draft = ExploreFilters()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    if lockedDifficulty == nil {
                        section("Difficulty") {
                            chips(Difficulty.allCases, selected: draft.difficulty, title: \.rawValue) { draft.difficulty = $0 }
                        }
                    }
                    section("Grammar", caption: "Clips where this pattern is spoken") {
                        FlowLayout(spacing: 8, lineSpacing: 8) {
                            ForEach(ExploreGrammar.allCases) { g in
                                Button {
                                    Haptics.selection()
                                    draft.grammar = draft.grammar == g ? nil : g
                                } label: {
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(g.title).font(JojoFont.jp(15, bold: true, relativeTo: .subheadline))
                                        Text(g.gloss).font(.caption2)
                                            .foregroundStyle(draft.grammar == g ? Color.white.opacity(0.85) : .secondary)
                                    }
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .foregroundStyle(draft.grammar == g ? .white : .primary)
                                    .background(draft.grammar == g ? Color.jojoOrange : Color.fieldFill,
                                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .buttonStyle(PressableStyle())
                                .accessibilityAddTraits(draft.grammar == g ? .isSelected : [])
                            }
                        }
                    }
                    if !lockTopic {
                        section("Topic") {
                            FlowLayout(spacing: 8, lineSpacing: 8) {
                                ForEach(ClipCategory.allCases) { c in
                                    Button {
                                        Haptics.selection()
                                        draft.topic = draft.topic == c ? nil : c
                                    } label: {
                                        FilterChip(title: c.displayName, systemImage: c.symbol, isSelected: draft.topic == c)
                                    }
                                    .buttonStyle(PressableStyle())
                                }
                            }
                        }
                    }
                    section("Source") {
                        chips(SourceType.allCases, selected: draft.source, title: \.displayName) { draft.source = $0 }
                    }
                    section("Watched") {
                        Picker("Watched", selection: $draft.watched) {
                            ForEach(WatchedFilter.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .padding(Spacing.l)
            }
            .safeAreaInset(edge: .bottom) {
                let n = count(draft)
                HStack(spacing: Spacing.m) {
                    Button("Reset") {
                        Haptics.light()
                        withAnimation(.snappy) { draft = ExploreFilters(difficulty: lockedDifficulty) }
                    }
                    .font(.headline)
                    .foregroundStyle(Color.jojoOrange)
                    .frame(minWidth: 88, minHeight: 56)
                    .disabled(draft.activeCount == (lockedDifficulty == nil ? 0 : 1))

                    Button(n == 0 ? "No clips match" : "Apply · \(n) clip\(n == 1 ? "" : "s")") {
                        Haptics.medium()
                        filters = draft
                        dismiss()
                        onApply?()
                    }
                    .buttonStyle(PrimaryButtonStyle(isEnabled: n > 0))
                    .disabled(n == 0)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: n)
                }
                .padding(.horizontal, Spacing.l)
                .padding(.vertical, Spacing.s)
                .background(.bar)
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { draft = filters }
    }

    private func section<Content: View>(_ title: String, caption: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let caption {
                    Text(caption).font(.caption).foregroundStyle(.secondary)
                }
            }
            content()
        }
    }

    private func chips<T: Identifiable & Equatable>(_ values: [T], selected: T?, title: KeyPath<T, String>, set: @escaping (T?) -> Void) -> some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(values) { v in
                Button {
                    Haptics.selection()
                    set(selected == v ? nil : v)
                } label: {
                    FilterChip(title: v[keyPath: title], isSelected: selected == v)
                }
                .buttonStyle(PressableStyle())
            }
        }
    }
}
