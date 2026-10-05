import SwiftUI
import Vision
import PhotosUI

/// A dictionary word found inside text read from a photo or screenshot.
struct CaptureHit: Identifiable, Hashable, Sendable {
    let key: String
    let surface: String
    let reading: String
    let romaji: String
    let pos: String
    let conjugationClass: String?
    let jlpt: String?
    let definitions: [String]
    let jaDefinitions: [String]
    let sentence: String

    var id: String { key }
    var gloss: String { definitions.first ?? jaDefinitions.first ?? "" }
}

/// Reads Japanese out of a picture and matches it to the bundled dictionary.
enum JapaneseCapture {
    static func recognizeLines(in image: UIImage) async -> [String] {
        let upright = uprightImage(image)
        guard let cgImage = upright.cgImage else { return [] }
        let gate = ResumeGate()
        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, _ in
                let lines = (request.results as? [VNRecognizedTextObservation])?.compactMap {
                    $0.topCandidates(1).first?.string
                } ?? []
                gate.resume(continuation, with: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            if let languages = try? VNRecognizeTextRequest.supportedRecognitionLanguages(
                for: .accurate,
                revision: VNRecognizeTextRequest.currentRevision
            ), languages.contains("ja-JP") {
                request.recognitionLanguages = ["ja-JP"]
            }
            let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
            do {
                try handler.perform([request])
            } catch {
                gate.resume(continuation, with: [])
            }
        }
    }

    /// Longest dictionary match across each recognized line. Particles are left out so a menu or sign yields words.
    static func hits(in lines: [String], lexicon: LocalLexicon) -> [CaptureHit] {
        var seen: Set<String> = []
        var found: [CaptureHit] = []
        for line in lines {
            let sentence = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sentence.isEmpty else { continue }
            for (surface, entry) in matches(in: sentence, lexicon: lexicon) {
                let reading = entry.baseReading ?? entry.readings.first ?? ""
                let form = entry.baseForm ?? surface
                let key = SavedWord.makeKey(surface: form, reading: reading)
                guard seen.insert(key).inserted else { continue }
                found.append(CaptureHit(
                    key: key,
                    surface: form,
                    reading: reading,
                    romaji: entry.baseRomaji ?? entry.romaji,
                    pos: entry.pos,
                    conjugationClass: entry.conjugationClass,
                    jlpt: entry.jlpt,
                    definitions: entry.definitions,
                    jaDefinitions: entry.jaDefinitions,
                    sentence: sentence
                ))
            }
        }
        return found
    }

    private static func matches(in line: String, lexicon: LocalLexicon) -> [(String, DictionaryEntry)] {
        let chars = Array(line)
        var index = 0
        var found: [(String, DictionaryEntry)] = []
        while index < chars.count {
            var consumed = 1
            let longest = min(12, chars.count - index)
            for length in stride(from: longest, through: 1, by: -1) {
                let surface = String(chars[index..<(index + length)])
                guard let entry = lexicon.entry(for: surface) else { continue }
                if entry.pos == "particle" { continue }
                found.append((surface, entry))
                consumed = length
                break
            }
            index += consumed
        }
        return found
    }

    private static func uprightImage(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}

private final class ResumeGate: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false

    func resume(_ continuation: CheckedContinuation<[String], Never>, with value: [String]) {
        lock.lock()
        let already = resumed
        resumed = true
        lock.unlock()
        guard !already else { return }
        continuation.resume(returning: value)
    }
}

/// Photo or screenshot → Japanese words the learner can save.
struct CaptureJapaneseView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var lines: [String] = []
    @State private var hits: [CaptureHit] = []
    @State private var saved: Set<String> = []
    @State private var scanning = false
    @State private var didScan = false

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Point Jojo at a sign, menu, manga page, or screenshot. Words it recognizes can be saved as cards.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Choose a photo", systemImage: "photo")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(Color.sakuraFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(scanning)

                    if cameraAvailable {
                        Button {
                            showCamera = true
                        } label: {
                            Label("Take a photo", systemImage: "camera")
                                .font(.headline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, minHeight: 48)
                                .background(Color.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.cardStroke))
                        }
                        .buttonStyle(.plain)
                        .disabled(scanning)
                    }

                    if scanning {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Reading the Japanese…")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else if didScan {
                        results
                    }
                }
                .padding(20)
            }
            .background(Color.canvas.ignoresSafeArea())
            .navigationTitle("From a photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await load(item) }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraCapture { image in
                    showCamera = false
                    if let image { Task { await scan(image) } }
                }
            }
        }
    }

    @ViewBuilder
    private var results: some View {
        if hits.isEmpty {
            Text(lines.isEmpty
                 ? "No Japanese turned up in that photo. Try a closer shot of the text."
                 : "Jojo read the photo, but those words are not in the built-in dictionary yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if !lines.isEmpty {
                Text(lines.joined(separator: "\n"))
                    .font(JojoFont.jp(16, relativeTo: .body))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        } else {
            Text("\(hits.count) words")
                .font(.headline)
            ForEach(hits) { hit in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(hit.surface)
                            .font(JojoFont.jp(22, bold: true, relativeTo: .title3))
                            .lineLimit(1)
                        if !hit.reading.isEmpty || !hit.romaji.isEmpty {
                            Text([hit.reading, hit.romaji].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if !hit.gloss.isEmpty {
                            Text(hit.gloss)
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                                .lineLimit(2)
                        }
                        Text(hit.sentence)
                            .font(JojoFont.jp(14, relativeTo: .footnote))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 8)
                    Button {
                        Haptics.success()
                        app.saveCaptured(hit: hit)
                        saved.insert(hit.key)
                        DailyPlanProgress.mark(.capture)
                    } label: {
                        Image(systemName: saved.contains(hit.key) ? "checkmark.circle.fill" : "plus.circle.fill")
                            .font(.system(size: 28))
                            .foregroundStyle(saved.contains(hit.key) ? Color.spokenGreen : Color.designOrange)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .disabled(saved.contains(hit.key))
                    .accessibilityLabel(saved.contains(hit.key) ? "Saved \(hit.surface)" : "Save \(hit.surface)")
                }
                .padding(14)
                .background(Color.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.cardStroke))
            }
        }
    }

    private func load(_ item: PhotosPickerItem) async {
        scanning = true
        defer { scanning = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            didScan = true
            lines = []
            hits = []
            return
        }
        await scan(image)
    }

    private func scan(_ image: UIImage) async {
        scanning = true
        defer { scanning = false }
        let recognized = await JapaneseCapture.recognizeLines(in: image)
        lines = recognized
        hits = JapaneseCapture.hits(in: recognized, lexicon: app.lexicon)
        didScan = true
        track("capture_scanned", props: ["lines": String(recognized.count), "words": String(hits.count)])
    }
}

private struct CameraCapture: UIViewControllerRepresentable {
    var onImage: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onImage: onImage) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage?) -> Void
        init(onImage: @escaping (UIImage?) -> Void) { self.onImage = onImage }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onImage(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onImage(nil)
        }
    }
}

/// Which pieces of today's plan are already done. Resets with the calendar day.
enum DailyPlanProgress {
    enum Step: String {
        case review, watch, speak, capture
    }

    private static func key(_ step: Step) -> String {
        let day = Calendar.current.startOfDay(for: Date()).timeIntervalSince1970
        return "jojo.plan.\(Int(day)).\(step.rawValue)"
    }

    static func mark(_ step: Step) {
        UserDefaults.standard.set(true, forKey: key(step))
    }

    static func isDone(_ step: Step) -> Bool {
        UserDefaults.standard.bool(forKey: key(step))
    }
}
