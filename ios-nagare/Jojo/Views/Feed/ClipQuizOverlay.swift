import SwiftUI

nonisolated struct ClipQuizQuestion: Identifiable, Sendable {
    var id: String { prompt + reveal }
    let prompt: String
    let options: [String]
    let correctIndex: Int
    let reveal: String
    var promptIsJapanese: Bool = false
    var optionsAreJapanese: Bool = false
}

/// Builds a check of the line the learner just heard, then a word only if the clip is a single line.
nonisolated enum ClipQuizBuilder {
    static func questions(for clip: Clip, count: Int = 2, skipping: Set<String> = []) -> [ClipQuizQuestion] {
        var out: [ClipQuizQuestion] = []
        let lines = clip.lines.filter {
            !$0.translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.text.count > 1
        }
        if lines.count >= 2 {
            let pool = lines.shuffled()
            if let line = pool.first {
                var options = unique([line.translation] + pool.map(\.translation)).prefix(4)
                var choices = Array(options)
                if !choices.contains(line.translation) { choices.append(line.translation) }
                choices.shuffle()
                if let correctIndex = choices.firstIndex(of: line.translation) {
                    out.append(ClipQuizQuestion(
                        prompt: line.text,
                        options: choices,
                        correctIndex: correctIndex,
                        reveal: line.translation,
                        promptIsJapanese: true
                    ))
                }
            }
            if let line = pool.dropFirst().first {
                var choices = Array(unique([line.text] + pool.map(\.text)).prefix(4))
                if !choices.contains(line.text) { choices.append(line.text) }
                choices.shuffle()
                if let correctIndex = choices.firstIndex(of: line.text) {
                    out.append(ClipQuizQuestion(
                        prompt: "Which line means “\(line.translation)”?",
                        options: choices,
                        correctIndex: correctIndex,
                        reveal: line.text,
                        optionsAreJapanese: true
                    ))
                }
            }
        }
        if out.count < count {
            out.append(contentsOf: wordQuestions(for: clip, limit: count - out.count, skipping: skipping))
        }
        return Array(out.prefix(count))
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func wordQuestions(for clip: Clip, limit: Int, skipping: Set<String>) -> [ClipQuizQuestion] {
        let tokens = clip.lines.flatMap(\.tokens).filter {
            $0.tappable && !$0.definitions.isEmpty && $0.surface.count > 1 && !skipping.contains($0.surface)
        }
        guard !tokens.isEmpty else { return [] }
        var pool = tokens.shuffled()
        var out: [ClipQuizQuestion] = []
        var used = Set<String>()
        while out.count < limit, let token = pool.popLast() {
            guard used.insert(token.surface).inserted else { continue }
            let line = clip.lines.first { $0.tokens.contains { $0.surface == token.surface } }
            let correct = token.definitions.first ?? token.surface
            var distractors = tokens
                .filter { $0.surface != token.surface }
                .compactMap(\.definitions.first)
            distractors = Array(Set(distractors).subtracting([correct])).shuffled()
            while distractors.count < 3 {
                distractors.append(contentsOf: ["to go", "friend", "today", "delicious", "school"])
                distractors = Array(Set(distractors).subtracting([correct]))
            }
            var options = Array(distractors.prefix(3)) + [correct]
            options.shuffle()
            guard let correctIndex = options.firstIndex(of: correct) else { continue }
            let prompt = line.map { "In 「\($0.text)」, what does \(token.surface) mean?" } ?? "What does \(token.surface) mean?"
            out.append(ClipQuizQuestion(
                prompt: prompt,
                options: options,
                correctIndex: correctIndex,
                reveal: "\(token.surface) · \(correct)"
            ))
        }
        return out
    }
}

/// End-of-clip micro-quiz overlay. Skip or finish to continue the feed.
struct ClipQuizOverlay: View {
    let clip: Clip
    let onFinished: () -> Void

    @Environment(AppModel.self) private var app
    @State private var questions: [ClipQuizQuestion] = []
    @State private var index: Int = 0
    @State private var selected: Int?
    @State private var correctCount: Int = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: Spacing.l) {
                HStack {
                    Text("Quick check")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    Button("Skip") {
                        Haptics.selection()
                        onFinished()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(minHeight: 44)
                }
                if questions.isEmpty {
                    ProgressView().tint(Color.jojoOrange)
                } else if index >= questions.count {
                    done
                } else {
                    questionCard(questions[index])
                }
            }
            .padding(Spacing.l)
            .frame(maxWidth: 420)
            .background(Color.card, in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
            .padding(Spacing.l)
        }
        .onAppear {
            let known = Set(clip.lines.flatMap(\.tokens).filter { app.wordState(for: $0) == .known }.map(\.surface))
            questions = ClipQuizBuilder.questions(for: clip, skipping: known)
            if questions.isEmpty { onFinished() }
            track("clip_quiz_shown", props: ["clip": clip.id, "q": String(questions.count)])
        }
    }

    private func questionCard(_ q: ClipQuizQuestion) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Text("\(index + 1)/\(questions.count)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.jojoOrange)
            Text(q.prompt)
                .font(q.promptIsJapanese ? JojoFont.jp(22, bold: true, relativeTo: .title3) : .title3.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(4)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Array(q.options.enumerated()), id: \.offset) { i, option in
                Button {
                    guard selected == nil else { return }
                    selected = i
                    let good = i == q.correctIndex
                    if good { correctCount += 1 }
                    Haptics.success()
                    Task {
                        try? await Task.sleep(for: .milliseconds(700))
                        withAnimation(.snappy) {
                            selected = nil
                            index += 1
                        }
                    }
                } label: {
                    HStack {
                        Text(option)
                            .font(q.optionsAreJapanese ? JojoFont.jp(16, relativeTo: .body) : .body.weight(.medium))
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        if let selected {
                            if i == q.correctIndex {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.spokenGreen)
                            } else if i == selected {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(Color.againText)
                            }
                        }
                    }
                    .padding(Spacing.m)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                    .background(optionBackground(i, correct: q.correctIndex), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(selected != nil)
            }
        }
    }

    private func optionBackground(_ i: Int, correct: Int) -> Color {
        guard let selected else { return Color.fieldFill }
        if i == correct { return Color.spokenGreen.opacity(0.35) }
        if i == selected { return Color.againBackground.opacity(0.35) }
        return Color.fieldFill.opacity(0.6)
    }

    private var done: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.jojoOrange)
            Text("\(correctCount)/\(questions.count) correct")
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
            Text("Nice — keep scrolling.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button {
                track("clip_quiz_done", props: ["clip": clip.id, "correct": String(correctCount)])
                onFinished()
            } label: {
                Text("Next clip")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(.white)
                    .background(Color.sakuraButton, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .padding(.top, Spacing.s)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            // Auto-advance if they already finished answering.
            Task {
                try? await Task.sleep(for: .milliseconds(1200))
                onFinished()
            }
        }
    }
}
