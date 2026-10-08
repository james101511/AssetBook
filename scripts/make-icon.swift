// 產生 App 圖示：swiftc scripts/make-icon.swift -o build/make-icon && build/make-icon Resources/AppIcon.png
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// macOS 圖示格線：824×824 的圓角方形置中
let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let shape = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
NSColor.white.setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

NSGradient(colors: [NSColor(red: 0.36, green: 0.42, blue: 1.0, alpha: 1),
                    NSColor(red: 0.20, green: 0.24, blue: 0.80, alpha: 1)])!
    .draw(in: shape, angle: -90)

let config = NSImage.SymbolConfiguration(pointSize: 420, weight: .semibold)
    .applying(.init(paletteColors: [.white]))
if let symbol = NSImage(systemSymbolName: "chart.pie.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let s = symbol.size
    symbol.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2, width: s.width, height: s.height))
}
image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
