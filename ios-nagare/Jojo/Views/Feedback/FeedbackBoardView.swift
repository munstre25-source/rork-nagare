import SwiftUI

/// Public request board: post ideas and bug reports, upvote what other learners asked for.
/// Posts are public but never show who wrote them. Private notes go to Messages instead.
struct FeedbackBoardView: View {
    /// When set, the leading control returns to the previous screen instead of closing the sheet.
    var onBack: (() -> Void)? = nil

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var posts: [FeedbackPost] = []
    @State private var sort: BoardSort = .top
    @State private var search = ""
    @State private var failed = false
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var hasMore = false
    @State private var nextOffset = 0
    @State private var showComposer = false
    @State private var selected: FeedbackPost?
    @State private var reporting: FeedbackPost?
    @State private var reportNotice: String?
    @State private var loadGeneration = 0

    enum BoardSort: String, CaseIterable, Hashable {
        case top, newest, trending
        var title: String {
            switch self {
            case .top: "Top"
            case .newest: "Newest"
            case .trending: "Trending"
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    header
                    OrangePillBar(items: BoardSort.allCases, selection: $sort, title: \.title)
                    content
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .background(Color.studyPage.ignoresSafeArea())
            .navigationTitle("Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search requests")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if let onBack {
                        Button("Back", action: onBack)
                    } else {
                        Button("Close") { dismiss() }
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Post a request") { showComposer = true }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(Color.studyPage)
            }
            .navigationDestination(item: $selected) { post in
                FeedbackPostScreen(post: post) { updated in
                    if let index = posts.firstIndex(where: { $0.id == updated.id }) {
                        posts[index] = updated
                    }
                }
            }
            .sheet(isPresented: $showComposer) {
                FeedbackComposer { post in
                    posts.removeAll { $0.id == post.id }
                    posts.insert(post, at: 0)
                }
            }
            .confirmationDialog(
                "Report this post?",
                isPresented: Binding(get: { reporting != nil }, set: { if !$0 { reporting = nil } }),
                titleVisibility: .visible,
                presenting: reporting
            ) { post in
                ForEach(FeedbackReportReason.allCases) { reason in
                    Button(reason.title) { Task { await report(post, reason: reason) } }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("Reported posts are hidden for review once several people flag them.")
            }
            .alert(reportNotice ?? "", isPresented: Binding(get: { reportNotice != nil }, set: { if !$0 { reportNotice = nil } })) {
                Button("OK", role: .cancel) {}
            }
            .refreshable { await reload() }
            .task(id: sort) { await reload() }
            .task(id: search) {
                // Debounce typing; the sort task already covers the first load.
                guard !search.isEmpty || !posts.isEmpty || failed else { return }
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                await reload()
            }
            .onAppear { track("feedback_board_viewed") }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ideas and bugs from Jojo learners. Upvote what you want most. Posts are public and don't show who wrote them, so please leave out personal details.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            NavigationLink {
                FeedbackInboxView()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .foregroundStyle(Color.studyAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Messages with Jojo")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("A private thread. Only you and the Jojo team see it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(14)
                .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.cardStroke))
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && posts.isEmpty {
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.card)
                    .frame(height: 96)
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.cardStroke))
            }
            .redacted(reason: .placeholder)
            .accessibilityLabel("Loading requests")
        } else if failed && posts.isEmpty {
            ContentUnavailableView {
                Label("Couldn't load the board", systemImage: "wifi.exclamationmark")
            } description: {
                Text("Check your connection and try again.")
            } actions: {
                Button("Try again") { Task { await reload() } }
                    .buttonStyle(.bordered)
                    .tint(Color.studyAccent)
            }
            .padding(.top, 12)
        } else if posts.isEmpty {
            ContentUnavailableView {
                Label(search.isEmpty ? "No requests yet" : "No matches", systemImage: search.isEmpty ? "lightbulb" : "magnifyingglass")
            } description: {
                Text(search.isEmpty ? "Be the first to ask for something." : "Try a different word, or post it as a new request.")
            }
            .padding(.top, 12)
        } else {
            ForEach(posts) { post in
                FeedbackPostRow(
                    post: post,
                    onOpen: { selected = post },
                    onVote: { await vote(post) },
                    onReport: { reporting = post }
                )
            }
            if hasMore {
                HStack {
                    Spacer()
                    if isLoadingMore {
                        ProgressView()
                    } else {
                        Button("Load more") { Task { await loadMore() } }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Color.studyAccent)
                            .frame(minHeight: 44)
                    }
                    Spacer()
                }
                .onAppear { Task { await loadMore() } }
            }
        }
    }

    // MARK: Loading

    private func reload() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        let page = await InsightsService.shared.loadFeedbackBoardPage(
            sort: sort.rawValue, search: search, offset: 0, appUserId: app.purchases.appUserId
        )
        guard generation == loadGeneration else { return }
        if let page {
            posts = page.posts
            hasMore = page.hasMore
            nextOffset = page.nextOffset
            failed = false
        } else {
            failed = true
        }
        isLoading = false
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore, !isLoading else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let generation = loadGeneration
        guard let page = await InsightsService.shared.loadFeedbackBoardPage(
            sort: sort.rawValue, search: search, offset: nextOffset, appUserId: app.purchases.appUserId
        ), generation == loadGeneration else { return }
        let known = Set(posts.map(\.id))
        posts.append(contentsOf: page.posts.filter { !known.contains($0.id) })
        hasMore = page.hasMore
        nextOffset = page.nextOffset
    }

    private func vote(_ post: FeedbackPost) async {
        guard let index = posts.firstIndex(where: { $0.id == post.id }) else { return }
        let previous = posts[index]
        Haptics.selection()
        posts[index].voted.toggle()
        posts[index].voteCount += posts[index].voted ? 1 : -1
        guard let result = await InsightsService.shared.toggleFeedbackVote(id: post.id, appUserId: app.purchases.appUserId),
              let current = posts.firstIndex(where: { $0.id == post.id }) else {
            if let current = posts.firstIndex(where: { $0.id == post.id }) { posts[current] = previous }
            return
        }
        posts[current].voteCount = result.count
        posts[current].voted = result.voted
    }

    private func report(_ post: FeedbackPost, reason: FeedbackReportReason) async {
        reporting = nil
        let ok = await InsightsService.shared.reportFeedbackPost(id: post.id, reason: reason.rawValue, appUserId: app.purchases.appUserId)
        reportNotice = ok ? "Thanks. We'll take a look." : "Couldn't send the report. Try again in a moment."
        if ok { track("feedback_post_reported", props: ["reason": reason.rawValue]) }
    }
}

