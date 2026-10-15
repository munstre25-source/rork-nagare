import SwiftUI

/// Share payload for “I understood this line” — text + a rendered card preview.
enum UnderstoodLineShare {
    static func text(line: Line, clip: Clip, surface: String?) -> String {
        let jp = line.text
        let en = line.translation
        let focus = surface.map { "Word I got: \($0)\n" } ?? ""
        return """
        I understood this line on Jojo 流れ
        \(focus)“\(jp)”
        \(en.isEmpty ? "" : "→ \(en)\n")— \(clip.channelName) · \(clip.title)
        """
    }
}

/// Visual share card for ActivityView / ShareLink preview context.
struct UnderstoodLineShareCard: View {
    let line: Line
    let clip: Clip
    var surface: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Jojo 流れ")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(Color.sakuraPink)
            Text("I understood this line")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(line.text)
                .font(JojoFont.jp(26, bold: true, relativeTo: .title))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            if !line.translation.isEmpty {
                Text(line.translation)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let surface, !surface.isEmpty {
                Text(surface)
                    .font(JojoFont.jp(16, bold: true, relativeTo: .subheadline))
                    .foregroundStyle(Color.sakuraPink)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.sakuraPink.opacity(0.12), in: Capsule())
            }
            HStack {
                Text(clip.channelName)
                Spacer()
                Text(clip.title)
                    .lineLimit(1)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
        }
        .padding(22)
        .frame(maxWidth: 340, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.card)
                .shadow(color: .black.opacity(0.12), radius: 18, y: 10)
        )
    }
}

/// Share button used on the dictionary card and clip chrome.
struct UnderstoodLineShareButton: View {
    let line: Line
    let clip: Clip
    var surface: String?
    var compact: Bool = false

    var body: some View {
        ShareLink(
            item: UnderstoodLineShare.text(line: line, clip: clip, surface: surface),
            subject: Text("I understood this line"),
            message: Text(UnderstoodLineShare.text(line: line, clip: clip, surface: surface))
        ) {
            Label(compact ? "Share" : "I understood this", systemImage: "square.and.arrow.up")
                .font(compact ? .caption.weight(.bold) : .subheadline.weight(.bold))
                .foregroundStyle(Color.sakuraPink)
                .frame(maxWidth: compact ? nil : .infinity)
                .frame(minHeight: compact ? 32 : 40)
                .padding(.horizontal, compact ? 10 : 0)
                .background(
                    Capsule().fill(Color.sakuraPink.opacity(0.12))
                )
        }
        .accessibilityLabel("Share that you understood this line")
    }
}
