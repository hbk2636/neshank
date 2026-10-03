import SwiftUI

// MARK: - طراحی‌های رابط (چیدمان کاملِ برنامه)

/// «طراحی رابط» با «تم رنگی» (UITheme) فرق دارد:
/// تم فقط رنگ/گرادیان عوض می‌کند؛ طراحی، کل چیدمان را — ناوبری، ویجت‌ها،
/// تب‌ها، آیکون‌ها و نحوهٔ نمایش جزئیات. هر طراحی یک پوستهٔ مستقل است
/// که فقط داده و منطق را با بقیهٔ برنامه مشترک دارد.
enum UIDesign: String, CaseIterable, Identifiable {
    case classic, aurora, focus, dashboard, atlas, orbit

    var id: String { rawValue }

    var label: String {
        switch self {
        case .classic: return L.tr("Classic Layout")
        case .aurora: return L.tr("Aurora")
        case .focus: return L.tr("Focus")
        case .dashboard: return L.tr("Dashboard")
        case .atlas: return L.tr("Archive")
        case .orbit: return L.tr("Orbit")
        }
    }

    var tagline: String {
        switch self {
        case .classic: return L.tr("The familiar three-column Mac layout")
        case .aurora: return L.tr("Glass tab bar and large photo cards")
        case .focus: return L.tr("One quiet typographic column")
        case .dashboard: return L.tr("Widget home with an icon rail")
        case .atlas: return L.tr("Library catalog with margin index tabs")
        case .orbit: return L.tr("Big-tile launcher with pages")
        }
    }

    /// آیکون کوچک انتخابگر در تنظیمات
    var icon: String {
        switch self {
        case .classic: return "rectangle.3.group"
        case .aurora: return "sparkles.rectangle.stack"
        case .focus: return "text.justify"
        case .dashboard: return "square.grid.3x3.fill"
        case .atlas: return "books.vertical"
        case .orbit: return "circle.grid.2x2"
        }
    }

    /// نام فارسی ثابت برای لوح پیش‌نمایش (مستقل از زبان؛ هویت طراحی)
    var mark: String {
        switch self {
        case .classic: return "≡"
        case .aurora: return "✦"
        case .focus: return "¶"
        case .dashboard: return "▦"
        case .atlas: return "❧"
        case .orbit: return "◉"
        }
    }
}

// MARK: - محیط طراحی

private struct UIDesignKey: EnvironmentKey {
    static let defaultValue: UIDesign = .classic
}

extension EnvironmentValues {
    var uiDesign: UIDesign {
        get { self[UIDesignKey.self] }
        set { self[UIDesignKey.self] = newValue }
    }
}

// MARK: - ابزارهای مشترک پوسته‌ها

/// کمکی‌های مشترک طراحی‌های جدید: بدون هیچ ظاهر مشترکی بین پوسته‌ها —
/// فقط منطق سبک (عنوان محدوده، دستهٔ راست‌کلیک و …) تا در هر فایل تکرار نشود.
enum ShellSupport {
    /// مقدار پیش‌فرض پوشهٔ والد برای «نشانک جدید» بر اساس محدودهٔ فعال
    @MainActor static func currentFolderId(_ lib: Library) -> Int64? {
        if case .folder(let id) = lib.scope { return id }
        return nil
    }

    static func openURL(_ urlString: String) {
        if let url = URL(string: urlString) { NSWorkspace.shared.open(url) }
    }

    static func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

// MARK: - پیش‌نمایش می‌نیاتوری طراحی (برای انتخابگر تنظیمات)

/// شِمای کوچک از چیدمان هر طراحی — فقط هندسه، نه جزئیات واقعی
struct DesignPreview: View {
    let design: UIDesign
    var theme: UITheme = .classic

    @Environment(\.colorScheme) private var colorScheme

    private var accent: Color {
        theme.accentColor ?? Color(nsColor: .controlAccentColor)
    }

    private var paper: Color {
        theme.background != nil
            ? theme.accentColor?.opacity(0.06) ?? Color.primary.opacity(0.04)
            : Color.primary.opacity(colorScheme == .dark ? 0.07 : 0.05)
    }