nonisolated enum FeedbackReportReason: String, CaseIterable, Identifiable, Sendable {
    case spam, offensive, personalInfo = "personal_info", other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .spam: "Spam"
        case .offensive: "Offensive or abusive"
        case .personalInfo: "Shares personal info"
        case .other: "Something else"
        }
    }
}

/// Board status shown as a small badge. Unknown values hide the badge.
struct FeedbackStatusBadge: View {
    let status: String?

    private var info: (title: String, color: Color)? {
        switch status {
        case "under_review": ("Under review", .secondary)
        case "planned": ("Planned", Color(hex: "#3B82F6"))
        case "in_progress": ("In progress", Color.designOrange)
        case "completed": ("Completed", Color(hex: "#22C55E"))
        case "declined": ("Declined", Color(hex: "#9CA3AF"))
        default: nil
        }
    }

    var body: some View {
        if let info {
            Text(info.title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(info.color)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(info.color.opacity(0.14), in: Capsule())
                .accessibilityLabel("Status: \(info.title)")
        }
    }
}

private struct FeedbackPostRow: View {
    let post: FeedbackPost
    var onOpen: () -> Void
    var onVote: () async -> Void
    var onReport: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(post.category.capitalized)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.studyAccent)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.studyFocus, in: Capsule())
                        FeedbackStatusBadge(status: post.status)
                        Label("\(post.commentCount)", systemImage: "bubble.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("\(post.commentCount) comments")
                    }
                    Text(post.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(post.body)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.plain)
            Button {
                Task { await onVote() }
            } label: {
                VStack(spacing: 2) {
                    Image(systemName: post.voted ? "chevron.up.circle.fill" : "chevron.up")
                        .font(.body.weight(.bold))
                        .contentTransition(.symbolEffect(.replace))
                    Text("\(post.voteCount)")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .foregroundStyle(post.voted ? Color.studyAccent : .secondary)
                .frame(width: 44, height: 52)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(post.voted ? "Remove upvote" : "Upvote")
            .accessibilityValue("\(post.voteCount)")
        }
        .padding(14)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.cardStroke))
        .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contextMenu {
            Button(role: .destructive, action: onReport) {
                Label("Report", systemImage: "flag")
            }
        }
        .accessibilityAction(named: "Report", onReport)
    }
}

