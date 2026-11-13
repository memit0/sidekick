import AppKit

@main
struct SidekickMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var modelMenu = NSMenu()
    private let overlay = OverlayController()
    private let hotkey = HotkeyMonitor()
    private let recognizer = SpeechRecognizer()
    private let speaker = Speaker()
    private let claude = ClaudeClient()

    private var shotTask: Task<ScreenCapture.Shot, Error>?
    private var turnTask: Task<Void, Never>?
    private var hideTask: Task<Void, Never>?

    private var ui: OverlayModel { overlay.model }

    func applicationDidFinishLaunching(_ notification: Notification) {
        ScreenCapture.cleanUp()
        setupMenu()
        overlay.show()
        Permissions.requestAll()

        recognizer.onPartial = { [weak self] text in
            guard let self, self.ui.phase == .listening else { return }
            self.ui.text = text
        }
        speaker.onFinish = { [weak self] in self?.finishSpeaking() }
        hotkey.onPress = { [weak self] in self?.startListening() }
        hotkey.onRelease = { [weak self] in self?.stopListening() }
        hotkey.start()
    }

    // MARK: - Turn flow

    private func startListening() {
        turnTask?.cancel(); turnTask = nil
        hideTask?.cancel(); hideTask = nil
        speaker.stop()
        overlay.clearPoint()

        // Grab the screen as it looks right now (the overlay is excluded from captures).
        shotTask = Task { try await ScreenCapture.take() }

        ui.text = ""
        ui.phase = .listening
        do {
            try recognizer.start()
        } catch {
            show(error)
        }
    }

    private func stopListening() {
        guard ui.phase == .listening else { return }
        turnTask = Task { await runTurn() }
    }

    private func runTurn() async {
        let question = await recognizer.stop().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else {
            ui.phase = .idle
            ui.text = ""
            return
        }
        ui.phase = .thinking
        ui.text = question

        do {
            guard let shotTask else { throw SidekickError.screenshotFailed }
            let shot = try await shotTask.value
            defer { try? FileManager.default.removeItem(at: shot.url) }

            let raw = try await claude.ask(question, shot: shot)
            try Task.checkCancellation()

            let reply = Reply.parse(raw)
            ui.phase = .speaking
            ui.text = reply.text
            if let p = reply.point {
                let local = CGPoint(
                    x: p.x / shot.pixelSize.width * shot.screenFrame.width,
                    y: p.y / shot.pixelSize.height * shot.screenFrame.height
                )
                overlay.point(at: local, on: shot.screenFrame, label: reply.label)
            }
            speaker.speak(reply.text)
        } catch is CancellationError {
            // a new press interrupted this turn
        } catch {
            if !Task.isCancelled { show(error) }
        }
    }

    private func finishSpeaking() {
        guard ui.phase == .speaking else { return }
        ui.phase = .idle
        scheduleHide(after: 6)
    }

    private func show(_ error: Error) {
        ui.phase = .error
        ui.text = error.localizedDescription
        scheduleHide(after: 8)
    }

    private func scheduleHide(after seconds: Double) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard let self, !Task.isCancelled else { return }
            if self.ui.phase == .idle || self.ui.phase == .error {
                self.ui.phase = .idle
                self.ui.text = ""
                self.overlay.clearPoint()
            }
        }
    }

    // MARK: - Menu bar

    private func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "cursorarrow.rays", accessibilityDescription: "Sidekick")

        let menu = NSMenu()
        let hint = NSMenuItem(title: "Hold ⌃ Control + ⌥ Option to talk", action: nil, keyEquivalent: "")
        hint.isEnabled = false
        menu.addItem(hint)
        menu.addItem(.separator())

        let newChat = NSMenuItem(title: "New Conversation", action: #selector(newConversation), keyEquivalent: "n")
        newChat.target = self
        menu.addItem(newChat)

        let modelItem = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
        for name in ["haiku", "sonnet", "opus"] {
            let item = NSMenuItem(title: name.capitalized, action: #selector(selectModel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = name
            modelMenu.addItem(item)
        }
        modelItem.submenu = modelMenu
        menu.addItem(modelItem)
        refreshModelMenu()

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Sidekick", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    @objc private func newConversation() {
        claude.reset()
        speaker.stop()
        overlay.clearPoint()
        ui.phase = .idle
        ui.text = ""
    }

    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        Settings.model = name
        refreshModelMenu()
    }

    private func refreshModelMenu() {
        for item in modelMenu.items {
            item.state = (item.representedObject as? String) == Settings.model ? .on : .off
        }
    }
}

enum Settings {
    /// Change from the menu, or: defaults write dev.sidekick.app model haiku
    static var model: String {
        get { UserDefaults.standard.string(forKey: "model") ?? "sonnet" }
        set { UserDefaults.standard.set(newValue, forKey: "model") }
    }
    /// Optional: defaults write dev.sidekick.app claudePath /path/to/claude
    static var claudePath: String? { UserDefaults.standard.string(forKey: "claudePath") }
    /// Optional: defaults write dev.sidekick.app voice com.apple.voice.premium.en-US.Zoe
    static var voice: String? { UserDefaults.standard.string(forKey: "voice") }
}

enum SidekickError: LocalizedError {
    case claudeNotFound
    case claudeFailed(String)
    case noMicrophone
    case speechUnavailable
    case screenshotFailed

    var errorDescription: String? {
        switch self {
        case .claudeNotFound:
            return "Couldn't find Claude Code. Install it, run `claude` once in Terminal to log in, then try again."
        case .claudeFailed(let message):
            return "Claude error: \(message)"
        case .noMicrophone:
            return "No microphone access. Allow it in System Settings → Privacy & Security → Microphone."
        case .speechUnavailable:
            return "Speech recognition isn't available. Allow it in System Settings → Privacy & Security → Speech Recognition."
        case .screenshotFailed:
            return "Couldn't capture the screen. Allow Sidekick in System Settings → Privacy & Security → Screen Recording, then relaunch it."
        }
    }
}
