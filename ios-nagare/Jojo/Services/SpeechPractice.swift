import AVFoundation
import Foundation
import Speech

enum SpeechListenResult: Sendable {
    case heard(String)
    case unavailable(String)
}

/// Listens for a short Japanese utterance and returns what the recognizer heard.
@MainActor
enum SpeechPractice {
    static func listen(seconds: Double = 4.5) async -> SpeechListenResult {
        let status = await withCheckedContinuation { (cont: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0) }
        }
        guard status == .authorized else {
            return .unavailable("Allow speech recognition to score how close you were.")
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP")), recognizer.isAvailable else {
            return .unavailable("Japanese speech recognition isn't available on this device.")
        }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            return .unavailable("The microphone couldn't start.")
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            return .unavailable("No microphone input on this device.")
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            return .unavailable("The microphone couldn't start.")
        }

        let box = TranscriptBox()
        let task = recognizer.recognitionTask(with: request) { result, _ in
            if let text = result?.bestTranscription.formattedString {
                box.set(text)
            }
        }
        try? await Task.sleep(for: .seconds(seconds))
        engine.stop()
        input.removeTap(onBus: 0)
        request.endAudio()
        task.cancel()

        let heard = box.get().trimmingCharacters(in: .whitespacesAndNewlines)
        if heard.isEmpty {
            return .unavailable("I didn't catch that. Hold the phone a little closer and try the line again.")
        }
        return .heard(heard)
    }

    /// 0–100 overlap between what was heard and the line.
    static func score(heard: String, target: String) -> Int {
        let h = normalize(heard)
        let t = normalize(target)
        guard !h.isEmpty, !t.isEmpty else { return 0 }
        if h == t || t.contains(h) || h.contains(t) { return 100 }
        let shared = lcsLength(Array(h), Array(t))
        let ratio = Double(shared) / Double(max(t.count, 1))
        return min(100, Int((ratio * 100).rounded()))
    }

    private static func normalize(_ text: String) -> String {
        let kana = JapaneseText.hiragana(text)
        return String(kana.filter { character in
            !character.isWhitespace && !"、。！？!?「」…・,. ".contains(character)
        })
    }

    private static func lcsLength(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty || b.isEmpty { return 0 }
        var previous = Array(repeating: 0, count: b.count + 1)
        var current = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            for j in 1...b.count {
                if a[i - 1] == b[j - 1] {
                    current[j] = previous[j - 1] + 1
                } else {
                    current[j] = max(previous[j], current[j - 1])
                }
            }
            previous = current
            current = Array(repeating: 0, count: b.count + 1)
        }
        return previous[b.count]
    }
}

private final class TranscriptBox: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""

    func set(_ value: String) {
        lock.lock()
        text = value
        lock.unlock()
    }

    func get() -> String {
        lock.lock()
        defer { lock.unlock() }
        return text
    }
}
