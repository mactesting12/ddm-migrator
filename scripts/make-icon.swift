#!/usr/bin/env swift
import AppKit

// Renders the DDM Migrator app icon: a "fan-out" glyph (one source node
// splitting into the four DDM domains) on a blue→teal squircle — matching the
// app's accent palette. Produces a 1024px master PNG; build-app.sh turns it
// into the .iconset and AppIcon.icns. Pure, reproducible, no external deps.

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let S: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
                          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                          isPlanar: false, colorSpaceName: .deviceRGB,
                          bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Squircle background with the standard macOS icon margin (~10%).
let margin: CGFloat = 100
let rect = NSRect(x: margin, y: margin, width: S - margin * 2, height: S - margin * 2)
let radius = rect.width * 0.2237
let bg = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
bg.addClip()
NSGradient(starting: color(0x3B9BFF), ending: color(0x10B5A6))!.draw(in: bg, angle: -90)

// Glyph geometry: one source node on the left fanning out to four targets.
let cy = S / 2
let L = NSPoint(x: 372, y: cy)               // source node
let rightX: CGFloat = 690
let rys: [CGFloat] = [cy + 188, cy + 63, cy - 63, cy - 188]
let R = rys.map { NSPoint(x: rightX, y: $0) }

// Connector lines (drawn first, under the nodes).
let shadow = NSShadow()
shadow.shadowColor = color(0x0A3A66, 0.35)
shadow.shadowBlurRadius = 26
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()

color(0xFFFFFF, 0.96).setStroke()
for r in R {
    let p = NSBezierPath()
    p.lineWidth = 26
    p.lineCapStyle = .round
    p.move(to: L)
    p.curve(to: r,
            controlPoint1: NSPoint(x: L.x + 150, y: L.y),
            controlPoint2: NSPoint(x: r.x - 150, y: r.y))
    p.stroke()
}

// Nodes.
func dot(_ c: NSPoint, _ rad: CGFloat, _ col: NSColor) {
    col.setFill()
    NSBezierPath(ovalIn: NSRect(x: c.x - rad, y: c.y - rad, width: rad * 2, height: rad * 2)).fill()
}
dot(L, 58, color(0xFFFFFF))                  // source — white, larger
for r in R { dot(r, 38, color(0xEAFBFF)) }   // targets — slight cool tint

NSGraphicsContext.restoreGraphicsState()

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "app-icon/icon-1024.png"
let url = URL(fileURLWithPath: out)
try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                         withIntermediateDirectories: true)
try! rep.representation(using: .png, properties: [:])!.write(to: url)
print("wrote \(out)")
