import AppKit

// MARK: - اکشن‌های سراسری برنامه

@MainActor
enum AppActions {
    /// باز کردن پنجرهٔ تنظیمات.
    ///
    /// نکتهٔ فنی (تأییدشده با لاگ): آیتم Settings… منوی برنامه اکشن
    /// `showSettingsWindow:` ندارد؛ SwiftUI آن را با `menuAction:` روی یک
    /// `MenuItemCallback` داخلی سیم‌کشی می‌کند. به همین دلیل هیچ شکل مستقیمِ
    /// `sendAction` کار نمی‌کند و باید همان آیتم منو اجرا شود.
    /// شناسایی مستقل از زبان: اول کلید میان‌بر ⌘, بعد عنوان.
    static func openSettings() {
        if let topItems = NSApp.mainMenu?.items {
            for top in topItems {
                guard let menu = top.submenu, let items = top.submenu?.items else { continue }
                if let i = items.firstIndex(where: {
                    $0.keyEquivalent == ","
                        && $0.keyEquivalentModifierMask.contains(.command)
                        && $0.action != nil
                }) {
                    menu.performActionForItem(at: i)
                    return
                }
                if let i = items.firstIndex(where: {
                    $0.title.localizedCaseInsensitiveContains("setting")
                        || $0.title.localizedCaseInsensitiveContains("настройк")
                        || $0.title.contains("设置")
                        || $0.title.contains("تنظیمات")
                }) {
                    menu.performActionForItem(at: i)
                    return
                }
            }
        }
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
