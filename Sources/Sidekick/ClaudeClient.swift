import Foundation

/// Talks to Claude through your locally installed Claude Code CLI (`claude -p`),
/// so usage counts against your Claude Pro/Max subscription instead of a paid API key.
@MainActor
final class ClaudeClient {
    private var sessionId: String?
    private var lastUse = Date.distantPast
    private var resolved: (exe: String, env: [String: String])?

    /// Start a fresh conversation (also happens automatically after 5 idle minutes).
    func reset() { sessionId = nil }

    func ask(_ question: String, shot: ScreenCapture.Shot) async throws -> String {
        let (exe, env) = try await locateClaude()
        if Date().timeIntervalSince(lastUse) > 300 { sessionId = nil }

        let image = try Data(contentsOf: shot.url)
        let w = Int(shot.pixelSize.width), h = Int(shot.pixelSize.height)
        let cx = Int(shot.cursorInImage.x), cy = Int(shot.cursorInImage.y)
        let text = """
        [Screenshot of the user's screen is attached: \(w)x\(h) px. Their mouse cursor is at (\(cx), \(cy)).]
        The user said: "\(question)"
        """

        let message: [String: Any] = [
            "type": "user",
            "message": [
                "role": "user",
                "content": [
                    ["type": "image", "source": ["type": "base64", "media_type": "image/jpeg", "data": image.base64EncodedString()]],
                    ["type": "text", "text": text],
                ],
            ],
        ]
        var input = try JSONSerialization.data(withJSONObject: message)
        input.append(0x0A)

        var args = [
            "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",
            "--model", Settings.model,
            "--append-system-prompt", Self.systemPrompt,
            "--allowedTools", "WebSearch,WebFetch",
            "--strict-mcp-config",
        ]
        if let sessionId { args += ["--resume", sessionId] }

        let result = try await Shell.run(exe, args, env: env, cwd: ScreenCapture.workDir, stdin: input, timeout: 180)

        var answer: String?
        var isError = false
        for line in result.stdout.split(separator: "\n") {
            guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  json["type"] as? String == "result" else { continue }
            answer = json["result"] as? String
            isError = json["is_error"] as? Bool ?? false
            if let sid = json["session_id"] as? String { sessionId = sid }
        }

        guard let answer, !isError else {
            sessionId = nil
            let detail = answer ?? result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SidekickError.claudeFailed(detail.isEmpty ? "exit code \(result.status)" : String(detail.suffix(300)))
        }
        lastUse = Date()
        return answer
    }

    /// GUI apps don't get your shell's PATH, so borrow it from a login shell once.
    private func locateClaude() async throws -> (String, [String: String]) {
        if let resolved { return resolved }

        var env = ProcessInfo.processInfo.environment
        var path = env["PATH"] ?? "/usr/bin:/bin"
        let shell = env["SHELL"] ?? "/bin/zsh"
        if let r = try? await Shell.run(shell, ["-ilc", "printf '__SKPATH__%s\\n' \"$PATH\""], timeout: 8),
           let line = r.stdout.split(separator: "\n").last(where: { $0.hasPrefix("__SKPATH__") }) {
            path = String(line.dropFirst("__SKPATH__".count))
        }

        let home = NSHomeDirectory()
        let dirs = path.split(separator: ":").map(String.init)
            + ["\(home)/.local/bin", "\(home)/.claude/local", "/opt/homebrew/bin", "/usr/local/bin"]
        env["PATH"] = dirs.joined(separator: ":")

        // Make sure Claude Code uses your subscription login, not an API key.
        env.removeValue(forKey: "ANTHROPIC_API_KEY")
        env.removeValue(forKey: "ANTHROPIC_AUTH_TOKEN")

        let candidates = [Settings.claudePath].compactMap { $0 } + dirs.map { "\($0)/claude" }
        guard let exe = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw SidekickError.claudeNotFound
        }
        resolved = (exe, env)
        return (exe, env)
    }

    static let systemPrompt = """
    You are Sidekick, a friendly voice assistant that lives next to the user's mouse cursor on macOS. \
    Each message comes with a screenshot of the screen the user is looking at, plus where their cursor is.

    Your reply is read aloud by text-to-speech, so:
    - Keep it short: one to three sentences unless they ask for detail.
    - Sound natural and conversational. No markdown, bullet lists, code blocks, emojis or URLs.
    - Never mention screenshots, pixels or coordinates out loud. Talk about what's on screen as if you can see it.
    - If they ask how to do something, give the next step or two, not a long tutorial.

    When pointing at something on screen would help (a button, menu, field, link), add this tag on its own \
    line at the very end of your reply: [POINT:x,y:short label]
    x,y are pixel coordinates in the screenshot (top-left origin) at the center of the element. \
    Use at most one tag, and only when it's genuinely useful.
    """
}

struct Reply {
    var text: String
    var point: CGPoint? = nil
    var label: String? = nil

    static func parse(_ raw: String) -> Reply {
        let pattern = #"\[POINT:\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*(?::\s*([^\]]*))?\]"#
        let range = NSRange(raw.startIndex..., in: raw)
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: raw, range: range) else {
            return Reply(text: clean(raw))
        }
        func group(_ i: Int) -> String? {
            guard let r = Range(match.range(at: i), in: raw) else { return nil }
            return String(raw[r])
        }
        let stripped = regex.stringByReplacingMatches(in: raw, range: range, withTemplate: "")
        var reply = Reply(text: clean(stripped))
        if let x = group(1).flatMap(Double.init), let y = group(2).flatMap(Double.init) {
            reply.point = CGPoint(x: x, y: y)
            reply.label = group(3)?.trimmingCharacters(in: .whitespaces)
        }
        return reply
    }

    private static func clean(_ s: String) -> String {
        var t = s
        for token in ["**", "__", "`", "# "] { t = t.replacingOccurrences(of: token, with: "") }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
