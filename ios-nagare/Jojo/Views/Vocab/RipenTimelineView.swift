import SwiftUI

/// Yomi-style “same line, three months apart” — drag through Day 1 / Week 3 / Month 3
/// and watch amber words turn green.
struct RipenTimelineView: View {
    @Environment(AppModel.self) private var app
    @State private var day: Double = 1

    private let milestones: [(day: Double, label: String)] = [
        (1, "Day 1"),
        (21, "Week 3"),
        (90, "Month 3"),
    ]

    private let demoTokens: [(surface: String, furigana: String?, romaji: String)] = [
        ("今日", "きょう", "kyou"),
        ("は", nil, "wa"),
        ("朝", "あさ", "asa"),
        ("から", nil, "kara"),
        ("雨", "あめ", "ame"),
        ("だった", nil, "datta"),
        ("けど", nil, "kedo"),
        ("、", nil, ""),
        ("午後", "ごご", "gogo"),
        ("は", nil, "wa"),
        ("友達", "ともだち", "tomodachi"),
        ("と", nil, "to"),
        ("カフェ", nil, "kafe"),
        ("で", nil, "de"),
        ("話せた", "はな", "hanaseta"),
        ("。", nil, ""),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("See it ripen")
                        .font(.title3.weight(.black))
                    Text("The same line, three months apart.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text("\(greenCount) of \(tappableCount) green")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(LearningInk.known)
            }

            Text(lineAt(day: day))
                .font(.footnote)
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 4, lineSpacing: 10) {
                ForEach(Array(demoTokens.enumerated()), id: \.offset) { index, token in
                    let mark = mark(for: index, day: day)
                    VStack(spacing: 2) {
                        if app.profile.showFurigana {
                            Text(token.furigana ?? " ")
                                .font(JojoFont.jp(10, relativeTo: .caption2))
                                .foregroundStyle(LearningInk.mastery(mark).opacity(0.75))
                        }
                        Text(token.surface)
                            .font(JojoFont.jp(22, bold: true, relativeTo: .title3))
                            .foregroundStyle(token.romaji.isEmpty ? LearningInk.japanese : LearningInk.mastery(mark))
                        if app.profile.showRomaji, !token.romaji.isEmpty {
                            Text(token.romaji)
                                .font(.system(size: 9))
                                .foregroundStyle(LearningInk.mastery(mark).opacity(0.7))
                        }
                    }
                    .padding(.horizontal, token.romaji.isEmpty ? 0 : 4)
                }
            }

            Slider(value: $day, in: 1...90, step: 1)
                .tint(Color.sakuraPink)
                .accessibilityLabel("Days of watching")

            HStack {
                ForEach(milestones, id: \.day) { item in
                    Button {
                        Haptics.selection()
                        withAnimation(.snappy) { day = item.day }
                    } label: {
                        Text(item.label)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(abs(day - item.day) < 0.5 ? Color.white : .primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                abs(day - item.day) < 0.5 ? Color.sakuraPink : Color.fieldFill,
                                in: Capsule()
                            )
                    }
                    .accessibilityAddTraits(abs(day - item.day) < 0.5 ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
        }
        .padding(Spacing.l)
        .background(Color.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(Color.cardStroke, lineWidth: 1)
        )
    }

    private var tappableCount: Int { demoTokens.filter { !$0.romaji.isEmpty }.count }

    private var greenCount: Int {
        demoTokens.indices.filter { mark(for: $0, day: day) == .known }.count
    }

    private func lineAt(day: Double) -> String {
        if day < 10 { return "Day \(Int(day)) · a wall of amber words." }
        if day < 40 { return "Day \(Int(day)) · some greens starting to stick." }
        return "Day \(Int(day)) · the line you just understand."
    }

    /// Seeds ripen on a staggered schedule so the slider feels earned.
    private func mark(for index: Int, day: Double) -> SRSState {
        let token = demoTokens[index]
        guard !token.romaji.isEmpty else { return .known }
        // Particles ripen early; content words later.
        let isParticle = ["は", "から", "けど", "と", "で"].contains(token.surface)
        let unlockDay: Double
        if isParticle {
            unlockDay = Double((index % 5) + 3)
        } else {
            unlockDay = Double(8 + (index % 7) * 10)
        }
        if day < unlockDay * 0.4 { return .new }
        if day < unlockDay * 0.7 { return .learning }
        if day < unlockDay { return .familiar }
        if day < unlockDay * 1.2 { return .easy }
        return .known
    }
}
