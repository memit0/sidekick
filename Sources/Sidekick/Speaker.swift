import AVFoundation

/// Text-to-speech with the best built-in macOS voice available. Free, offline.
///
/// Tip: download a "Premium" or "Enhanced" voice in System Settings → Accessibility →
/// Spoken Content → System Voice → Manage Voices for much nicer speech.
@MainActor
final class Speaker: NSObject, AVSpeechSynthesizerDelegate {
    var onFinish: (() -> Void)?

    private let synth = AVSpeechSynthesizer()

    private lazy var voice: AVSpeechSynthesisVoice? = {
        if let id = Settings.voice, let v = AVSpeechSynthesisVoice(identifier: id) { return v }
        let lang = AVSpeechSynthesisVoice.currentLanguageCode()
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == lang }
        return voices.first { $0.quality == .premium }
            ?? voices.first { $0.quality == .enhanced }
            ?? AVSpeechSynthesisVoice(language: lang)
    }()

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ text: String) {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        synth.speak(utterance)
    }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.onFinish?() }
    }
}
