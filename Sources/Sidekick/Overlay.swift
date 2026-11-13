import AppKit
import SwiftUI

@MainActor
final class OverlayModel: ObservableObject {
    enum Phase { case idle, listening, thinking, speaking, error }

    @Published var phase: Phase = .idle
    @Published var text = ""
    @Published var cursor: CGPoint = .zero   // top-left origin, window coordinates
    @Published var size: CGSize = .zero
    @Published var target: CGPoint?
    @Published var targetLabel: String?
}

/// A transparent, click-through window over the current screen that draws the buddy next to the cursor.
@MainActor
final class OverlayController {
    let model = OverlayModel()

    private var window: NSWindow!
    private var timer: Timer?
    private var screenFrame: NSRect = .zero
    private var pinnedFrame: NSRect? // keeps the overlay on one screen while pointing

    func show() {
        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .screenSaver
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.sharingType = .none // keep the overlay out of screenshots
        window.contentView = NSHostingView(rootView: OverlayView(model: model))
        window.orderFrontRegardless()
        self.window = window

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func point(at local: CGPoint, on frame: NSRect, label: String?) {
        pinnedFrame = frame
        move(to: frame)
        model.target = local
        model.targetLabel = (label?.isEmpty ?? true) ? nil : label
    }

    func clearPoint() {
        pinnedFrame = nil
        model.target = nil
        model.targetLabel = nil
    }

    private func tick() {
        let mouse = NSEvent.mouseLocation
        let frame = pinnedFrame
            ?? NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) })?.frame
            ?? screenFrame
        move(to: frame)
        let p = CGPoint(x: mouse.x - frame.minX, y: frame.maxY - mouse.y)
        if p != model.cursor { model.cursor = p }
    }

    private func move(to frame: NSRect) {
        guard frame != screenFrame else { return }
        screenFrame = frame
        window.setFrame(frame, display: true)
        model.size = frame.size
    }
}

// MARK: - Views

struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        let anchor = model.target ?? model.cursor
        ZStack(alignment: .topLeading) {
            Color.clear

            if let target = model.target {
                TargetMarker(label: model.targetLabel)
                    .position(target)
                    .transition(.opacity)
            }

            BuddyDot(phase: model.phase)
                .position(x: anchor.x + 16, y: anchor.y + 16)

            if model.phase != .idle || !model.text.isEmpty {
                Bubble(model: model)
                    .frame(maxWidth: 320, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .offset(bubbleOffset(for: anchor))
                    .transition(.opacity)
            }
        }
        .frame(width: model.size.width, height: model.size.height, alignment: .topLeading)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: anchor)
        .animation(.easeInOut(duration: 0.2), value: model.phase)
    }

    private func bubbleOffset(for a: CGPoint) -> CGSize {
        var x = a.x + 30, y = a.y + 30
        if x + 330 > model.size.width { x = a.x - 350 }
        if y + 180 > model.size.height { y = a.y - 190 }
        return CGSize(width: max(8, x), height: max(8, y))
    }
}

struct BuddyDot: View {
    let phase: OverlayModel.Phase
    @State private var pulse = false

    private var color: Color {
        switch phase {
        case .idle: return .blue
        case .listening: return .red
        case .thinking: return .orange
        case .speaking: return .green
        case .error: return .gray
        }
    }

    var body: some View {
        ZStack {
            if phase == .listening || phase == .thinking {
                Circle()
                    .stroke(color, lineWidth: 2)
                    .frame(width: 14, height: 14)
                    .scaleEffect(pulse ? 2.2 : 1)
                    .opacity(pulse ? 0 : 0.8)
                    .onAppear { pulse = false; withAnimation(.easeOut(duration: 1).repeatForever(autoreverses: false)) { pulse = true } }
            }
            Circle()
                .fill(color)
                .frame(width: 12, height: 12)
                .shadow(color: color.opacity(0.6), radius: 4)
        }
    }
}

struct Bubble: View {
    @ObservedObject var model: OverlayModel

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            switch model.phase {
            case .listening:
                Image(systemName: "mic.fill").foregroundStyle(.red)
                Text(model.text.isEmpty ? "Listening…" : model.text)
            case .thinking:
                ProgressView().controlSize(.small)
                Text("Thinking…").foregroundStyle(.secondary)
            case .error:
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                Text(model.text)
            case .speaking, .idle:
                Text(model.text)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.2), radius: 8, y: 2)
    }
}

struct TargetMarker: View {
    let label: String?
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(Color.accentColor, lineWidth: 3)
                    .frame(width: 34, height: 34)
                    .scaleEffect(pulse ? 1.25 : 0.9)
                Circle()
                    .fill(Color.accentColor.opacity(0.18))
                    .frame(width: 34, height: 34)
            }
            if let label {
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .onAppear { withAnimation(.easeInOut(duration: 0.7).repeatForever()) { pulse = true } }
    }
}
