// ساخت Social Preview برای گیت‌هاب — ۱۲۸۰×۶۴۰، رندر ۲x و کوچک‌نمایی برای وضوح کامل.
// usage: swift Scripts/make_social_preview.swift <plain|tagline> <in-screenshot.png> <logo.png> <out.png>
// plain   : اسکرین‌شات + لوگوی گوشه
// tagline : + پردهٔ تیرهٔ پایین، نام و شعار (متن برداری، همیشه تیز)
import AppKit

let args = CommandLine.arguments
guard args.count >= 5 else {
    FileHandle.standardError.write("usage: make_social_preview.swift <plain|tagline> <shot> <logo> <out>\n".data(using: .utf8)!)
    exit(1)
}
let mode = args[1], shotPath = args[2], logoPath = args[3], outPath = args[4]

let W: CGFloat = 1280, H: CGFloat = 640
let SS: CGFloat = 2                       // ضریب فرا‌نمونه (رندر ۲۵۶۰×۱۲۸۰ → خروجی ۱۲۸۰×۶۴۰)

guard let shot = NSImage(contentsOfFile: shotPath) else { print("shot load failed"); exit(1) }
guard let logo = NSImage(contentsOfFile: logoPath) else { print("logo load failed"); exit(1) }

// بوم ۲x با فضای کاربری ۱۲۸۰ (متن/شکل‌ها در مقیاس طراحی رسم، رستر در ۲۵۶۰)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                           pixelsWide: Int(W * SS), pixelsHigh: Int(H * SS),
                           bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: W, height: H)
guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { print("ctx failed"); exit(1) }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx

let canvas = NSRect(x: 0, y: 0, width: W, height: H)

// ۱) اسکرین‌شات: برش ۲:۱ از مرکز، پر کردن بوم
let sw = shot.size.width, sh = shot.size.height
let cropH = sw / 2
let cropY = max(0, (sh - cropH) / 2)
let crop = NSRect(x: 0, y: cropY, width: sw, height: min(cropH, sh))
shot.draw(in: canvas, from: crop, operation: .sourceOver, fraction: 1.0)

// ۲) پردهٔ تیرهٔ پایین (فقط حالت tagline)
if mode == "tagline" {
    let scrimH: CGFloat = 310
    let scrim = NSRect(x: 0, y: 0, width: W, height: scrimH)
    let gradient = NSGradient(colors: [NSColor.black.withAlphaComponent(0.0),
                                       NSColor.black.withAlphaComponent(0.78)])!
    // angle=-90 → رنگ اول بالا (شفاف)، رنگ دوم پایین (تیره)
    gradient.draw(in: scrim, angle: -90)
}

// ۳) لوگو — در tagline فقط بخش آیکون (بدون نوشتهٔ داخل لوگو، تا با شعار تداخل نکند)
let logoSide: CGFloat = mode == "tagline" ? 92 : 88
let logoDst = NSRect(x: 36, y: H - 36 - logoSide, width: logoSide, height: logoSide)
if mode == "tagline" {
    let s = logo.size
    let iconCrop = NSRect(x: 0, y: s.height * 0.30, width: s.width, height: s.height * 0.67)
    logo.draw(in: logoDst, from: iconCrop, operation: .sourceOver, fraction: 1.0)
} else {
    logo.draw(in: logoDst, from: .zero, operation: .sourceOver, fraction: 1.0)
}

// ۴) متن‌ها (برداری؛ Avenir با پشتیبان Helvetica)
if mode == "tagline" {
    func draw(_ text: String, size: CGFloat, fontNames: [String], color: NSColor, x: CGFloat, bottomY: CGFloat) {
        var font: NSFont = NSFont.boldSystemFont(ofSize: size)
        for n in fontNames { if let f = NSFont(name: n, size: size) { font = f; break } }
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let s = NSAttributedString(string: text, attributes: attrs)
        let box = NSRect(x: x, y: bottomY, width: W - x - 36, height: s.size().height + 4)
        s.draw(in: box)
    }
    draw("Neshank", size: 62,
         fontNames: ["AvenirNext-Bold", "HelveticaNeue-Bold"], color: NSColor.white.withAlphaComponent(0.97),
         x: 44, bottomY: 150)
    draw("Native, offline-first bookmark manager for macOS", size: 26,
         fontNames: ["AvenirNext-Medium", "HelveticaNeue-Medium"], color: NSColor.white.withAlphaComponent(0.92),
         x: 44, bottomY: 104)
    draw("AI chat · Mind maps · Video downloader", size: 22,
         fontNames: ["AvenirNext-Regular", "HelveticaNeue-Regular"], color: NSColor.white.withAlphaComponent(0.72),
         x: 44, bottomY: 64)
}

NSGraphicsContext.restoreGraphicsState()

// ۵) خروجی PNG (۲۵۶۰×۱۲۸۰ — کوچک‌نمایی به ۱۲۸۰×۶۴۰ بیرون از این اسکریپت با sips انجام می‌شود)
guard let data = rep.representation(using: .png, properties: [:]) else { print("png failed"); exit(1) }
do {
    try data.write(to: URL(fileURLWithPath: outPath))
    print("ok: \(outPath) (\(rep.pixelsWide)x\(rep.pixelsHigh))")
} catch {
    FileHandle.standardError.write("write failed: \(error)\n".data(using: .utf8)!)
    exit(1)
}
