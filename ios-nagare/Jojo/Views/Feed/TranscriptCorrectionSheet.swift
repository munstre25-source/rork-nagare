import SwiftUI

/// Private, line-specific transcript feedback from the feed.
struct TranscriptCorrectionSheet: View {
    let clip: Clip
    let initialLineIndex: Int?

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLineIndex: Int
    @State private var issue: Issue = .japanese
    @State private var correction = ""
    @State private var details = ""
    @State private var isSending = false
    @State private var didSend = false
    @State private var errorText: String?
    @FocusState private var focusedField: Field?

    private enum Issue: String, CaseIterable, Identifiable {
        case japanese, translation, reading, timing, other

        var id: String { rawValue }
        var title: String {
            switch self {
            case .japanese: "Japanese transcript"
            case .translation: "English translation"
            case .reading: "Furigana or reading"
            case .timing: "Timing or line break"
            case .other: "Other issue"
            }
        }
    }

    private enum Field: Hashable { case correction, details }

    init(clip: Clip, lineIndex: Int? = nil) {
        self.clip = clip
        self.initialLineIndex = lineIndex
        _selectedLineIndex = State(initialValue: lineIndex ?? 0)
    }

    private var activeLineIndex: Int {
        min(max(selectedLineIndex, 0), max(clip.lines.count - 1, 0))
    }
    private var line: Line? { clip.lines[safe: activeLineIndex] }
    private var trimmedCorrection: String { correction.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var trimmedDetails: String { details.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool { (!trimmedCorrection.isEmpty || !trimmedDetails.isEmpty) && !isSending }

    var body: some View {
        NavigationStack {
            Group {
                if didSend {
                    sentView
                } else {
                    form
                }
            }
            .navigationTitle(didSend ? "Report sent" : "Report transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(didSend ? "Done" : "Cancel") { dismiss() }
                }
                if !didSend {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isSending ? "Sending…" : "Send") {
                            Task { await submit() }
                        }
                        .disabled(!canSend)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var form: some View {
        Form {
            Section("Line being reported") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(clip.title)
                        .font(.subheadline.weight(.semibold))
                    if initialLineIndex == nil, !clip.lines.isEmpty {
                        Picker("Transcript line", selection: $selectedLineIndex) {
                            ForEach(clip.lines.indices, id: \.self) { index in
                                Text("Line \(index + 1): \(String(clip.lines[index].text.prefix(24)))")
                                    .tag(index)
                            }
                        }
                    }
                    if let line {
                        Text(line.text)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.primary)
                        if !line.translation.isEmpty {
                            Text(line.translation)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text("Line \(activeLineIndex + 1) · \(formatClock(line.start))–\(formatClock(line.end))")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    } else {
                        Text("Line \(activeLineIndex + 1)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("What needs fixing?") {
                Picker("Issue", selection: $issue) {
                    ForEach(Issue.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                TextField(correctionPlaceholder, text: $correction, axis: .vertical)
                    .lineLimit(2...5)
                    .focused($focusedField, equals: .correction)
                    .onChange(of: correction) { _, value in
                        if value.count > 700 { correction = String(value.prefix(700)) }
                    }
            }

            Section("More detail (optional)") {
                TextField("Add context to help us review it", text: $details, axis: .vertical)
                    .lineLimit(2...4)
                    .focused($focusedField, equals: .details)
                    .onChange(of: details) { _, value in
                        if value.count > 500 { details = String(value.prefix(500)) }
                    }
                Text("This report is sent privately to the Jojo team with the clip and line details above.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorText {
                Section {
                    Text(errorText)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var sentView: some View {
        ContentUnavailableView {
            Label("Thanks for the correction", systemImage: "checkmark.circle.fill")
        } description: {
            Text("Your report includes this clip and the exact transcript line. The team can review it in private feedback.")
        }
    }

    private var correctionPlaceholder: String {
        switch issue {
        case .japanese: "Suggested Japanese wording"
        case .translation: "Suggested English translation"
        case .reading: "Suggested furigana or reading"
        case .timing: "Suggested timing or line break"
        case .other: "What should this line say?"
        }
    }

    @MainActor
    private func submit() async {
        guard canSend else { return }
        focusedField = nil
        errorText = nil
        isSending = true
        defer { isSending = false }

        let message = reportMessage
        let sent = await InsightsService.shared.submitFeedback(
            enjoyed: nil,
            category: "content",
            message: message,
            appUserId: app.purchases.appUserId,
            source: "manual"
        )
        guard sent else {
            errorText = await InsightsService.shared.lastErrorMessage() ?? "Couldn't send the report. Check your connection and try again."
            return
        }
        track("transcript_correction_submitted", props: ["clip": clip.id, "line": "\(activeLineIndex + 1)", "issue": issue.rawValue])
        withAnimation(.snappy) { didSend = true }
    }

    private var reportMessage: String {
        let currentLine = line
        let entries = [
            "Transcript correction report",
            "Clip ID: \(clip.id)",
            "YouTube video ID: \(clip.videoId)",
            "Clip title: \(String(clip.title.prefix(140)))",
            "Line: \(activeLineIndex + 1)",
            "Time: \(formatClock(currentLine?.start ?? 0))–\(formatClock(currentLine?.end ?? 0))",
            "Issue: \(issue.title)",
            "Current Japanese: \(String(currentLine?.text.prefix(220) ?? ""))",
            "Current English: \(String(currentLine?.translation.prefix(260) ?? ""))",
            "Suggested correction: \(trimmedCorrection)",
            "Details: \(trimmedDetails)"
        ]
        return String(entries.joined(separator: "\n").prefix(1900))
    }
}
