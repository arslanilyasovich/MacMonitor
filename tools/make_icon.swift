// MacMonitor uygulama ikonunu assets/logo.png'den üretir: swift make_icon.swift logo.png cikti.png
// Logo kendi koyu zemininde bir yuvarlatılmış kare içeriyor; kare kesilip dışı şeffaf yapılır ve
// macOS ikon ızgarasına (1024'lük tuvalde 824'lük gövde, hafif gölge) yerleştirilir.
import AppKit

let args = CommandLine.arguments
let src = NSImage(contentsOfFile: args[1])!
let out = args.count > 2 ? args[2] : "icon_1024.png"

// Kaynak logoda karenin kenarları (1254 px görselde ölçüldü): x/y ≈ 92…1160, köşe yarıçapı ≈ 250
let srcSize = src.representations.first.map { CGFloat($0.pixelsWide) } ?? 1254
let k = srcSize / 1254
let crop = NSRect(x: 91 * k, y: 91 * k, width: 1072 * k, height: 1072 * k)

let size = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high

let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let radius: CGFloat = 824 * 250 / 1072
let shape = NSBezierPath(roundedRect: body, xRadius: radius, yRadius: radius)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.4)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.set()
NSColor(srgbRed: 0.04, green: 0.07, blue: 0.14, alpha: 1).setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.saveGraphicsState()
shape.addClip()
// NSImage koordinatları alttan başlar: kırpma alanı simetrik olduğu için fark etmez
src.draw(in: body, from: crop, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
