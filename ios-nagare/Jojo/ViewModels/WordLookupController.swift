import Foundation
import Observation

nonisolated enum PopupTab: Int, CaseIterable, Sendable {
    case dictionary, flashcard, examples

    var symbol: String {
        switch self {
        case .dictionary: "book.closed"
        case .flashcard: "rectangle.on.rectangle"
        case .examples: "text.alignleft"
        }
    }

    var title: String {
        switch self {
        case .dictionary: "Dictionary"
        case .flashcard: "Flashcard preview"
        case .examples: "Example sentences"
        }
    }

    var compactTitle: String {
        switch self {
        case .dictionary: "Dictionary"
        case .flashcard: "Card"
        case .examples: "Examples"
        }
    }
}

/// Drives the tap-to-understand popup. The tap itself saves the word; there is no save button.
@Observable
@MainActor
final class WordLookupController {
    struct Selection: Equatable {
        let clip: Clip
        let lineIndex: Int
        let tokenIndex: Int
        let token: Token
        var sentence: String { clip.lines[safe: lineIndex]?.text ?? token.surface }
        var translation: String { clip.lines[safe: lineIndex]?.translation ?? "" }
    }

    private(set) var selection: Selection?
    private(set) var explanation: WordExplanation?
    private(set) var occurrenceCount: Int = 0
    private(set) var context: ContextExplanation?
    private(set) var isLoadingContext = false
    private(set) var isLoadingMeaning = false
    var tab: PopupTab = .dictionary
    /// Bumps on every tap so the badge can animate.
    private(set) var tapPulse: Int = 0
    /// When true (onboarding demo), never touches the network.
    @ObservationIgnored var offlineOnly = false
    /// When true (sneak peek), show the popup without saving words to Vocab.
    @ObservationIgnored var previewOnly = false

    @ObservationIgnored private var lookupTask: Task<Void, Never>?
    @ObservationIgnored private var contextTask: Task<Void, Never>?

    var isPresented: Bool { selection != nil }

    func isSelected(clipId: String, lineIndex: Int, tokenIndex: Int) -> Bool {
        guard let selection else { return false }
        return selection.clip.id == clipId && selection.lineIndex == lineIndex && selection.tokenIndex == tokenIndex
    }

    func select(token: Token, tokenIndex: Int, lineIndex: Int, clip: Clip, app: AppModel) {
        guard token.tappable else { return }
        Haptics.light()
        lookupTask?.cancel()
        isLoadingMeaning = false
        let newSelection = Selection(clip: clip, lineIndex: lineIndex, tokenIndex: tokenIndex, token: token)
        let sameMoment = selection?.token.surface == token.surface && selection?.sentence == newSelection.sentence
        selection = newSelection
        if !sameMoment {
            tab = .dictionary
            context = nil
            contextTask?.cancel()
            isLoadingContext = false
        }
        let instant = app.localWordExplanation(for: token, sentence: newSelection.sentence) ?? .fallback(for: token)
        explanation = instant
        if previewOnly {
            occurrenceCount = 1
        } else {
            occurrenceCount = app.recordTap(token: token, explanation: instant, clip: clip, lineIndex: lineIndex)
        }
        tapPulse += 1
        if !previewOnly {
            track("word_tapped", props: ["word": token.surface, "count": String(occurrenceCount)])
        }

        loadContextIfNeeded(app: app)
        guard instant.source == .fallback, !offlineOnly, !previewOnly else { return }
        isLoadingMeaning = true
        let service = app.explainService
        let userId = app.purchases.appUserId
        let sentence = newSelection.sentence
        lookupTask = Task { [weak self, weak app] in
            let outcome = await service.lookup(token: token, sentence: sentence, appUserId: userId)
            guard !Task.isCancelled, let self, self.selection == newSelection else { return }
            self.isLoadingMeaning = false
            self.explanation = outcome.explanation
            app?.persistCache(outcome.newCache)
            app?.updateDefinitions(for: token, with: outcome.explanation)
            if self.context?.isFallback == true, let app {
                self.context = Self.offlineContext(for: newSelection, app: app)
            }
        }
    }

    func loadContextIfNeeded(app: AppModel) {
        guard let selection, context == nil, !isLoadingContext else { return }
        let fallback = Self.offlineContext(for: selection, app: app)
        context = fallback
        if !previewOnly {
            app.rememberContext(fallback.contextualExplanation, token: selection.token, preferExisting: true)
        }
        if offlineOnly || previewOnly { return }
        isLoadingContext = true
        let service = app.explainService
        let userId = app.purchases.appUserId
        contextTask = Task { [weak self, weak app] in
            let outcome = await service.context(token: selection.token, sentence: selection.sentence, appUserId: userId, fallback: fallback)
            guard let self, !Task.isCancelled, self.selection == selection else { return }
            self.isLoadingContext = false
            if !outcome.context.isFallback {
                self.context = outcome.context
                app?.rememberContext(outcome.context.contextualExplanation, token: selection.token, preferExisting: false)
            }
            app?.persistCache(outcome.newCache)
        }
    }

    func retryContext(app: AppModel) {
        contextTask?.cancel()
        context = nil
        isLoadingContext = false
        loadContextIfNeeded(app: app)
    }

    func dismiss() {
        lookupTask?.cancel()
        contextTask?.cancel()
        isLoadingContext = false
        isLoadingMeaning = false
        selection = nil
        explanation = nil
        context = nil
    }

    /// Graceful offline "context" built from local data: the real sentence plus other clips using the same word.
    static func offlineContext(for selection: Selection, app: AppModel) -> ContextExplanation {
        let token = selection.token
        let base = token.dictionaryForm
        var examples: [String] = []
        for clip in app.clipsMentioning(base, limit: 8) {
            for line in clip.lines where line.tokens.contains(where: { $0.dictionaryForm == base }) {
                let entry = "\(line.text)\n\(line.translation)"
                if line.text != selection.sentence, !examples.contains(entry) { examples.append(entry) }
                if examples.count == 3 { break }
            }
            if examples.count == 3 { break }
        }
        let meaning = app.localWordExplanation(for: token, sentence: selection.sentence)
        let gloss = meaning?.definitions.first ?? meaning?.jaDefinitions.first
        let reading = token.reading ?? token.baseReading
        let named: String
        if let reading, !reading.isEmpty {
            named = "\(token.surface) (\(reading))"
        } else {
            named = token.surface
        }
        var explanation = gloss.map { "Saved meaning of \(named): \($0)." }
            ?? "A definition for \(named) isn't saved on this device yet."
        if !selection.translation.isEmpty {
            explanation += " Saved sentence translation: \(selection.translation)"
        }
        if token.baseForm != nil {
            explanation += " \(token.surface) is a form of \(base)."
        }
        if let formality = token.formality {
            explanation += " It sounds \(formality)."
        }
        let relatedUnique = app.relatedForms(pos: token.pos, jlpt: token.jlpt, excluding: base)
        return ContextExplanation(
            contextualExplanation: explanation,
            examples: Array(examples.prefix(3)),
            relatedWords: Array(relatedUnique),
            isFallback: true
        )
    }
}
