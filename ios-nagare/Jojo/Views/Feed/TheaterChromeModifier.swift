import SwiftUI

/// Shared gesture/idle behavior for Explore and onboarding theater players.
struct TheaterChromeModifier: ViewModifier {
    var expanded: Bool
    @Binding var visible: Bool
    var playing: Bool
    var blocked: Bool
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var interaction = 0
    @State private var isLandscapeViewport = false

    private struct IdleState: Hashable {
        var expanded: Bool
        var visible: Bool
        var playing: Bool
        var blocked: Bool
        var voiceOver: Bool
        var interaction: Int
    }

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 28).onEnded { value in
                    guard expanded else { return }
                    if isLandscapeViewport {
                        withAnimation(.easeInOut(duration: 0.2)) { visible = true }
                        interaction += 1
                    } else if value.translation.height > 48 {
                        withAnimation(.easeInOut(duration: 0.2)) { visible = true }
                        interaction += 1
                    } else if value.translation.height < -48 {
                        withAnimation(.easeInOut(duration: 0.2)) { visible = false }
                    }
                }
            )
            .simultaneousGesture(
                TapGesture().onEnded {
                    if expanded && isLandscapeViewport {
                        withAnimation(.easeInOut(duration: 0.2)) { visible = true }
                    }
                    interaction += 1
                }
            )
            .onGeometryChange(for: Bool.self) { proxy in
                proxy.size.width > proxy.size.height
            } action: { isLandscapeViewport = $0 }
            .onChange(of: expanded) { _, _ in visible = false }
            .task(id: IdleState(expanded: expanded, visible: visible, playing: playing,
                                blocked: blocked, voiceOver: voiceOverEnabled, interaction: interaction)) {
                guard expanded, visible, playing, !blocked, !voiceOverEnabled else { return }
                do { try await Task.sleep(for: .seconds(4)) } catch { return }
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.3)) { visible = false }
            }
            .accessibilityActions {
                if expanded {
                    Button(visible ? "Hide playback controls" : "Show playback controls") {
                        visible.toggle()
                        interaction += 1
                    }
                }
            }
    }
}
