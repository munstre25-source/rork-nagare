import SwiftUI

/// Draws the current tour step or tip: a soft dim with a cutout around the real control and a
/// small card beside it. The dim never takes touches, so the control underneath stays usable.
struct CoachOverlay: View {
    @State private var guide = GuidanceCenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private enum Content: Equatable {
        case tour(TourStep)
        case tip(CoachTip)

        var anchor: CoachAnchor {
            switch self {
            case .tour(let step): step.anchor
            case .tip(let tip): tip.anchor
            }
        }
    }

    private var content: Content? {
        if let step = guide.visibleTourStep { return .tour(step) }
        if guide.tourStep == nil, let tip = guide.activeTip, guide.frame(for: tip.anchor) != nil,
           !guide.blockedByPresentation {
            return .tip(tip)
        }
        return nil
    }

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let target = content.flatMap { guide.frame(for: $0.anchor) }.map {
                $0.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: -8, dy: -8)
            }
            if let content, Self.isShowable(content, target: target, size: proxy.size) {
                ZStack(alignment: .topLeading) {
                    dim(target: target, size: proxy.size)
                    bubble(for: content)
                        .frame(maxWidth: 360)
                        .padding(.horizontal, 20)
                        .frame(width: proxy.size.width)
                        .modifier(BubblePlacement(target: target, size: proxy.size, insets: proxy.safeAreaInsets))
                }
                .transition(.opacity)
                .id(contentID(content))
            }
        }
        .ignoresSafeArea()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: content)
        .onChange(of: content) { _, new in announce(new) }
        .onAppear {
            announce(content)
            if !reduceMotion { pulse = true }
        }
    }

    /// Tips only show while their control is fully on screen (e.g. not scrolled away).
    private static func isShowable(_ content: Content, target: CGRect?, size: CGSize) -> Bool {
        guard case .tip = content else { return true }
        guard let target else { return false }
        return target.minY > 40 && target.maxY < size.height - 100 && target.height > 0
    }

    private func contentID(_ content: Content) -> String {
        switch content {
        case .tour(let step): "tour-\(step.rawValue)"
        case .tip(let tip): "tip-\(tip.rawValue)"
        }
    }

    // MARK: Dim and spotlight

    @ViewBuilder
    private func dim(target: CGRect?, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            CutoutShape(cutout: target, cornerRadius: 18)
                .fill(Color.black.opacity(target == nil ? 0.35 : 0.55), style: FillStyle(eoFill: true))
            if let target {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.designOrange, lineWidth: 2)
                    .frame(width: target.width, height: target.height)
                    .scaleEffect(pulse ? 1.015 : 1)
                    .opacity(pulse ? 0.65 : 1)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: pulse)
                    .offset(x: target.minX, y: target.minY)
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: Bubble

    @ViewBuilder
    private func bubble(for content: Content) -> some View {
        switch content {
        case .tour(let step): tourBubble(step)
        case .tip(let tip): tipBubble(tip)
        }
    }

    private func tourBubble(_ step: TourStep) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(step.eyebrow)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.designOrange)
                    .textCase(.uppercase)
                    .accessibilityLabel("Step \(step.rawValue + 1) of \(TourStep.allCases.count), \(step.eyebrow)")
                Spacer(minLength: 8)
                dots(current: step)
            }
            Text(step.title)
                .font(.headline)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(guide.showStuckHint ? (step.stuckHint ?? step.message) : step.message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
            HStack(spacing: 12) {
                Button("Skip tour") {
                    Haptics.selection()
                    guide.skipTour()
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.white.opacity(0.6))
                .frame(minHeight: 44)
                Spacer(minLength: 0)
                if !step.waitsForAction || guide.showStuckHint {
                    Button(step.primaryLabel) {
                        Haptics.selection()
                        guide.next()
                    }
                    .buttonStyle(CoachPrimaryButtonStyle())
                }
            }
        }
        .modifier(BubbleChrome())
        .accessibilityElement(children: .contain)
    }

    private func tipBubble(_ tip: CoachTip) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Tip")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.designOrange)
                .textCase(.uppercase)
            Text(tip.title)
                .font(.headline)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
            Text(tip.message)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer(minLength: 0)
                Button("Got it") {
                    Haptics.selection()
                    guide.dismissTip()
                }
                .buttonStyle(CoachPrimaryButtonStyle())
            }
        }
        .modifier(BubbleChrome())
        .accessibilityElement(children: .contain)
    }

    private func dots(current: TourStep) -> some View {
        HStack(spacing: 5) {
            ForEach(TourStep.allCases, id: \.rawValue) { step in
                Capsule()
                    .fill(step.rawValue <= current.rawValue ? Color.designOrange : Color.white.opacity(0.2))
                    .frame(width: step == current ? 14 : 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }

    private func announce(_ content: Content?) {
        guard let content else { return }
        let text: String
        switch content {
        case .tour(let step): text = "\(step.title). \(step.message)"
        case .tip(let tip): text = "\(tip.title). \(tip.message)"
        }
        AccessibilityNotification.Announcement(text).post()
    }
}

/// Puts the card below the spotlight when there's room, otherwise above, otherwise at the bottom.
private struct BubblePlacement: ViewModifier {
    let target: CGRect?
    let size: CGSize
    let insets: EdgeInsets
    private let estimatedHeight: CGFloat = 210
    private let gap: CGFloat = 14

    func body(content: Content) -> some View {
        let top = insets.top + 8
        let bottom = insets.bottom + 8
        if let target {
            let below = size.height - bottom - target.maxY
            let above = target.minY - top
            if below >= estimatedHeight {
                content
                    .padding(.top, target.maxY + gap)
                    .frame(width: size.width, height: size.height, alignment: .top)
            } else if above >= estimatedHeight {
                content
                    .padding(.bottom, size.height - target.minY + gap)
                    .frame(width: size.width, height: size.height, alignment: .bottom)
            } else {
                content
                    .padding(.bottom, bottom + 84)
                    .frame(width: size.width, height: size.height, alignment: .bottom)
            }
        } else {
            content
                .padding(.bottom, bottom + 120)
                .frame(width: size.width, height: size.height, alignment: .bottom)
        }
    }
}

private struct BubbleChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(Color(hex: "#121212"), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 24, y: 10)
            .environment(\.colorScheme, .dark)
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
    }
}

private struct CoachPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .frame(minHeight: 44)
            .background(Color.designOrange, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.18), value: configuration.isPressed)
    }
}

/// Full-screen rectangle with a rounded hole (even-odd fill).
private struct CutoutShape: Shape {
    var cutout: CGRect?
    var cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        if let cutout {
            path.addRoundedRect(in: cutout, cornerSize: CGSize(width: cornerRadius, height: cornerRadius), style: .continuous)
        }
        return path
    }
}
