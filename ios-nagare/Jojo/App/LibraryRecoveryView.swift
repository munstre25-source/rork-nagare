import SwiftUI

/// Shown when the on-disk library cannot be opened. The app does not continue on a memory store.
struct LibraryRecoveryView: View {
    let onRetry: () -> Void
    let onReset: () -> Void
    @State private var confirmReset = false

    var body: some View {
        VStack(spacing: Spacing.l) {
            Spacer()
            Image(systemName: "books.vertical")
                .font(.system(size: 44))
                .foregroundStyle(Color.jojoOrange)
            Text("Couldn’t open your library")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text("Jojo couldn’t read the words and clips saved on this device. You can try again, or reset the library and start fresh.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Retry", action: onRetry)
                .buttonStyle(PrimaryButtonStyle())
            Button("Reset library") { confirmReset = true }
                .font(.headline)
                .foregroundStyle(.red)
                .frame(minHeight: 44)
        }
        .padding(Spacing.xl)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.canvas.ignoresSafeArea())
        .confirmationDialog("Reset your library?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset library", role: .destructive, action: onReset)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This erases words, watch history, and settings stored on this device.")
        }
    }
}
