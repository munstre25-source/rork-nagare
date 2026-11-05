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
                    OnboardingTitle(title: "Why are you learning Japanese?", subtitle: "Pick as many as you like.", accent: "Japanese")
                        .padding(.bottom, Spacing.s)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: Spacing.m), GridItem(.flexible(), spacing: Spacing.m)], spacing: Spacing.m) {
                        ForEach(Motivation.allCases) { m in
                            Button {
                                Haptics.selection()
                                if selected.contains(m.rawValue) { selected.remove(m.rawValue) } else { selected.insert(m.rawValue) }
                                track("onboarding_motivation_selected", props: ["value": m.rawValue])
                            } label: {
                                ChoiceTile(symbol: m.symbol, title: m.shortTitle, isSelected: selected.contains(m.rawValue))
                            }
                            .buttonStyle(PressableStyle())
                        }
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
        app.updateOnboardingPreferences(motivations: values)
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
    @State private var isDeciding = false

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
                            .foregroundStyle(Color.sakuraPink)
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
                .shadow(color: Color.black.opacity(0.1), radius: 12, y: 5)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(label)
    }

    private var summary: String {
        if !liked.isEmpty {
            let names = liked.compactMap { Taste(rawValue: $0)?.title }.prefix(2).joined(separator: " & ")
            return "We’ll prioritize \(names) at your level."
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
        app.updateOnboardingPreferences(liked: liked, disliked: disliked)
    }

    private func decide(like: Bool) {
        guard !isDeciding, let taste = tastes[safe: index] else { return }
        isDeciding = true
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
            isDeciding = false
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
        .shadow(color: Color.black.opacity(0.16), radius: 22, y: 12)
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

/// Five-step self assessment with signal bars. Auto-advances.
struct LevelStepView: View {
    let onContinue: () -> Void
    @Environment(AppModel.self) private var app
    @State private var selected: SelfLevel?
    @State private var continuationTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(spacing: Spacing.m) {
                MascotCoach(message: "No pressure. I'll pick clips that stretch you just a little.")
                    .padding(.bottom, Spacing.xs)
                OnboardingTitle(title: "How much Japanese do you know?", accent: "Japanese")
                    .padding(.bottom, Spacing.s)
                ForEach(SelfLevel.allCases) { level in
                    row(level)
                }
                Label("You can change this anytime in Settings", systemImage: "slider.horizontal.3")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color.white.opacity(0.75))
                    .padding(.horizontal, Spacing.m)
                    .padding(.vertical, Spacing.s)
                    .background(Color.white.opacity(0.1), in: Capsule())
                    .padding(.top, Spacing.s)
            }
            .padding(.horizontal, Spacing.l)
            .padding(.vertical, Spacing.l)
        }
        .onAppear {
            let saved = UserDefaults.standard.object(forKey: OnboardingPrefs.selfLevelKey) as? Int
            if let saved, let level = SelfLevel(rawValue: saved) { selected = level }
        }
        .onDisappear { continuationTask?.cancel() }
    }

    private func row(_ level: SelfLevel) -> some View {
        let isSelected = selected == level
        return Button {
            Haptics.medium()
            selected = level
            UserDefaults.standard.set(level.rawValue, forKey: OnboardingPrefs.selfLevelKey)
            UserDefaults.standard.set(level.jlpt.rawValue, forKey: PlayerPrefs.jlptLevelKey)
            app.updateOnboardingPreferences(level: level.readingLevel)
            track("onboarding_level_selected", props: ["level": level.readingLevel.rawValue, "step": String(level.rawValue)])
            continuationTask?.cancel()
            continuationTask = Task {
                do { try await Task.sleep(for: .milliseconds(380)) } catch { return }
                guard !Task.isCancelled else { return }
                onContinue()
            }
        } label: {
            HStack(spacing: Spacing.m) {
                SignalBars(filled: level.rawValue + 1, highlighted: isSelected)
                    .frame(width: 44, height: 44)
                    .background(isSelected ? Color.white.opacity(0.22) : Color.white.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(level.title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Text(level.subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.white.opacity(isSelected ? 0.88 : 0.65))
                }
                Spacer(minLength: 0)
                Text(level.jlpt.rawValue)
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(isSelected ? .white : Color.sakuraPink)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(isSelected ? Color.white.opacity(0.22) : Color.sakuraPink.opacity(0.14), in: Capsule())
            }
            .padding(Spacing.m)
            .frame(minHeight: 72)
            .background {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(isSelected
                          ? AnyShapeStyle(LinearGradient(colors: [Color.jojoOrange, Color.jojoVermilion], startPoint: .topLeading, endPoint: .bottomTrailing))
                          : AnyShapeStyle(Color.white.opacity(0.08)))
            }
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(isSelected ? .clear : Color.white.opacity(0.12), lineWidth: 1))
            .animation(.snappy, value: isSelected)
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("\(level.title). \(level.subtitle)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Five ascending bars, `filled` of them lit.
struct SignalBars: View {
    let filled: Int
    var highlighted: Bool = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(0..<5, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(i < filled ? (highlighted ? Color.white : Color.sakuraPink) : Color.white.opacity(0.2))
                    .frame(width: 4, height: 6 + CGFloat(i) * 4)
            }
        }
        .accessibilityHidden(true)
    }
}