private struct FeedbackPostScreen: View {
    @Environment(AppModel.self) private var app
    @State private var post: FeedbackPost
    @State private var comments: [FeedbackComment] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorText: String?
    var onChange: (FeedbackPost) -> Void

    init(post: FeedbackPost, onChange: @escaping (FeedbackPost) -> Void) {
        _post = State(initialValue: post)
        self.onChange = onChange
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Text(post.category.capitalized)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.studyAccent)
                    FeedbackStatusBadge(status: post.status)
                }
                Text(post.title)
                    .font(.title2.weight(.bold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(post.body)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    Task { await vote() }
                } label: {
                    Label("\(post.voteCount)", systemImage: post.voted ? "chevron.up.circle.fill" : "chevron.up")
                        .font(.headline)
                        .foregroundStyle(post.voted ? Color.studyAccent : .primary)
                        .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(post.voted ? "Remove upvote" : "Upvote")

                Text("Comments")
                    .font(.headline)
                if comments.isEmpty {
                    Text("No comments yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(comments) { comment in
                        Text(comment.body)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Color.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
                TextField("Write a comment…", text: $draft, axis: .vertical)
                    .lineLimit(2...5)
                    .padding(12)
                    .background(Color.fieldFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(.red)
                }
                Button(isSending ? "Sending…" : "Comment") {
                    Task { await send() }
                }
                .buttonStyle(PrimaryButtonStyle(isEnabled: canSend))
                .disabled(!canSend)
            }
            .padding(20)
        }
        .background(Color.studyPage.ignoresSafeArea())
        .navigationTitle("Feedback")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    private func load() async {
        guard let detail = await InsightsService.shared.loadFeedbackPost(id: post.id, appUserId: app.purchases.appUserId) else {
            return
        }
        post = detail.post
        comments = detail.comments
        onChange(detail.post)
    }

    private func vote() async {
        let previous = post
        post.voted.toggle()
        post.voteCount += post.voted ? 1 : -1
        onChange(post)
        guard let result = await InsightsService.shared.toggleFeedbackVote(id: post.id, appUserId: app.purchases.appUserId) else {
            post = previous
            onChange(previous)
            return
        }
        post.voteCount = result.count
        post.voted = result.voted
        onChange(post)
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        guard let result = await InsightsService.shared.addFeedbackComment(
            postId: post.id,
            body: text,
            appUserId: app.purchases.appUserId
        ) else {
            errorText = "Couldn't send — try again in a moment."
            return
        }
        comments.append(result.comment)
        post.commentCount = result.count
        draft = ""
        errorText = nil
        onChange(post)
    }
}

/// Private thread with Jojo. Other learners' messages never load here.
private struct FeedbackInboxView: View {
    @Environment(AppModel.self) private var app
    @State private var messages: [DirectMessage] = []
    @State private var draft = ""
    @State private var failed = false
    @State private var isLoading = true
    @State private var isSending = false
    @State private var errorText: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Only you and Jojo can see this.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if isLoading && messages.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 80)
                } else if failed && messages.isEmpty {
                    Text("Messages will show when you're back online.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if messages.isEmpty {
                    Text("Nothing here yet. Write Jojo, or reply when a note arrives.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(messages) { message in
                        let mine = message.sender != "jojo"
                        HStack {
                            if mine { Spacer(minLength: 48) }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(mine ? "You" : "Jojo")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(mine ? Color.white.opacity(0.8) : Color.studyAccent)
                                Text(message.body)
                                    .font(.subheadline)
                                    .foregroundStyle(mine ? Color.white : .primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(12)
                            .background(
                                mine ? Color.studyAccent : Color.card,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                            if !mine { Spacer(minLength: 48) }
                        }
                    }
                }
                TextField("Write to Jojo…", text: $draft, axis: .vertical)
                    .lineLimit(2...5)
                    .padding(12)
                    .background(Color.fieldFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                if let errorText {
                    Text(errorText).font(.footnote).foregroundStyle(.red)
                }
                Button(isSending ? "Sending…" : "Send") {
                    Task { await send() }
                }
                .buttonStyle(PrimaryButtonStyle(isEnabled: canSend))
                .disabled(!canSend)
            }
            .padding(20)
        }
        .background(Color.studyPage.ignoresSafeArea())
        .navigationTitle("Messages")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    private func load() async {
        let loaded = await InsightsService.shared.loadDirectMessages(appUserId: app.purchases.appUserId)
        if let loaded {
            messages = loaded
            failed = false
        } else if messages.isEmpty {
            failed = true
        }
        isLoading = false
    }

    private func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        guard let message = await InsightsService.shared.sendDirectMessage(
            body: String(text.prefix(2000)),
            appUserId: app.purchases.appUserId
        ) else {
            errorText = "Couldn't send — try again in a moment."
            return
        }
        messages.append(message)
        draft = ""
        errorText = nil
    }
}

