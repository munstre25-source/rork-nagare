import SwiftUI

/// Multi-select motivation.
struct MotivationStepView: View {
    let onContinue: () -> Void
    @Environment(AppModel.self) private var app
    @State private var selected: Set<String> = []

    var body: some View {
        VStack(spacing: Spacing.l) {
            ScrollView {
                VStack(spacing: Spacing.m) {
                    MascotCoach(message: coachMessage)
                        .padding(.bottom, Spacing.xs)
                    OnboardingTitle(title: "What's pulling you toward Japanese?", subtitle: "Pick as many as you like.")
                        .padding(.bottom, Spacing.s)
                    ForEach(Motivation.allCases) { m in
                        Button {
                            Haptics.selection()
                            if selected.contains(m.rawValue) { selected.remove(m.rawValue) } else { selected.insert(m.rawValue) }
                            track("onboarding_motivation_selected", props: ["value": m.rawValue])
                        } label: {
                            OptionCard(title: m.title, symbol: m.symbol, isSelected: selected.contains(m.rawValue))
                        }
                        .buttonStyle(PressableStyle())
                    }
                }
                .padding(.horizontal, Spacing.l)
                .padding(.top, Spacing.l)
            }
            Button("Continue") { save(Array(selected)) }
                .buttonStyle(PrimaryButtonStyle(isEnabled: !selected.isEmpty))
                .disabled(selected.isEmpty)
                .padding(.horizontal, Spacing.l)
        }
        .onAppear { selected = Set(app.profile.motivations) }
    }

    private var coachMessage: String {
        app.profile.firstName.isEmpty
        ? "Tell me why you're here and I'll pick clips to match."
        : "Tell me why you're here, \(app.profile.firstName), and I'll pick clips to match."
    }

    private func save(_ values: [String]) {
        Haptics.light()
        app.profile.motivations = values
        app.save()
        app.assignFirstClip()
        onContinue()
    }
}

/// Tinder-style swipe stack of genres.
struct TasteSwipeStepView: View {
    let onContinue: () -> Void
    @Environment(AppModel.self) private var app
    @State private var index: Int = 0
    @State private var liked: [String] = []
    @State private var disliked: [String] = []
    @State private var drag: CGSize = .zero
    @State private var didRestore = false

    private let tastes = Taste.allCases

