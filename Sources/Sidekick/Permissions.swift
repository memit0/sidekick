import AVFoundation
import CoreGraphics
import Speech

enum Permissions {
    /// Triggers the macOS permission prompts on first launch.
    static func requestAll() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
        SFSpeechRecognizer.requestAuthorization { _ in }
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }
}
