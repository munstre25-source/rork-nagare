import AVFoundation
import Foundation
import Speech

enum SpeechListenResult: Sendable {
    /// What the recognizer heard, and whether recognition stayed on the device.
    case heard(String, onDevice: Bool)
    case unavailable(String)
}

/// Listens for a short Japanese utterance and returns what the recognizer heard.
@MainActor
enum SpeechPractice {
    /// True while the microphone is open. Prompts and tips wait until speaking practice ends.
    static private(set) var isListening = false

    static func listen(seconds: Double = 4.5) async -> SpeechListenResult {
        isListening = true
        defer { isListening = false }
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
        // Keep the learner's voice on the phone whenever the Japanese model is installed.
        // Audio is streamed from memory; nothing is written to disk.
        let onDevice = recognizer.supportsOnDeviceRecognition
        request.requiresOnDeviceRecognition = onDevice
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
        try? session.setActive(false, options: .notifyOthersOnDeactivation)

        let heard = box.get().trimmingCharacters(in: .whitespacesAndNewlines)
        if heard.isEmpty {
            return .unavailable("I didn't catch that. Hold the phone a little closer and try the line again.")
        }
        return .heard(heard, onDevice: onDevice)
    }
}

/// Recognition similarity: how closely speech recognition's text matches the target line.
/// This is a text comparison, not a phonetic pronunciation score.
nonisolated enum SpeechScoring {
    /// 0–100. The better of a script comparison and a reading (romaji) comparison, so
    /// "今日" heard as "きょう" still counts. Saying only part of the line scores partially.
    static func score(heard: String, target: String) -> Int {
        let script = similarity(normalize(heard), normalize(target))
        let reading = similarity(romanized(heard), romanized(target))
        return max(script, reading)
    }

    /// Dice coefficient over the longest common subsequence: 2·LCS / (|a| + |b|).
    /// Symmetric, so both missing and extra characters lower the score.
    static func similarity(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        guard !x.isEmpty, !y.isEmpty else { return 0 }
        if x == y { return 100 }
        let shared = lcsLength(x, y)
        let dice = 2 * Double(shared) / Double(x.count + y.count)
        return min(100, max(0, Int((dice * 100).rounded())))
    }

    static func normalize(_ text: String) -> String {
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

    /// Latin transcription of Japanese text via the system tokenizer (kanji → reading).
    static func romanized(_ text: String) -> String {
        let source = normalize(text)
        guard !source.isEmpty else { return "" }
        let cf = source as CFString
        let range = CFRange(location: 0, length: CFStringGetLength(cf))
        guard let tokenizer = CFStringTokenizerCreate(
            kCFAllocatorDefault, cf, range, kCFStringTokenizerUnitWordBoundary, Locale(identifier: "ja_JP") as CFLocale
        ) else { return "" }
        var out = ""
        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            if let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String {
                out += latin
            } else {
                let tokenRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)
                if let piece = CFStringCreateWithSubstring(kCFAllocatorDefault, cf, tokenRange) as String? {
                    out += piece
                }
            }
        }
        return JapaneseText.normalizedRomaji(out).filter { $0.isLetter || $0.isNumber }
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
