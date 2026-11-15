import AVFoundation

/// Text-to-speech with the best built-in macOS voice available. Free, offline.
///
/// Tip: download a "Premium" or "Enhanced" voice in System Settings → Accessibility →
/// Spoken Content → System Voice → Manage Voices for much nicer speech.
@MainActor
final class Speaker: NSObject, AVSpeechSynthesizerDelegate, AVAudioPlayerDelegate {
    var onFinish: (() -> Void)?

    private let synth = AVSpeechSynthesizer()

    // ponytail: hardcoded Piper install path; make it a setting if anyone else installs it elsewhere.
    private static let piperDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".local/share/piper")
    private static let piper = piperDir.appendingPathComponent("venv/bin/piper").path
    private static let piperModel = piperDir.appendingPathComponent("en_US-lessac-medium.onnx").path
    private var piperTask: Task<Void, Never>?
    private var player: AVAudioPlayer?

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
        guard FileManager.default.isExecutableFile(atPath: Self.piper) else { return speakApple(text) }
        let wav = FileManager.default.temporaryDirectory.appendingPathComponent("sidekick-speech.wav")
        piperTask = Task {
            let result = try? await Shell.run(
                Self.piper, ["-m", Self.piperModel, "-f", wav.path],
                stdin: Data(text.utf8), timeout: 30)
            guard !Task.isCancelled else { return }
            if result?.status == 0, let p = try? AVAudioPlayer(contentsOf: wav) {
                p.delegate = self
                player = p
                p.play()
            } else {
                speakApple(text) // Piper failed: fall back to the built-in voice.
            }
        }
    }

    private func speakApple(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05
        synth.speak(utterance)
    }

    func stop() {
        piperTask?.cancel()
        piperTask = nil
        player?.stop()
        player = nil
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.onFinish?() }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.onFinish?() }
    }
}
