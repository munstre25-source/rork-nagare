import SwiftUI

nonisolated struct ClipQuizQuestion: Identifiable, Sendable {
    var id: String { prompt + reveal }
    let prompt: String
    let options: [String]
    let correctIndex: Int
    let reveal: String
}

/// Builds 1–2 quick comprehension questions from a clip's tappable tokens.
nonisolated enum ClipQuizBuilder {
    static func questions(for clip: Clip, count: Int = 2) -> [ClipQuizQuestion] {
        let tokens = clip.lines.flatMap(\.tokens).filter {
            $0.tappable && !$0.definitions.isEmpty && $0.surface.count > 1
        }
        guard !tokens.isEmpty else { return [] }
        var pool = tokens.shuffled()
        var out: [ClipQuizQuestion] = []
        var used = Set<String>()

        while out.count < count, let token = pool.popLast() {
            guard used.insert(token.surface).inserted else { continue }
            let correct = token.definitions.first ?? token.surface
            var distractors = tokens
                .filter { $0.surface != token.surface }
                .compactMap(\.definitions.first)
            distractors = Array(Set(distractors).subtracting([correct])).shuffled()
            while distractors.count < 3 {
                distractors.append(contentsOf: ["to go", "friend", "today", "delicious", "school"].shuffled())
                distractors = Array(Set(distractors).subtracting([correct]))
            }
            var options = Array(distractors.prefix(3)) + [correct]
            options.shuffle()
            guard let correctIndex = options.firstIndex(of: correct) else { continue }
            out.append(ClipQuizQuestion(
                prompt: "What does \(token.surface) mean?",
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
                        .foregroundStyle(.white)
                    Spacer()
                    Button("Skip") {
                        Haptics.selection()
                        onFinished()
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                    .frame(minHeight: 44)
                }
                if questions.isEmpty {
                    ProgressView().tint(.white)
                } else if index >= questions.count {
                    done
                } else {
                    questionCard(questions[index])
                }
            }
            .padding(Spacing.l)
            .frame(maxWidth: 420)
            .background(Color.bgElevatedDark, in: RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous))
            .padding(Spacing.l)
        }
        .onAppear {
            questions = ClipQuizBuilder.questions(for: clip)
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
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
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
                            .font(.body.weight(.medium))
                            .foregroundStyle(.white)
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
        guard let selected else { return Color.white.opacity(0.08) }
        if i == correct { return Color.spokenGreen.opacity(0.35) }
        if i == selected { return Color.againBackground.opacity(0.35) }
        return Color.white.opacity(0.06)
    }

    private var done: some View {
        VStack(spacing: Spacing.m) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.jojoOrange)
            Text("\(correctCount)/\(questions.count) correct")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
            Text("Nice — keep scrolling.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.65))
            Button {
                track("clip_quiz_done", props: ["clip": clip.id, "correct": String(correctCount)])
                onFinished()
            } label: {
                Text("Next clip")
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .foregroundStyle(.white)
                    .background(Color.jojoOrange, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
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
