import AVFoundation
import Speech

/// Speech-to-text using Apple's built-in recognizer (on-device when supported). Free, no API key.
@MainActor
final class SpeechRecognizer {
    var onPartial: ((String) -> Void)?

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: .current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var transcript = ""
    private var finalWaiter: CheckedContinuation<Void, Never>?

    func start() throws {
        reset()
        guard let recognizer, recognizer.isAvailable,
              SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw SidekickError.speechUnavailable
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0 else { throw SidekickError.noMicrophone }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        try engine.start()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let done = (result?.isFinal ?? false) || error != nil
            Task { @MainActor in
                guard let self else { return }
                if let text, !text.isEmpty {
                    self.transcript = text
                    self.onPartial?(text)
                }
                if done { self.resumeWaiter() }
            }
        }
    }

    /// Stops recording and returns the transcript (waits briefly for the final result).
    func stop() async -> String {
        stopAudio()
        if task != nil {
            await withCheckedContinuation { continuation in
                finalWaiter = continuation
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(700))
                    self.resumeWaiter()
                }
            }
        }
        task?.cancel()
        task = nil
        request = nil
        return transcript
    }

    private func reset() {
        stopAudio()
        task?.cancel()
        task = nil
        request = nil
        transcript = ""
        resumeWaiter()
    }

    private func stopAudio() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
    }

    private func resumeWaiter() {
        finalWaiter?.resume()
        finalWaiter = nil
    }
}
