import SwiftUI
import AppKit

// MARK: - تمپلیت‌های ظاهری برنامه

/// (نام قدیمی AppTheme برای دسترسی سراسری در Settings.swift است)
/// هر تمپلیت فقط رنگ تاکیدی نیست: پس‌زمینهٔ گرادیانی پنجره، رنگ پایهٔ chrome و
/// حالت روشنایی اجباری را هم تعیین می‌کند. `classic` = رفتار سیستمیِ بدون دست‌کاری.
enum UITheme: String, CaseIterable, Identifiable {
    case classic, midnight, ocean, forest, sunset, sakura

    var id: String { rawValue }

    var label: String {
        switch self {
        case .classic: return L.tr("Classic")
        case .midnight: return L.tr("Midnight")
        case .ocean: return L.tr("Ocean")
        case .forest: return L.tr("Forest")
        case .sunset: return L.tr("Sunset")
        case .sakura: return L.tr("Sakura")
        }
    }

    /// nil = از انتخاب «حالت روشنایی» کاربر پیروی کن (فقط classic)
    var scheme: ColorScheme? {
        switch self {
        case .classic: return nil
        case .midnight: return .dark
        case .ocean, .forest, .sunset, .sakura: return .light
        }
    }

    /// پس‌زمینهٔ گرادیانی محتوا (بالا ← پایین)؛ classic = nil یعنی Vibrancy سیستمی
    var background: LinearGradient? {
        guard let top = gradientTop, let bottom = gradientBottom else { return nil }
        return LinearGradient(colors: [color(top), color(bottom)],
                              startPoint: .top, endPoint: .bottom)
    }

    /// رنگ پایهٔ پنجره (پشت chrome و لیست‌ها — NSWindow.backgroundColor)
    var windowBaseNS: NSColor? {
        guard let base = windowBaseRGB else { return nil }
        return NSColor(srgbRed: base.0 / 255, green: base.1 / 255, blue: base.2 / 255, alpha: 1)
    }

    var accentColor: Color? {
        guard let a = accentRGB else { return nil }
        return color(a)
    }

    // پالت‌ها — RGB بر پایهٔ ۲۵۵

    private var gradientTop: (Double, Double, Double)? {
        switch self {
        case .classic: return nil
        case .midnight: return (26, 27, 48)      // #1A1B30
        case .ocean: return (242, 248, 253)      // #F2F8FD
        case .forest: return (241, 247, 238)     // #F1F7EE
        case .sunset: return (254, 243, 234)     // #FEF3EA
        case .sakura: return (253, 242, 245)     // #FDF2F5
        }
    }

    private var gradientBottom: (Double, Double, Double)? {
        switch self {
        case .classic: return nil
        case .midnight: return (15, 16, 32)      // #0F1020
        case .ocean: return (218, 235, 249)      // #DAEBF9
        case .forest: return (220, 236, 213)     // #DCECD5
        case .sunset: return (250, 224, 208)     // #FAE0D0
        case .sakura: return (246, 223, 232)     // #F6DFE8
        }
    }

    private var windowBaseRGB: (Double, Double, Double)? {
        switch self {
        case .classic: return nil
        case .midnight: return (21, 22, 40)      // #151628
        case .ocean: return (232, 241, 250)      // #E8F1FA
        case .forest: return (233, 242, 229)     // #E9F2E5
        case .sunset: return (252, 237, 226)     // #FCEDE2
        case .sakura: return (250, 236, 240)     // #FAECF0
        }
    }

    private var accentRGB: (Double, Double, Double)? {
        switch self {
        case .classic: return nil
        case .midnight: return (140, 140, 240)   // #8C8CF0 — نیلی روشن
        case .ocean: return (30, 120, 200)       // #1E78C8 — آبی اقیانوسی
        case .forest: return (51, 128, 76)       // #33804C — سبز جنگلی
        case .sunset: return (217, 95, 53)       // #D95F35 — نارنجی گرم
        case .sakura: return (194, 77, 119)      // #C24D77 — صورتی شکوفه
        }
    }

    private func color(_ rgb: (Double, Double, Double)) -> Color {
        Color(red: rgb.0 / 255, green: rgb.1 / 255, blue: rgb.2 / 255)
    }
}
