import SwiftUI

/// Cinematic gradient poster used by the simulated player and clip thumbnails.
struct GradientPoster: View {
    let clip: Clip
    var isAnimating: Bool = false
    var showsSymbol: Bool = true

    private var colors: [Color] {
        let hexes = clip.thumbnailGradient.isEmpty ? ["#111111", "#333333", "#FF6B00"] : clip.thumbnailGradient
        return hexes.map { Color(hex: $0) }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !isAnimating)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    LinearGradient(colors: [colors[0], colors[safe: 1] ?? colors[0]], startPoint: .topLeading, endPoint: .bottomTrailing)
                    RadialGradient(
                        colors: [(colors.last ?? .orange).opacity(0.85), .clear],
                        center: UnitPoint(x: 0.7 + 0.12 * sin(t * 0.35), y: 0.35 + 0.1 * cos(t * 0.28)),
                        startRadius: 4,
                        endRadius: max(size.width, size.height) * 0.6
                    )
                    RadialGradient(
                        colors: [(colors[safe: 1] ?? .orange).opacity(0.7), .clear],
                        center: UnitPoint(x: 0.2 + 0.1 * cos(t * 0.22), y: 0.8 + 0.08 * sin(t * 0.3)),
                        startRadius: 2,
                        endRadius: max(size.width, size.height) * 0.5
                    )
                    bokeh(size: size, t: t)
                    if showsSymbol {
                        Image(systemName: clip.categoryKind.symbol)
                            .font(.system(size: min(size.width, size.height) * 0.34, weight: .light))
                            .foregroundStyle(.white.opacity(0.13))
                            .offset(x: size.width * 0.22, y: -size.height * 0.04 + 4 * sin(t * 0.6))
                    }
                    LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                }
            }
        }
        .accessibilityHidden(true)
    }

    private func bokeh(size: CGSize, t: Double) -> some View {
        let seed = clip.id.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 10_007 }
        return ZStack {
            ForEach(0..<7, id: \.self) { i in
                let fx = Double((seed * (i + 3)) % 100) / 100
                let fy = Double((seed * (i + 7)) % 100) / 100
                let r = CGFloat(10 + (seed * (i + 1)) % 26)
                Circle()
                    .fill(.white.opacity(0.07 + Double(i % 3) * 0.03))
                    .frame(width: r, height: r)
                    .blur(radius: 3)
                    .position(
                        x: size.width * fx + 6 * sin(t * 0.4 + Double(i)),
                        y: size.height * fy * 0.7 + 5 * cos(t * 0.3 + Double(i))
                    )
            }
        }
    }
}

/// Circular channel avatar with the channel's initial.
struct ChannelAvatar: View {
    let clip: Clip
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            Circle().fill(
                LinearGradient(colors: [Color(hex: clip.channelAvatarColor), Color(hex: clip.channelAvatarColor).opacity(0.55)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            Image(systemName: clip.categoryKind.symbol)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Channel attribution row: avatar, name, subtitle, optional Follow.
struct ChannelRow: View {
    let clip: Clip
    var trailing: AnyView?
    var showsFollow: Bool = true
    /// When true, lead with clip title + channel (TikTok-style feed chrome).
    var emphasizesTitle: Bool = false

    var body: some View {
        HStack(spacing: Spacing.m) {
            ChannelAvatar(clip: clip)
            VStack(alignment: .leading, spacing: 1) {
                if emphasizesTitle {
                    Text(clip.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(clip.channelName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text(clip.channelName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("\(clip.categoryKind.displayName) · \(clip.difficulty)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if showsFollow {
                FollowChannelButton(channelName: clip.channelName)
            }
            trailing
        }
        .padding(.horizontal, Spacing.l)
        .accessibilityElement(children: .contain)
    }
}

/// Follow / Following capsule used in channel rows and clip info.
struct FollowChannelButton: View {
    let channelName: String
    @Environment(AppModel.self) private var app

    var body: some View {
        Button {
            Haptics.selection()
            withAnimation(.snappy) { _ = app.toggleFollow(channel: channelName) }
        } label: {
            Text(app.isFollowing(channel: channelName) ? "Following" : "Follow")
                .font(.caption.weight(.bold))
                .foregroundStyle(app.isFollowing(channel: channelName) ? Color.secondary : Color.white)
                .padding(.horizontal, 12)
                .frame(minHeight: 32)
                .background(
                    app.isFollowing(channel: channelName)
                        ? Color.fieldFill
                        : Color.jojoOrange,
                    in: Capsule()
                )
        }
        .accessibilityLabel(app.isFollowing(channel: channelName) ? "Unfollow \(channelName)" : "Follow \(channelName)")
    }
}

/// Peek of the next clip at the bottom of a feed page — scroll affordance.
struct NextClipPeek: View {
    let clip: Clip

    var body: some View {
        HStack(spacing: Spacing.m) {
            ChannelAvatar(clip: clip, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(clip.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(clip.channelName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(spacing: 2) {
                Image(systemName: "chevron.compact.up")
                    .font(.system(size: 16, weight: .bold))
                Text("Next")
                    .font(.caption2.weight(.bold))
            }
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Spacing.l)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [.clear, Color.canvas.opacity(0.92), Color.canvas],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Next: \(clip.title) by \(clip.channelName). Swipe up.")
    }
}
