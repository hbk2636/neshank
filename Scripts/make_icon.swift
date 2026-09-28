// ساخت آیکون برنامه — بدون هیچ وابستگی خارجی.
// usage: swift Scripts/make_icon.swift <out-1024.png> [out.icns] [source.png]
// خروجی اول: PNG بزرگ (برای پوشهٔ build) — خروجی دوم: فایل ICNS واقعی مک.
// آرگومان سوم: لوگوی مبدأ (اگر داده نشود، آیکون رویه‌ای قدیمی ساخته می‌شود).
import AppKit

func makeIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let inset = size * 0.03
    let rect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = size * 0.225
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    if let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.20, green: 0.48, blue: 0.96, alpha: 1.0),
        NSColor(calibratedRed: 0.36, green: 0.22, blue: 0.86, alpha: 1.0),
        NSColor(calibratedRed: 0.07, green: 0.14, blue: 0.45, alpha: 1.0)
    ]) {
        gradient.draw(in: path, angle: -70)
    }

    // برش روشن بالای آیکون
    NSColor.white.withAlphaComponent(0.13).setFill()
    let shine = NSBezierPath(
        roundedRect: NSRect(x: rect.minX + size * 0.05,
                            y: rect.midY,
                            width: rect.width - size * 0.1,
                            height: rect.height * 0.42),
        xRadius: radius * 0.7,
        yRadius: radius * 0.7
    )
    shine.fill()

    // نشان نشانک
    if let symbol = NSImage(systemSymbolName: "bookmark.fill", accessibilityDescription: nil) {
        let config = NSImage.SymbolConfiguration(pointSize: size * 0.46, weight: .bold)
        let configured = symbol.withSymbolConfiguration(config) ?? symbol
        let w = configured.size.width
        let h = configured.size.height
        let drawRect = NSRect(x: (size - w) / 2, y: (size - h) / 2 + size * 0.02,
                              width: w, height: h)
        NSColor.white.set()
        configured.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
    }

    image.unlockFocus()
    return image
}

/// رندر تصویر در یک اندازهٔ پیکسلی مشخص و خروجی PNG
func png(_ image: NSImage, pixels: Int) -> Data? {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }

    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    return rep.representation(using: .png, properties: [:])
}

/// ساخت فایل ICNS دستی (کانتینر + بلوک‌های PNG)
func writeICNS(_ image: NSImage, to path: String) -> Bool {
    // type → اندازهٔ پیکسلی
    let blocks: [(String, Int)] = [
        ("icp4", 16), ("ic11", 32),
        ("icp5", 32), ("ic12", 64),
        ("ic07", 128), ("ic13", 256),
        ("ic08", 256), ("ic09", 512),
        ("ic14", 512), ("ic10", 1024)
    ]

    var body = Data()
    for (type, px) in blocks {
        guard let data = png(image, pixels: px) else { continue }
        var chunk = Data(type.utf8)
        var len = UInt32(data.count + 8).bigEndian
        withUnsafeBytes(of: &len) { chunk.append(contentsOf: $0) }
        chunk.append(data)
        body.append(chunk)
    }
    guard !body.isEmpty else { return false }

    var file = Data("icns".utf8)
    var total = UInt32(body.count + 8).bigEndian
    withUnsafeBytes(of: &total) { file.append(contentsOf: $0) }
    file.append(body)

    do {
        try file.write(to: URL(fileURLWithPath: path))
        return true
    } catch {
        FileHandle.standardError.write("icns write failed: \(error)\n".data(using: .utf8)!)
        return false
    }
}

let args = CommandLine.arguments
guard args.count > 1 else {
    FileHandle.standardError.write("usage: swift make_icon.swift <output.png> [output.icns] [source.png]\n".data(using: .utf8)!)
    exit(1)
}

/// قرار دادن تصویر مبدأ در بوم مربعیِ شفاف (اگر مربع نباشد)
func squareCanvas(_ image: NSImage) -> NSImage {
    let w = image.size.width
    let h = image.size.height
    guard abs(w - h) > 0.5 else { return image }
    let side = max(w, h)
    let out = NSImage(size: NSSize(width: side, height: side))
    out.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: (side - w) / 2, y: (side - h) / 2, width: w, height: h))
    out.unlockFocus()
    return out
}

// لوگوی مبدأ (آرگومان سوم) یا آیکون رویه‌ای
var icon = makeIcon(size: 1024)
if args.count > 3 {
    guard let source = NSImage(contentsOfFile: args[3]) else {
        FileHandle.standardError.write("source image not readable: \(args[3])\n".data(using: .utf8)!)
        exit(1)
    }
    icon = squareCanvas(source)
}

// PNG
do {
    // رندر دقیق در ۱۰۲۴ پیکسل (نه نقطه)
    guard let data = png(icon, pixels: 1024) else { throw NSError(domain: "icon", code: 1) }
    try data.write(to: URL(fileURLWithPath: args[1]))
} catch {
    FileHandle.standardError.write("png failed: \(error)\n".data(using: .utf8)!)
    exit(1)
}

// ICNS (اختیاری)
if args.count > 2 {
    guard writeICNS(icon, to: args[2]) else { exit(1) }
}

print("ok")
