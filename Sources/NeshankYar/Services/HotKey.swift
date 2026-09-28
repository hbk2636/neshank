import Foundation
import Carbon.HIToolbox

extension Notification.Name {
    /// فشردن میان‌بر سراسریِ «افزودن سریع»
    static let quickAddHotKey = Notification.Name("NeshankYar.quickAddHotKey")
}

// MARK: - میان‌بر سراسری (Carbon — بدون نیاز به مجوز دسترسی)

/// امضای گرم‌کلید: 'NYKH'
private let hotKeySignature: OSType = 0x4E59_4B48

private func hotKeyEventHandler(
    _ callRef: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return noErr }
    var hkID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hkID
    )
    guard status == noErr, hkID.signature == hotKeySignature else { return OSStatus(eventNotHandledErr) }

    // همهٔ کارها باید در رشتهٔ اصلی انجام شود
    DispatchQueue.main.async {
        NotificationCenter.default.post(name: .quickAddHotKey, object: nil)
    }
    return noErr
}

@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var current: HotKeyChoice = .off

    private init() {}

    /// انتخاب ذخیره‌شدهٔ کاربر
    static func savedChoice() -> HotKeyChoice {
        HotKeyChoice(rawValue: UserDefaults.standard.string(forKey: "hotkey") ?? "") ?? .space
    }

    func start() {
        apply(Self.savedChoice())
    }

    /// ثبت/لغو میان‌بر
    func apply(_ choice: HotKeyChoice) {
        unregister()
        current = choice
        guard let keyCode = choice.keyCode else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyEventHandler,
            1,
            &eventType,
            nil,
            &handlerRef
        )

        let id = EventHotKeyID(signature: hotKeySignature, id: 1)
        var ref: EventHotKeyRef?
        RegisterEventHotKey(keyCode, choice.modifiers, id, GetApplicationEventTarget(), 0, &ref)
        hotKeyRef = ref
    }

    private func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }
}
