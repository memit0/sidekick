import AppKit
import ImageIO

enum ScreenCapture {
    struct Shot {
        let url: URL
        let pixelSize: CGSize      // size of the (downscaled) image sent to Claude
        let screenFrame: NSRect    // the captured screen, in global AppKit coordinates
        let cursorInImage: CGPoint // mouse position in image pixels (top-left origin)
        var marked = false         // a highlight stroke was drawn onto the image
    }

    /// Paints the user's highlight stroke (global AppKit coordinates) onto the screenshot file.
    /// The overlay is excluded from captures, so the stroke has to be added afterwards.
    static func drawMarker(_ points: [NSPoint], on shot: inout Shot) {
        guard points.count > 1,
              let source = CGImageSourceCreateWithURL(shot.url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        let f = shot.screenFrame
        let scale = CGFloat(image.width) / f.width
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        // CoreGraphics and AppKit both use a bottom-left origin, so only offset and scale.
        ctx.addLines(between: points.map { CGPoint(x: ($0.x - f.minX) * scale, y: ($0.y - f.minY) * scale) })
        ctx.setStrokeColor(red: 1, green: 0, blue: 0, alpha: 0.6)
        ctx.setLineWidth(10 * scale)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        ctx.strokePath()
        guard let marked = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(shot.url as CFURL, "public.jpeg" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, marked, nil)
        if CGImageDestinationFinalize(dest) { shot.marked = true }
    }

    static let workDir: URL = {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sidekick", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Captures the screen the mouse is on, downscaled so the long side is at most 1568px.
    @MainActor
    static func take() async throws -> Shot {
        // Without permission, screencapture silently returns only the wallpaper (no windows).
        guard CGPreflightScreenCaptureAccess() else { throw SidekickError.screenshotFailed }
        let mouse = NSEvent.mouseLocation
        let screens = NSScreen.screens
        let index = screens.firstIndex { NSMouseInRect(mouse, $0.frame, false) } ?? 0
        guard index < screens.count else { throw SidekickError.screenshotFailed }
        let frame = screens[index].frame

        let url = workDir.appendingPathComponent("screen-\(UUID().uuidString).jpg")
        try await Shell.run("/usr/sbin/screencapture", ["-x", "-t", "jpg", "-D", "\(index + 1)", url.path], timeout: 10)
        guard FileManager.default.fileExists(atPath: url.path) else { throw SidekickError.screenshotFailed }
        try await Shell.run("/usr/bin/sips", ["-Z", "1568", url.path], timeout: 10)

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else {
            throw SidekickError.screenshotFailed
        }

        let cursor = CGPoint(
            x: (mouse.x - frame.minX) / frame.width * CGFloat(width),
            y: (frame.maxY - mouse.y) / frame.height * CGFloat(height)
        )
        return Shot(url: url, pixelSize: CGSize(width: width, height: height), screenFrame: frame, cursorInImage: cursor)
    }

    /// Removes leftover screenshots from earlier runs.
    static func cleanUp() {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(at: workDir, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "jpg" {
            try? fm.removeItem(at: file)
        }
    }
}
