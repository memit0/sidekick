// Draws the 1024x1024 app icon PNG. Usage: swift Resources/make-icon.swift out.png
import AppKit

let S: CGFloat = 1024
let ctx = CGContext(data: nil, width: Int(S), height: Int(S), bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.translateBy(x: 0, y: S); ctx.scaleBy(x: 1, y: -1) // top-left origin
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
let space = CGColorSpace(name: CGColorSpace.sRGB)!

// Squircle background: 824pt tile with 100pt margin (macOS Big Sur grid).
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 24, color: rgb(0, 0, 0, 0.35))
ctx.addPath(tilePath); ctx.setFillColor(rgb(0.2, 0.2, 0.5)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(tilePath); ctx.clip()
let bg = CGGradient(colorsSpace: space, colors: [rgb(0.36, 0.33, 0.92), rgb(0.10, 0.12, 0.42)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 924), options: [])
ctx.restoreGState()

// Buddy dot: soft glow + solid core, down-right of the cursor tip.
let dot = CGPoint(x: 700, y: 690)
let glow = CGGradient(colorsSpace: space, colors: [rgb(0.35, 0.75, 1, 0.9), rgb(0.35, 0.75, 1, 0)] as CFArray, locations: [0, 1])!
ctx.saveGState(); ctx.addPath(tilePath); ctx.clip()
ctx.drawRadialGradient(glow, startCenter: dot, startRadius: 0, endCenter: dot, endRadius: 190, options: [])
ctx.restoreGState()
let core = CGGradient(colorsSpace: space, colors: [rgb(0.88, 0.97, 1), rgb(0.40, 0.78, 1), rgb(0.20, 0.55, 1)] as CFArray, locations: [0, 0.55, 1])!
ctx.saveGState(); ctx.addEllipse(in: CGRect(x: dot.x - 64, y: dot.y - 64, width: 128, height: 128)); ctx.clip()
ctx.drawRadialGradient(core, startCenter: CGPoint(x: dot.x - 18, y: dot.y - 18), startRadius: 0, endCenter: dot, endRadius: 64, options: [])
ctx.restoreGState()

// Cursor arrow (unit grid, tip at origin), scaled and placed.
let pts: [(CGFloat, CGFloat)] = [(0, 0), (0, 17), (4, 13.2), (6.8, 19.6), (9.6, 18.4), (6.9, 12.2), (12.2, 12.2)]
let k: CGFloat = 24, origin = CGPoint(x: 310, y: 225)
let arrow = CGMutablePath()
arrow.addLines(between: pts.map { CGPoint(x: origin.x + $0.0 * k, y: origin.y + $0.1 * k) }); arrow.closeSubpath()
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: rgb(0, 0, 0.1, 0.45))
ctx.addPath(arrow); ctx.setFillColor(rgb(1, 1, 1)); ctx.fillPath()
ctx.restoreGState()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
