import SwiftUI

/// Kiku-style For You / Explore switch, centered on the top edge.
struct CenteredModeSwitch: View {
    var forYouSelected: Bool
    var onForYou: () -> Void
    var onExplore: () -> Void

    var body: some View {
        HStack(spacing: 22) {
            mode("For You", selected: forYouSelected, action: onForYou)
            mode("Explore", selected: !forYouSelected, action: onExplore)
        }
        .accessibilityElement(children: .contain)
    }

    private func mode(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            VStack(spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Capsule()
                    .fill(selected ? Color.sakuraPink : Color.clear)
                    .frame(width: 36, height: 3)
            }
            .frame(minHeight: 40)
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Explore home segments from the design boards: For You, Explore, My Path.
struct ExploreSegmentBar: View {
    enum Segment: Hashable {
        case forYou, explore, myPath
    }

    var selection: Segment
    var onForYou: () -> Void
    var onExplore: () -> Void
    var onMyPath: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            chip("For You", selected: selection == .forYou, action: onForYou)
            chip("Explore", selected: selection == .explore, action: onExplore)
            chip("My Path", selected: selection == .myPath, action: onMyPath)
        }
        .padding(4)
        .background(Color.card.opacity(0.9), in: Capsule())
        .overlay(Capsule().strokeBorder(Color.cardStroke, lineWidth: 1))
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.selection()
            action()
        } label: {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.72))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background {
                    if selected { Capsule().fill(Color.sakuraFill) }
                }
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Hides the floating tab bar while the finger moves down the page, and brings it back on the way up.
struct TabBarAutoHide: ViewModifier {
    @Binding var hidden: Bool

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 18, coordinateSpace: .local)
                .onEnded { value in
                    guard abs(value.translation.height) > abs(value.translation.width),
                          abs(value.translation.height) > 28 else { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                        hidden = value.translation.height < 0
                    }
                }
        )
    }
}

extension View {
    func tabBarAutoHide(_ hidden: Binding<Bool>) -> some View {
        modifier(TabBarAutoHide(hidden: hidden))
    }
}

/// Equal segments inside one capsule, used on Vocab and Search.
struct OrangePillBar<Item: Hashable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.self) { item in
                let selected = selection == item
                Button {
                    Haptics.selection()
                    withAnimation(.snappy) { selection = item }
                } label: {
                    Text(title(item))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.72))
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                        .padding(.horizontal, 8)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background {
                            if selected { Capsule().fill(Color.sakuraFill) }
                        }
                }
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Color.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.cardStroke, lineWidth: 1))
    }
}

struct JLPTBadge: View {
    let level: String

    private var tint: Color {
        switch level.uppercased() {
        case "N5": Color(hex: "#E85D8C")
        case "N4": Color(hex: "#3BA55D")
        case "N3": Color(hex: "#3B82F6")
        case "N2": Color(hex: "#8B5CF6")
        default: Color(hex: "#D97706")
        }
    }

    var body: some View {
        Text(level.uppercased().hasPrefix("JLPT") ? level.uppercased() : "JLPT \(level.uppercased())")
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

struct DesignSearchField: View {
    @Binding var text: String
    var placeholder: String
    var focused: FocusState<Bool>.Binding? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            field
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(minHeight: 48)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.cardStroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var field: some View {
        if let focused {
            TextField(placeholder, text: $text)
                .focused(focused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .lineLimit(1)
        } else {
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .lineLimit(1)
        }
    }
}