/// Request sheet opened from a clip. Posting or cancelling returns to that clip.
struct ClipFeatureRequestSheet: View {
    var contextNote: String?
    @Environment(\.dismiss) private var dismiss
    @State private var showBoard = false

    var body: some View {
        if showBoard {
            FeedbackBoardView(onBack: { showBoard = false })
        } else {
            FeedbackComposer(contextNote: contextNote, onBrowse: { showBoard = true }) { _ in
                dismiss()
            }
        }
    }
}

private struct FeedbackComposer: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var category = "feature"
    @State private var title = ""
    @State private var bodyText = ""
    @State private var isSending = false
    @State private var errorText: String?
    var contextNote: String? = nil
    var onBrowse: (() -> Void)? = nil
    var onPosted: (FeedbackPost) -> Void

    private let categories = ["bug", "feature", "general"]

    var body: some View {
        NavigationStack {
            composer
                .padding(20)
                .background(Color.studyPage.ignoresSafeArea())
                .navigationTitle("New request")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    if let onBrowse {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Board", action: onBrowse)
                        }
                    }
                }
        }
        .presentationDetents([.large])
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What should we build, or what broke?")
                .font(.title3.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            if contextNote != nil {
                Text("This posts to the feedback board. Cancel returns you to the clip.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            categoryPills
            titleField
            messageField
            if let errorText {
                Text(errorText).font(.footnote).foregroundStyle(.red)
            }
            Spacer(minLength: 0)
            submitButton
        }
    }

    private var categoryPills: some View {
        HStack(spacing: 8) {
            ForEach(categories, id: \.self) { item in
                FeedbackCategoryPill(title: item.capitalized, selected: category == item) {
                    category = item
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var titleField: some View {
        TextField("Short title", text: $title)
            .padding(12)
            .background(Color.fieldFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var messageField: some View {
        TextField("It would be cool if… / I ran into a bug when…", text: $bodyText, axis: .vertical)
            .lineLimit(4...8)
            .padding(12)
            .background(Color.fieldFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var submitButton: some View {
        Button(isSending ? "Sending…" : "Give Feedback!") {
            Task { await submit() }
        }
        .buttonStyle(PrimaryButtonStyle(isEnabled: canSend))
        .disabled(!canSend)
    }

    private var canSend: Bool {
        !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isSending
    }

    private func submit() async {
        let text = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isSending = true
        defer { isSending = false }
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var message = String(text.prefix(1000))
        if let contextNote, !contextNote.isEmpty, !message.contains(contextNote) {
            let suffix = "\n\n" + contextNote
            if message.count + suffix.count <= 1000 {
                message += suffix
            }
        }
        guard let post = await InsightsService.shared.createFeedbackPost(
            category: category,
            title: String(trimmedTitle.prefix(80)),
            body: message,
            appUserId: app.purchases.appUserId
        ) else {
            errorText = "Couldn't send — try again in a moment."
            return
        }
        onPosted(post)
        dismiss()
    }
}

private struct FeedbackCategoryPill: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            Haptics.selection()
            action()
        }) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .background {
                    Capsule().fill(selected ? AnyShapeStyle(Color.sakuraFill) : AnyShapeStyle(Color.fieldFill))
                }
        }
        .buttonStyle(.plain)
    }
}
