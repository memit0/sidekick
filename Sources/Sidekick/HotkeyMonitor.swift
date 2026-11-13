import AppKit

/// Push-to-talk on Control + Option.
///
/// Polls the global modifier state instead of using an event tap, so it needs
/// no Accessibility permission.
@MainActor
final class HotkeyMonitor {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?

    private let required: NSEvent.ModifierFlags = [.control, .option]
    private var timer: Timer?
    private var isDown = false

    func start() {
        let timer = Timer(timeInterval: 0.03, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        let flags = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let down = flags.contains(required) && !flags.contains(.command) && !flags.contains(.shift)
        guard down != isDown else { return }
        isDown = down
        if down { onPress?() } else { onRelease?() }
    }
}