    var body: some View {
        VStack(spacing: Spacing.l) {
            OnboardingTitle(title: "Swipe what you're into.", subtitle: "Right for interested, left for not for me.")
                .padding(.horizontal, Spacing.l)
                .padding(.top, Spacing.l)
            ZStack {
                if index >= tastes.count {
                    VStack(spacing: Spacing.m) {
                        JojoMascot(height: 150, pose: .wave)
                        Text("Your feed is tuned.")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                            .foregroundStyle(Color.white)
                        Text(summary)
                            .font(.subheadline)
                            .foregroundStyle(Color.white.opacity(0.7))
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .transition(.scale.combined(with: .opacity))
                } else {
                    ForEach(Array(tastes.enumerated()).reversed(), id: \.element) { i, taste in
                        if i >= index && i < index + 3 {
                            TasteCard(taste: taste, drag: i == index ? drag : .zero)
                                .scaleEffect(1 - CGFloat(i - index) * 0.05)
                                .offset(y: CGFloat(i - index) * 14)
                                .offset(i == index ? drag : .zero)
                                .rotationEffect(.degrees(i == index ? Double(drag.width / 18) : 0))
                                .allowsHitTesting(i == index)
                                .gesture(i == index ? swipeGesture : nil)
                                .accessibilityAction(named: "Interested") { decide(like: true) }
                                .accessibilityAction(named: "Not for me") { decide(like: false) }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, Spacing.xl)

            if index < tastes.count {
                HStack(spacing: Spacing.xxl) {
                    swipeButton(symbol: "xmark", color: .jojoInkSoft, label: "Not for me") { decide(like: false) }
                    swipeButton(symbol: "heart.fill", color: .jojoVermilion, label: "Interested") { decide(like: true) }
                }
                .padding(.bottom, Spacing.m)
            } else {
                VStack(spacing: Spacing.m) {
                    feedPreview
                    Button("Continue") {
                        persistTastes()
                        onContinue()
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    Button("Swipe again") { restart() }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(0.8))
                        .frame(minHeight: 44)
                }
                .padding(.horizontal, Spacing.l)
                .padding(.bottom, Spacing.m)
            }
        }
        .onAppear(perform: restore)
    }

    private var feedPreview: some View {
        let clips = Array(app.forYouClips.prefix(3))
        return VStack(alignment: .leading, spacing: 8) {
            if clips.isEmpty {
                Text("We'll keep looking for clips in this lane.")
                    .font(.subheadline)
                    .foregroundStyle(Color.white.opacity(0.7))
            } else {
                ForEach(clips) { clip in
                    HStack(spacing: 10) {
                        Image(systemName: clip.categoryKind.symbol)
                            .foregroundStyle(Color.sakuraPinkLight)
                            .frame(width: 28)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(clip.title)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(clip.categoryKind.displayName)
                                .font(.caption)
                                .foregroundStyle(Color.white.opacity(0.65))
                                .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var swipeGesture: some Gesture {
        DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { value in
                if abs(value.translation.width) > 110 || abs(value.predictedEndTranslation.width) > 260 {
                    decide(like: value.translation.width > 0)
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { drag = .zero }
                }
            }
    }

    private func swipeButton(symbol: String, color: Color, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(color)
                .frame(width: 68, height: 68)
                .background(Color.jojoPaper, in: Circle())
                .overlay(Circle().strokeBorder(Color.jojoPaperStroke, lineWidth: 1))
                .shadow(color: Color.jojoVermilion.opacity(0.1), radius: 12, y: 5)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }

    private var summary: String {
        if !liked.isEmpty {
            let names = liked.compactMap { Taste(rawValue: $0)?.title }.prefix(2).joined(separator: " & ")
            return "Your feed opens on \(names)."
        }
        let fromWhy = app.profile.motivations.compactMap { Motivation(rawValue: $0)?.title }.prefix(2)
        if !fromWhy.isEmpty {
            return "You passed the cards, so your feed follows why you're here."
        }
        return "Tell me one thing you're into and the feed will follow it."
    }

    private func restore() {
        guard !didRestore else { return }
        didRestore = true
        liked = app.profile.tastesLiked
        disliked = app.profile.tastesDisliked
        index = min(tastes.count, liked.count + disliked.count)
    }

    private func restart() {
        liked = []
        disliked = []
        index = 0
        drag = .zero
        persistTastes()
    }

    private func persistTastes() {
        app.profile.tastesLiked = liked
        app.profile.tastesDisliked = disliked
        app.save()
        app.assignFirstClip()
    }

    private func decide(like: Bool) {
        guard let taste = tastes[safe: index] else { return }
        like ? Haptics.medium() : Haptics.light()
        if like { liked.append(taste.rawValue) } else { disliked.append(taste.rawValue) }
        persistTastes()
        track("onboarding_taste_swiped", props: ["taste": taste.rawValue, "liked": like ? "1" : "0"])
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            drag = CGSize(width: like ? 600 : -600, height: drag.height)
        }
        Task {
            try? await Task.sleep(for: .milliseconds(180))
            drag = .zero
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { index += 1 }
        }
    }
}

private struct TasteCard: View {
    let taste: Taste
    let drag: CGSize

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(colors: taste.gradient.map { Color(hex: $0) }, startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: taste.symbol)
                .font(.system(size: 120, weight: .light))
                .foregroundStyle(.white.opacity(0.18))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            LinearGradient(colors: [.clear, .black.opacity(0.6)], startPoint: .center, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 4) {
                Text(taste.title).font(.system(.title, design: .rounded, weight: .bold)).foregroundStyle(.white)
                Text(taste.subtitle).font(.headline).foregroundStyle(.white.opacity(0.8))
            }
            .padding(Spacing.xl)
        }
        .overlay(alignment: .topLeading) {
            stamp("INTO IT", color: .jojoOrangeLight).opacity(Double(max(0, drag.width) / 100)).padding(Spacing.xl)
        }
        .overlay(alignment: .topTrailing) {
            stamp("PASS", color: .white).opacity(Double(max(0, -drag.width) / 100)).padding(Spacing.xl)
        }
        .frame(maxWidth: 380, maxHeight: 440)
        .clipShape(.rect(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.jojoVermilion.opacity(0.18), radius: 22, y: 12)
        .accessibilityElement(children: .combine)
    }

    private func stamp(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(.title2, design: .rounded, weight: .heavy))
            .foregroundStyle(color)
            .padding(.horizontal, 12).padding(.vertical, 6)
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(color, lineWidth: 3))
            .rotationEffect(.degrees(-10))
    }
}

/// "Which of these can you read comfortably?"
struct LevelStepView: View {
    let onContinue: () -> Void
    @Environment(AppModel.self) private var app
    @State private var selected: ReadingLevel?

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.m) {
                OnboardingTitle(title: "Which of these can you read comfortably?",
                                subtitle: "Tap the hardest one. No wrong answers, we'll adjust as you go.")
                    .padding(.bottom, Spacing.s)
                levelCard(.beginner, label: "Beginner", words: [
                    .init(surface: "こんにちは", romaji: "konnichiwa")
                ], translation: "Hello")
                levelCard(.intermediate, label: "Intermediate", words: [
                    .init(surface: "明日", furigana: "あした", romaji: "ashita"),
                    .init(surface: "友達", furigana: "ともだち", romaji: "tomodachi"),
                    .init(surface: "と", romaji: "to"),
                    .init(surface: "映画", furigana: "えいが", romaji: "eiga"),
                    .init(surface: "を", romaji: "o"),
                    .init(surface: "見", furigana: "み", romaji: "mi"),
                    .init(surface: "ます", romaji: "masu")
                ], translation: "I'll watch a movie with a friend tomorrow.")
                levelCard(.advanced, label: "Advanced", words: [
                    .init(surface: "曖昧"), .init(surface: "な"), .init(surface: "返事"), .init(surface: "を"),
                    .init(surface: "繰り返す"), .init(surface: "と"), .init(surface: "、"), .init(surface: "信頼"),
                    .init(surface: "を"), .init(surface: "損なう"), .init(surface: "恐れ"), .init(surface: "が"), .init(surface: "ある")
                ], translation: "Repeating vague replies risks damaging trust.", underline: false)
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.l)
        }
    }

    private func levelCard(_ level: ReadingLevel, label: String, words: [StaticSentence.Word], translation: String, underline: Bool = true) -> some View {
        let isSelected = selected == level
        return Button {
            Haptics.medium()
            selected = level
            app.profile.level = level.rawValue
            app.save()
            app.assignFirstClip()
            track("onboarding_level_selected", props: ["level": level.rawValue])
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                onContinue()
            }
        } label: {
            VStack(alignment: .leading, spacing: Spacing.m) {
                Text(label.uppercased())
                    .font(.caption.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(isSelected ? Color.white : Color.jojoVermilion)
                StaticSentence(
                    words: words,
                    size: level == .advanced ? 20 : 24,
                    showsUnderline: underline,
                    surface: isSelected ? .cinema : .cream
                )
                Text(translation)
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.jojoInkSoft)
            }
            .padding(Spacing.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous)
                    .fill(
                        isSelected
                        ? AnyShapeStyle(LinearGradient(colors: [Color.jojoOrange, Color.jojoVermilion], startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(Color.jojoPaper)
                    )
            }
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sheet, style: .continuous)
                    .strokeBorder(isSelected ? .clear : Color.jojoPaperStroke, lineWidth: 1)
            )
            .shadow(color: Color.jojoVermilion.opacity(isSelected ? 0.22 : 0.06), radius: 14, y: 6)
            .animation(.snappy, value: isSelected)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(label): \(translation)")
    }
}
