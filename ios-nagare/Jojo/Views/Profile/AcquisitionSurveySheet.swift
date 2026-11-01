import SwiftUI

/// A short, optional question shown after the learner has watched clips.
struct AcquisitionSurveySheet: View {
    let onClose: () -> Void
    @Environment(AppModel.self) private var app
    @State private var selected: AcquisitionSource?
    @State private var otherDetail = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(AcquisitionSource.allCases) { source in
                        Button {
                            selected = source
                            Haptics.selection()
                            track("acquisition_survey_selected", props: ["source": source.rawValue])
                        } label: {
                            HStack {
                                Label(source.title, systemImage: source.symbol)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if selected == source {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.designOrange)
                                }
                            }
                        }
                    }
                    if selected == .other {
                        TextField("Where did you find us? (optional)", text: $otherDetail)
                            .textInputAutocapitalization(.sentences)
                    }
                } header: {
                    Text("How did you find Jojo?")
                } footer: {
                    Text("This helps us learn which channels reach Japanese learners.")
                }
            }
            .navigationTitle("One quick question")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Not now") { onClose() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { submit() }
                        .fontWeight(.semibold)
                        .disabled(selected == nil)
                }
            }
        }
        .onAppear {
            selected = AcquisitionSource(rawValue: app.profile.acquisitionSource)
        }
    }

    @MainActor
    private func submit() {
        guard let selected else { return }
        app.profile.acquisitionSource = selected.rawValue
        app.save()
        UserDefaults.standard.set([
            "source": selected.rawValue,
            "detail": selected == .other ? otherDetail : "",
            "appUserId": app.purchases.appUserId
        ], forKey: InsightsService.pendingAcquisitionKey)
        track("acquisition_survey_submitted", props: ["source": selected.rawValue])
        onClose()
        Task { await InsightsService.shared.flushPendingAcquisition() }
    }
}
