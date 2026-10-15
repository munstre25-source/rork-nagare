import SwiftUI
import Charts

/// End-of-week learning report: minutes, streak, words, weak pockets.
struct WeeklyReportView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let report: WeeklyLearningReport

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.l) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("This week")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.sakuraPink)
                            .textCase(.uppercase)
                        Text(report.headline)
                            .font(.title.weight(.bold))
                        Text(report.subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: Spacing.m) {
                        reportTile("\(report.minutesWatched)", "min watched", symbol: "clock.fill")
                        reportTile("\(report.wordsSaved)", "words saved", symbol: "bookmark.fill")
                        reportTile("\(report.cardsReviewed)", "reviewed", symbol: "rectangle.on.rectangle.angled")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Daily minutes")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                        Chart(report.dayMinutes) { day in
                            BarMark(
                                x: .value("Day", day.date, unit: .day),
                                y: .value("Min", day.minutes)
                            )
                            .foregroundStyle(Color.sakuraPink.gradient)
                        }
                        .frame(height: 140)
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .day)) { _ in
                                AxisValueLabel(format: .dateTime.weekday(.abbreviated))
                            }
                        }
                    }
                    .padding(16)
                    .background(Color.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    if !report.topWords.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Words that stuck")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            ForEach(report.topWords, id: \.self) { word in
                                Text(word)
                                    .font(JojoFont.jp(20, bold: true, relativeTo: .title3))
                            }
                        }
                    }

                    if let pocket = report.weakPocketTitle {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Watch next")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                            Text(pocket)
                                .font(.headline)
                            Text("A short review of this pocket keeps next week easier.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.sakuraPink.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    Text("Streak \(report.streak) · Goal hit \(report.goalDays)/7 days")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .background(Color.canvas.ignoresSafeArea())
            .navigationTitle("Weekly report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onAppear {
            app.markWeeklyReportSeen()
        }
    }

    private func reportTile(_ value: String, _ caption: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.sakuraPink)
            Text(value)
                .font(.title2.weight(.bold))
            Text(caption)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

nonisolated struct WeeklyLearningReport: Sendable {
    var headline: String
    var subtitle: String
    var minutesWatched: Int
    var wordsSaved: Int
    var cardsReviewed: Int
    var streak: Int
    var goalDays: Int
    var dayMinutes: [DayMinutes]
    var topWords: [String]
    var weakPocketTitle: String?
}
