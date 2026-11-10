import Foundation
import Observation

nonisolated enum PopupTab: Int, CaseIterable, Sendable {
    case dictionary, ai, flashcard, examples

    var symbol: String {
        switch self {
        case .dictionary: "book.closed"
        case .ai: "bubble.left.and.bubble.right.fill"
        case .flashcard: "rectangle.on.rectangle"
        case .examples: "text.alignleft"
        }
    }

    var title: String {
        switch self {
        case .dictionary: "Dictionary"
        case .ai: "Ask Jojo"
        case .flashcard: "Flashcard preview"
        case .examples: "Example sentences"
        }
    }

    var compactTitle: String {
        switch self {
        case .dictionary: "Meaning"
        case .ai: "Jojo"
        case .flashcard: "Card"
        case .examples: "Examples"
        }
    }
}

/// Drives the tap-to-understand popup. The tap itself saves the word; there is no save button.
@Observable
@MainActor
final class WordLookupController {
    struct AskMessage: Identifiable, Equatable {
        let id = UUID()
        let fromLearner: Bool
        let text: String
        var failed = false
    }

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
    /// Ask Jojo thread for the current word; cleared when a new word is tapped.
    private(set) var askThread: [AskMessage] = []
    private(set) var isAsking = false
    @ObservationIgnored private var askTask: Task<Void, Never>?
    /// Bumps on every tap so the badge can animate.
    private(set) var tapPulse: Int = 0
    /// When true (onboarding demo), never touches the network.
    @ObservationIgnored var offlineOnly = false
    /// When true (sneak peek), show the popup without saving words to Vocab.
    @ObservationIgnored var previewOnly = false
    /// Particles / auxiliaries open without auto-saving; the card offers an explicit Save.
    private(set) var deferredSave = false

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
            askTask?.cancel()
            askThread = []
            isAsking = false
        }
        let instant = app.localWordExplanation(for: token, sentence: newSelection.sentence) ?? .fallback(for: token)
        explanation = instant
        let grammarOnly = GrammarFormNotes.isGrammarOnly(token)
        deferredSave = false
        if previewOnly {
            occurrenceCount = 1
        } else if grammarOnly, app.wordState(for: token) == nil {
            // Preview first — learner taps Save if they want it in Vocab.
            deferredSave = true
            occurrenceCount = 0
        } else {
            occurrenceCount = app.recordTap(token: token, explanation: instant, clip: clip, lineIndex: lineIndex)
        }
        tapPulse += 1
        if !previewOnly && !deferredSave {
            track("word_tapped", props: ["word": token.surface, "count": String(occurrenceCount)])
        }

        // Context starts offline. Only the Examples tab upgrades it remotely; Ask Jojo
        // spends a call only after the learner actually sends a question.
        if context == nil {
            context = Self.offlineContext(for: newSelection, app: app)
        }
        guard !instant.hasMeaning, !offlineOnly, !previewOnly else { return }
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

    /// Explicit Save for particles / auxiliaries that opened in preview.
    func saveDeferred(app: AppModel) {
        guard deferredSave, let selection, let explanation else { return }
        occurrenceCount = app.recordTap(
            token: selection.token,
            explanation: explanation,
            clip: selection.clip,
            lineIndex: selection.lineIndex
        )
        deferredSave = false
        tapPulse += 1
        track("word_tapped", props: ["word": selection.token.surface, "count": String(occurrenceCount), "deferred": "1"])
    }

    func loadContextIfNeeded(app: AppModel) {
        guard let selection, !isLoadingContext else { return }
        if context == nil {
            let fallback = Self.offlineContext(for: selection, app: app)
            context = fallback
            if !previewOnly && !deferredSave {
                app.rememberContext(fallback.contextualExplanation, token: selection.token, preferExisting: true)
            }
        }
        // Ask Jojo already makes a focused request when the learner sends a question.
        // Do not spend a second context call merely for opening that tab.
        guard tab == .examples else { return }
        guard context?.isFallback != false else { return }
        if offlineOnly || previewOnly { return }
        isLoadingContext = true
        let fallback = context ?? Self.offlineContext(for: selection, app: app)
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

    /// Sends one Ask Jojo question. A small per-word cap complements persistent caching
    /// and the backend daily limit without silently swallowing feedback.
    func ask(_ question: String, app: AppModel) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let selection, !trimmed.isEmpty, !isAsking else { return }
        guard askThread.filter(\.fromLearner).count < 4 else {
            askThread.append(AskMessage(fromLearner: false, text: "You've reached four questions for this word. Try its examples or tap another word to keep exploring.", failed: true))
            return
        }
        askThread.append(AskMessage(fromLearner: true, text: trimmed))
        guard !offlineOnly, !previewOnly else {
            askThread.append(AskMessage(fromLearner: false, text: "Ask Jojo works once you're in the app.", failed: true))
            return
        }
        isAsking = true
        let service = app.explainService
        let userId = app.purchases.appUserId
        track("ask_jojo", props: ["word": selection.token.surface])
        askTask = Task { [weak self, weak app] in
            let outcome = await service.ask(token: selection.token, sentence: selection.sentence, question: trimmed, appUserId: userId)
            guard let self, !Task.isCancelled, self.selection == selection else { return }
            self.isAsking = false
            switch outcome {
            case .answer(let answer, let newCache):
                app?.persistCache(newCache)
                self.askThread.append(AskMessage(fromLearner: false, text: answer))
                Haptics.light()
            case .failure(let message):
                self.askThread.append(AskMessage(fromLearner: false, text: message, failed: true))
            }
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
        askTask?.cancel()
        askThread = []
        isAsking = false
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
            ?? "「\(named)」 appears in this clip."
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
