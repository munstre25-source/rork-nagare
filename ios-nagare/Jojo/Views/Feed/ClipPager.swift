import SwiftUI

/// TikTok-style vertical pager. Exactly one page fills the viewport at rest, and a swipe
/// moves exactly one page.
///
/// Unlike a paged `ScrollView`, there is no scroll offset to drift: every page is placed at
/// `(index - current) * height`. When the viewport changes (maximize, dock, rotation) the
/// current page still sits at zero, so two clips can never share the screen.
/// Only the previous, current and next pages are mounted.
struct ClipPager<Page: View>: View {
    let ids: [String]
    @Binding var currentId: String?
    /// While true (dictionary card, quick check), swipes are ignored and pages stay put.
    var isDisabled: Bool = false
    @ViewBuilder let page: (String) -> Page

    @State private var drag = PagerDrag()
    @GestureState private var gestureActive = false

    private var currentIndex: Int {
        guard let currentId, let index = ids.firstIndex(of: currentId) else { return 0 }
        return index
    }

    private func window(around index: Int) -> [String] {
        guard !ids.isEmpty else { return [] }
        let lower = max(0, index - 1)
        let upper = min(ids.count - 1, index + 1)
        return Array(ids[lower...upper])
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let index = currentIndex
            ZStack(alignment: .top) {
                ForEach(window(around: index), id: \.self) { id in
                    let position = ids.firstIndex(of: id) ?? index
                    page(id)
                        .frame(width: size.width, height: size.height, alignment: .top)
                        .clipped()
                        .contentShape(Rectangle())
                        .offset(y: CGFloat(position - index) * size.height)
                        .allowsHitTesting(position == index)
                        .accessibilityHidden(position != index)
                        .zIndex(position == index ? 1 : 0)
                        .transition(.identity)
                }
            }
            .modifier(PagerDragOffset(drag: drag))
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(dragGesture(pageHeight: size.height), including: isDisabled ? .subviews : .all)
            .onChange(of: gestureActive) { _, active in
                // A gesture cancelled by the system never reaches onEnded: settle back.
                guard !active else { return }
                DispatchQueue.main.async {
                    guard drag.offset != 0, !drag.isSettling else { return }
                    withAnimation(Self.settle) { drag.offset = 0 }
                    drag.axis = nil
                }
            }
            .onChange(of: isDisabled) { _, disabled in
                guard disabled, drag.offset != 0 else { return }
                withAnimation(Self.settle) { drag.offset = 0 }
                drag.axis = nil
            }
        }
        .clipped()
    }

    static var settle: Animation { .spring(response: 0.36, dampingFraction: 0.9) }

    private func dragGesture(pageHeight: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 14, coordinateSpace: .global)
            .updating($gestureActive) { _, state, _ in state = true }
            .onChanged { value in
                guard !isDisabled, pageHeight > 0 else { return }
                if drag.axis == nil {
                    let dx = abs(value.translation.width)
                    let dy = abs(value.translation.height)
                    guard max(dx, dy) >= 10 else { return }
                    drag.axis = dy > dx ? .vertical : .horizontal
                }
                guard drag.axis == .vertical else { return }
                drag.isSettling = false
                var offset = value.translation.height
                let pullingPastStart = currentIndex == 0 && offset > 0
                let pullingPastEnd = currentIndex >= ids.count - 1 && offset < 0
                if pullingPastStart || pullingPastEnd { offset *= 0.28 }
                offset = min(max(offset, -pageHeight), pageHeight)
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { drag.offset = offset }
            }
            .onEnded { value in
                defer { drag.axis = nil }
                guard drag.axis == .vertical, !isDisabled, pageHeight > 0 else {
                    if drag.offset != 0 { withAnimation(Self.settle) { drag.offset = 0 } }
                    return
                }
                let moved = value.translation.height
                let predicted = value.predictedEndTranslation.height
                let index = currentIndex
                var target = index
                if (moved < -pageHeight * 0.2 || predicted < -pageHeight * 0.5), index < ids.count - 1 {
                    target = index + 1
                } else if (moved > pageHeight * 0.2 || predicted > pageHeight * 0.5), index > 0 {
                    target = index - 1
                }
                drag.isSettling = true
                if target != index { Haptics.selection() }
                withAnimation(Self.settle) {
                    if target != index { currentId = ids[target] }
                    drag.offset = 0
                } completion: {
                    drag.isSettling = false
                }
            }
    }
}

/// Drag state lives in an observable object so only the offset modifier re-renders while a
/// finger moves; the pages themselves are not rebuilt on every frame.
@Observable
final class PagerDrag {
    var offset: CGFloat = 0
    @ObservationIgnored var axis: Axis?
    @ObservationIgnored var isSettling = false
}

private struct PagerDragOffset: ViewModifier {
    let drag: PagerDrag

    func body(content: Content) -> some View {
        content.offset(y: drag.offset)
    }
}