    private var ink: Color { Color.primary.opacity(0.35) }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                paper
                switch design {
                case .classic: classicPreview(w, h)
                case .aurora: auroraPreview(w, h)
                case .focus: focusPreview(w, h)
                case .dashboard: dashboardPreview(w, h)
                case .atlas: atlasPreview(w, h)
                case .orbit: orbitPreview(w, h)
                }
            }
        }
    }

    private func bar(_ width: CGFloat, height: CGFloat = 3, color: Color? = nil) -> some View {
        RoundedRectangle(cornerRadius: height / 2)
            .fill(color ?? ink)
            .frame(width: width, height: height)
    }

    // سه ستون کلاسیک
    private func classicPreview(_ w: CGFloat, _ h: CGFloat) -> some View {
        HStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.10)).frame(width: w * 0.22)
            RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.05)).frame(maxWidth: .infinity)
            RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.10)).frame(width: w * 0.3)
        }
        .padding(6)
    }

    // تب‌بار بالا + گرید کارت
    private func auroraPreview(_ w: CGFloat, _ h: CGFloat) -> some View {
        VStack(spacing: 5) {
            HStack {
                Circle().fill(accent).frame(width: 6, height: 6)
                Spacer()
                bar(w * 0.35, height: 5, color: accent.opacity(0.5))
                Spacer()
                Circle().fill(accent).frame(width: 8, height: 8)
            }
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.10))
                        .frame(height: 26)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(6)
    }

    // تک‌ستون تایپوگرافیک
    private func focusPreview(_ w: CGFloat, _ h: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            bar(w * 0.3, height: 4)
            bar(w * 0.5, height: 2.5, color: ink.opacity(0.6))
            Spacer(minLength: 2)
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 4) {
                    Circle().fill(accent).frame(width: 3, height: 3)
                    bar(w * 0.45, height: 2.5)
                    Spacer()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // ریل آیکون + کارت‌های ویجت
    private func dashboardPreview(_ w: CGFloat, _ h: CGFloat) -> some View {
        HStack(spacing: 4) {
            VStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 2).fill(accent.opacity(0.6)).frame(width: 10, height: 10)
                RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.12)).frame(width: 10, height: 10)
                Spacer(minLength: 0)
            }
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.10)).frame(height: 14)
                    RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.10)).frame(height: 14)
                }
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.10)).frame(height: 14)
                    RoundedRectangle(cornerRadius: 3).fill(accent.opacity(0.25)).frame(height: 14)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(6)
    }

    // کارت‌های فهرستگان + زبانهٔ لبه
    private func atlasPreview(_ w: CGFloat, _ h: CGFloat) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 5) {
                bar(w * 0.25, height: 4, color: ink.opacity(0.8))
                Spacer(minLength: 2)
                ForEach(0..<3, id: \.self) { _ in
                    VStack(alignment: .leading, spacing: 2) {
                        bar(w * 0.4, height: 2.5)
                        bar(w * 0.25, height: 2, color: ink.opacity(0.4))
                    }
                    Divider().opacity(0.4)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 10)
            .padding(.vertical, 8)
            Spacer()
            VStack(spacing: 3) {
                Capsule().fill(accent).frame(width: 7, height: 14)
                Capsule().fill(Color.primary.opacity(0.12)).frame(width: 7, height: 14)
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .padding(.trailing, 3)
        }
    }

    // گرید تایل + نقاط صفحه
    private func orbitPreview(_ w: CGFloat, _ h: CGFloat) -> some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { i in
                    VStack(spacing: 2) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(i == 0 ? AnyShapeStyle(accent.opacity(0.35)) : AnyShapeStyle(Color.primary.opacity(0.10)))
                            .frame(width: 14, height: 14)
                        bar(10, height: 1.5)
                    }
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 2) {
                Circle().fill(accent).frame(width: 4, height: 4)
                Circle().fill(Color.primary.opacity(0.15)).frame(width: 4, height: 4)
            }
            .padding(.bottom, 3)
        }
    }
}
