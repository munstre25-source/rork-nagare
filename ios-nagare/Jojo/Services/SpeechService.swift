import AVFoundation

/// Speaks Japanese words with AVSpeechSynthesizer using a ja-JP voice.
@MainActor
final class SpeechService {
    static let shared = SpeechService()
    private let synthesizer = AVSpeechSynthesizer()
    private lazy var voice: AVSpeechSynthesisVoice? = {
        let jaVoices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "ja-JP" }
        return jaVoices.first { $0.quality == .enhanced } ?? jaVoices.first ?? AVSpeechSynthesisVoice(language: "ja-JP")
    }()

    func speak(_ text: String, rate: Float = 0.42) {
        guard !text.isEmpty else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[Speech] audio session error: \(error.localizedDescription)")
        }
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = rate
        utterance.pitchMultiplier = 1.0
        synthesizer.speak(utterance)
    }
}
