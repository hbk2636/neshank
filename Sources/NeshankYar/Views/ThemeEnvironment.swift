import SwiftUI

// MARK: - گذرگاه تم بین ویوها

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue: UITheme = .classic
}

extension EnvironmentValues {
    /// تم فعال پنجرهٔ اصلی — لیست‌ها با آن پس‌زمینهٔ خود را شفاف می‌کنند
    var appTheme: UITheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

/// پس‌زمینهٔ لیست را در تم‌های غیر کلاسیک شفاف می‌کند تا گرادیان دیده شود
struct ThemedScrollBackground: ViewModifier {
    @Environment(\.appTheme) private var theme

    func body(content: Content) -> some View {
        content.scrollContentBackground(theme == .classic ? .automatic : .hidden)
    }
}
