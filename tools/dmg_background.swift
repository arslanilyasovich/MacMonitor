// .dmg kurulum penceresinin arka planını çizer: swift dmg_background.swift cikti.png
// Pencere 640x400; simgeler (160,190) ve (480,190) noktalarına yerleştirilir.
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "background.png"
let scale = 2 // Retina için 2x çiz, 1280x800
let w = 640 * scale, h = 400 * scale

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: 640, height: 400)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

let full = NSRect(x: 0, y: 0, width: 640, height: 400)
NSGradient(colors: [rgb(10, 18, 38), rgb(7, 12, 26)])!.draw(in: full, angle: -90)
NSGradient(colors: [rgb(31, 102, 245, 0.28), rgb(31, 102, 245, 0)])!
    .draw(fromCenter: NSPoint(x: 600, y: 380), radius: 0, toCenter: NSPoint(x: 600, y: 380), radius: 360, options: [])
NSGradient(colors: [rgb(51, 133, 255, 0.10), rgb(51, 133, 255, 0)])!
    .draw(fromCenter: NSPoint(x: 40, y: 20), radius: 0, toCenter: NSPoint(x: 40, y: 20), radius: 320, options: [])

func text(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor, y: CGFloat) {
    let p = NSMutableParagraphStyle()
    p.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                .foregroundColor: color, .paragraphStyle: p]
    NSAttributedString(string: s, attributes: attrs).draw(in: NSRect(x: 0, y: y, width: 640, height: size * 1.5))
}

// Finder koordinatı üstten, çizim alttan ölçülür: simge merkezi y = 400 - 190 = 210
text("MacMonitor", 26, .bold, .white, y: 336)

// sağ altta imza
let sigAttrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .regular), .foregroundColor: rgb(255, 255, 255, 0.5)]
let sig = NSMutableAttributedString(string: "by ", attributes: sigAttrs)
sig.append(NSAttributedString(string: "Arslan", attributes: [.font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: rgb(69, 163, 255)]))
sig.draw(at: NSPoint(x: 640 - sig.size().width - 16, y: 10))
text("Kurmak için simgeyi Uygulamalar klasörüne sürükle  ·  Drag the icon to Applications", 12, .regular, rgb(255, 255, 255, 0.6), y: 308)

// Ok: iki simge arasında, logodaki mavi
let arrow = NSBezierPath()
arrow.move(to: NSPoint(x: 252, y: 210))
arrow.line(to: NSPoint(x: 372, y: 210))
arrow.lineWidth = 5
arrow.lineCapStyle = .round
let head = NSBezierPath()
head.move(to: NSPoint(x: 356, y: 226))
head.line(to: NSPoint(x: 376, y: 210))
head.line(to: NSPoint(x: 356, y: 194))
head.lineWidth = 5
head.lineCapStyle = .round
head.lineJoinStyle = .round
rgb(69, 163, 255).setStroke()
arrow.stroke()
head.stroke()

text("İlk açılış: Sistem Ayarları › Gizlilik ve Güvenlik › Yine de Aç", 11, .medium, rgb(255, 190, 77, 0.9), y: 52)
text("First launch: System Settings › Privacy & Security › Open Anyway", 11, .regular, rgb(255, 255, 255, 0.45), y: 34)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
