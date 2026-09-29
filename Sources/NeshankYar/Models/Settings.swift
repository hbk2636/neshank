import SwiftUI

// MARK: - تنظیمات رابط (بین اجراها حفظ می‌شوند)

/// حالت روشنایی
enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return L.tr("System")
        case .light: return L.tr("Light")
        case .dark: return L.tr("Dark")
        }
    }

    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// چگالی فهرست
enum Density: String, CaseIterable, Identifiable {
    case compact, comfortable
    var id: String { rawValue }

    var label: String {
        switch self {
        case .compact: return L.tr("Compact")
        case .comfortable: return L.tr("Comfortable")
        }
    }

    var rowPadding: CGFloat { self == .compact ? 1 : 3 }
    var titleSize: CGFloat { self == .compact ? 12.5 : 13 }
    var gridSpacing: CGFloat { self == .compact ? 10 : 14 }
    var thumbnailHeight: CGFloat { self == .compact ? 88 : 104 }
}

/// گروه‌بندی فهرست
enum GroupBy: String, CaseIterable, Identifiable {
    case none, domain, month, folder
    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return L.tr("No Grouping")
        case .domain: return L.tr("By Domain")
        case .month: return L.tr("By Month")
        case .folder: return L.tr("By Folder")
        }
    }

    var icon: String {
        switch self {
        case .none: return "list.bullet"
        case .domain: return "globe"
        case .month: return "calendar"
        case .folder: return "folder"
        }
    }
}

/// رنگ تم برنامه
enum AccentPreset: String, CaseIterable, Identifiable {
    case system, blue, teal, green, indigo, purple, pink, orange, red, graphite,
         olive, brown, sky
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return L.tr("Default")
        case .blue: return L.tr("Blue")
        case .teal: return L.tr("Teal")
        case .green: return L.tr("Green")
        case .indigo: return L.tr("Indigo")
        case .purple: return L.tr("Purple")
        case .pink: return L.tr("Pink")
        case .orange: return L.tr("Orange")
        case .red: return L.tr("Red")
        case .graphite: return L.tr("Graphite")
        case .olive: return L.tr("Olive")
        case .brown: return L.tr("Brown")
        case .sky: return L.tr("Sky")
        }
    }

    /// رنگ سفارشی (برای system = nil تا رنگ سیستم حفظ شود)
    var color: Color? {
        switch self {
        case .system: return nil
        case .blue: return Color(hex: "#0A84FF")
        case .teal: return Color(hex: "#40C8E0")
        case .green: return Color(hex: "#30D158")
        case .indigo: return Color(hex: "#5E5CE6")
        case .purple: return Color(hex: "#BF5AF2")
        case .pink: return Color(hex: "#FF6482")
        case .orange: return Color(hex: "#FF9F0A")
        case .red: return Color(hex: "#FF453A")
        case .olive: return Color(hex: "#9BA83B")
        case .brown: return Color(hex: "#B07D3C")
        case .sky: return Color(hex: "#5AC8FA")
        case .graphite: return Color(hex: "#8E8E93")
        }
    }

    var swatch: Color { color ?? Color.accentColor }
}

/// میان‌بر سراسریِ افزودن سریع (بدون نیاز به مجوز سیستم)
enum HotKeyChoice: String, CaseIterable, Identifiable {
    case space, a, h, off
    var id: String { rawValue }

    var label: String {
        switch self {
        case .space: return "⌘⇧Space"
        case .a: return "⌘⇧A"
        case .h: return "⌘⇧H"
        case .off: return L.tr("Off")
        }
    }

    /// کد مجازیِ کلید (kVK_Space=49, kVK_ANSI_A=0, kVK_ANSI_H=4)
    var keyCode: UInt32? {
        switch self {
        case .space: return 49
        case .a: return 0
        case .h: return 4
        case .off: return nil
        }
    }

    /// cmdKey (256) | shiftKey (512)
    var modifiers: UInt32 { 256 | 512 }
}

// MARK: - پالت رنگ و آیکون پوشه

/// دسترسی سراسری به تنظیمات ظاهری (برای پنجره‌های فرعی)
enum AppTheme {
    /// تمپلیت انتخابی پنجرهٔ اصلی (پنجره‌های فرعی هم از آن پیروی می‌کنند)
    static var selected: UITheme {
        UITheme(rawValue: UserDefaults.standard.string(forKey: "appTheme") ?? "") ?? .classic
    }

    static var accent: Color? {
        selected.accentColor
            ?? AccentPreset(rawValue: UserDefaults.standard.string(forKey: "accentColor") ?? "")?.color
    }

    static var appearance: ColorScheme? {
        selected.scheme
            ?? AppearanceChoice(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "")?.scheme
    }
}

enum FolderPalette {
    /// (نام، کد رنگ HEX)
    static var colors: [(name: String, hex: String)] {
        [
            (L.tr("Yellow"), "#FFCC00"),
            (L.tr("Orange"), "#FF9500"),
            (L.tr("Red"), "#FF3B30"),
            (L.tr("Pink"), "#FF2D95"),
            (L.tr("Purple"), "#AF52DE"),
            (L.tr("Indigo"), "#5856D6"),
            (L.tr("Blue"), "#007AFF"),
            (L.tr("Teal"), "#32ADE6"),
            (L.tr("Green"), "#34C759"),
            (L.tr("Olive"), "#8E8E93"),
        ]
    }

    static let icons: [String] = [
        "folder", "folder.fill", "star", "star.fill",
        "heart", "heart.fill", "flame", "book",
        "briefcase", "cart", "hammer", "lightbulb",
        "graduationcap", "figure.run", "music.note", "photo",
    ]
}

// MARK: - رنگ HEX

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        let r, g, b: Double
        if s.count == 6 {
            r = Double((value >> 16) & 0xFF) / 255
            g = Double((value >> 8) & 0xFF) / 255
            b = Double(value & 0xFF) / 255
        } else {
            r = 1; g = 1; b = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }

    /// کد HEX شش‌رقمی (برای ذخیره در پایگاه داده)
    var hexString: String {
        guard let ns = NSColor(self).usingColorSpace(.sRGB) else { return "#007AFF" }
        let r = Int(round(ns.redComponent * 255))
        let g = Int(round(ns.greenComponent * 255))
        let b = Int(round(ns.blueComponent * 255))
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
