import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct RootView: View {
    @ObservedObject private var lib = Library.shared
    @State private var selection = Set<Bookmark.ID>()
    @State private var dropTargeted = false
    @State private var page: AppPage?
    @State private var showPalette = false
    /// هشدار بحرانی: فایل دیتابیس واقعی باز نشده و تغییرات ذخیره نمی‌شوند
    @State private var showStorageAlert = false

    /// صفحه‌های تمام‌پنجره‌ای (پایدارتر از شیت؛ با Esc یا دکمهٔ بستن بسته می‌شوند)
    enum AppPage: String, Identifiable {
        case chats
        var id: String { rawValue }
    }

    // عرض ستون‌ها (بین اجراها حفظ می‌شود)
    @AppStorage("paneSidebarWidth") private var sidebarWidth: Double = 240
    @AppStorage("paneDetailWidth") private var detailWidth: Double = 520
    @AppStorage("appearance") private var appearanceRaw = AppearanceChoice.system.rawValue
    @AppStorage("accentColor") private var accentRaw = AccentPreset.system.rawValue
    @AppStorage("appTheme") private var themeRaw = UITheme.ocean.rawValue
    /// طراحی رابط (چیدمان) — جدا از تم رنگی
    @AppStorage("uiDesign") private var designRaw = UIDesign.classic.rawValue

    private var appearance: AppearanceChoice {
        AppearanceChoice(rawValue: appearanceRaw) ?? .system
    }

    private var theme: UITheme {
        UITheme(rawValue: themeRaw) ?? .classic
    }

    private var design: UIDesign {
        UIDesign(rawValue: designRaw) ?? .classic
    }

    /// پس‌زمینهٔ گرادیانی تم (classic = بدون پس‌زمینه) — جدا از body برای سرعت کامپایل
    @ViewBuilder
    private var themeBackground: some View {
        if let gradient = theme.background {
            gradient.ignoresSafeArea()
        }
    }

    private var accent: Color? {
        theme.accentColor ?? AccentPreset(rawValue: accentRaw)?.color
    }

    /// اعمال رنگ پایه و حالت روی پنجرهٔ واقعی (chrome و لیست‌های پشت محتوا)
    private struct WindowThemeApplier: NSViewRepresentable {
        let base: NSColor?
        let scheme: ColorScheme?

        func makeNSView(context: Context) -> NSView { NSView() }

        func updateNSView(_ nsView: NSView, context: Context) {
            nsView.window?.backgroundColor = base
            switch scheme {
            case .dark: nsView.window?.appearance = NSAppearance(named: .darkAqua)
            case .light: nsView.window?.appearance = NSAppearance(named: .aqua)
            case nil: nsView.window?.appearance = nil
            case .some: break
            }
        }
    }

    var body: some View {
        designRoot
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minWidth: 1000, minHeight: 640)
            .environment(\.appTheme, theme)
            .environment(\.uiDesign, design)
            // پس‌زمینهٔ گرادیانی تم؛ classic پس‌زمینه ندارد (Vibrancy سیستمی)
            .background(themeBackground)
            .background(WindowThemeApplier(base: theme.windowBaseNS, scheme: theme.scheme))
            .environment(\.layoutDirection, L.direction)
            .tint(accent)
            .preferredColorScheme(theme.scheme ?? appearance.scheme)
            // رها کردن لینک از مرورگر/هر برنامه‌ای روی پنجره
            .onDrop(of: [.url, .fileURL, .plainText], isTargeted: $dropTargeted, perform: handleDrop)
            .overlay {
                if dropTargeted {
                    dropOverlay
                }
            }
            .sheet(item: $lib.editing) { target in
                EditorSheet(target: target)
            }
            .overlay {
                if let page {
                    ZStack {
                        Color.black.opacity(0.14)
                            .ignoresSafeArea()
                            .onTapGesture { self.page = nil }

                        Group {
                            switch page {
                            case .chats:
                                ChatsView(onClose: { self.page = nil })
                            }
                        }
                        .padding(18)
                        .background(.regularMaterial)
                        .opaquePanelBacking()
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.35), radius: 30, y: 8)
                    }
                    .transition(.opacity)
                }
            }
            .overlay {
                if showPalette {
                    ZStack(alignment: .top) {
                        Color.black.opacity(0.16)
                            .ignoresSafeArea()
                            .onTapGesture { showPalette = false }
                        CommandPalette(isPresented: $showPalette)
                            .padding(.top, 86)
                    }
                    .transition(.opacity)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .showChats)) { _ in
                page = .chats
            }
            .onReceive(NotificationCenter.default.publisher(for: .showPalette)) { _ in
                showPalette.toggle()
            }
            .overlay(alignment: .bottom) { toast }
            .animation(.easeInOut(duration: 0.2), value: lib.notice)
            .onReceive(NotificationCenter.default.publisher(for: .newBookmark)) { _ in
                lib.editing = .new(folderId: currentFolderId)
            }
            .task {
                if UserDefaults.standard.bool(forKey: "checkOnLaunch") {
                    await lib.checkAllLinks()
                }
            }
            .onAppear {
                if lib.storageError != nil { showStorageAlert = true }
            }
            .onChange(of: lib.storageError) { err in
                if err != nil { showStorageAlert = true }
            }
            .alert(L.tr("Storage Problem"), isPresented: $showStorageAlert) {
                Button(L.tr("Quit")) { NSApp.terminate(nil) }
                Button(L.tr("Continue without saving")) {}
            } message: {
                Text(lib.storageError ?? "")
            }
    }

    /// ریشهٔ طراحی فعال: هر طراحی چیدمان کامل خودش را دارد؛
    /// امکانات سراسری (دراپ، پالت، توست و…) در body بالای این می‌آیند.
    @ViewBuilder
    private var designRoot: some View {
        switch design {
        case .classic: classicLayout
        case .aurora: AuroraShell()
        case .focus: FocusShell()
        case .dashboard: DashboardShell()
        case .atlas: AtlasShell()
        case .orbit: OrbitShell()
        }
    }

    /// چیدمان سه‌ستونهٔ کلاسیک (پیش‌فرض)
    private var classicLayout: some View {
        GeometryReader { geo in
            // عرضهای مجاز بر حسب فضای واقعی پنجره —
            // هدف: پیش‌نمایش/مرورگر تا جای ممکن بزرگ شود و فقط به کمینهٔ واقعی فهرست و سایدبار بندد.
            let total = geo.size.width
            let listMin: Double = 300        // کمینهٔ فهرست وسط
            let detailMin: Double = 330      // کمینهٔ پیش‌نمایش
            let gaps: Double = 12            // دو جداکننده (۶+۶)
            let sidebarMax = max(180, min(300, total - listMin - detailMin - gaps))
            let detailMax = max(detailMin, total - sidebarWidth - listMin - gaps)
            // مقدار ذخیره‌شده ممکن است برای پنجرهٔ کوچک‌تر زیاد باشد → فقط برای نمایش محدود می‌شود
            let shownSidebar = min(max(sidebarWidth, 180), sidebarMax)
            let shownDetail = min(max(detailWidth, detailMin), detailMax)

            HStack(alignment: .top, spacing: 0) {
                // راست: سایدبار
                SidebarView()
                    .modifier(ThemedScrollBackground())
                    .frame(width: shownSidebar)

                PaneDivider(
                    width: $sidebarWidth,
                    range: 180...sidebarMax,
                    multiplier: 1,
                    reset: 240
                )

                // میانی: فهرست نشانک‌ها — کل فضای باقی‌مانده را می‌گیرد
                ListView(selection: $selection)
                    .modifier(ThemedScrollBackground())
                    .frame(minWidth: listMin, maxWidth: .infinity, maxHeight: .infinity)

                // چپ: جزئیات/مرورگر — فقط وقتی نشانکی انتخاب شده (با کلیک باز،
                // با ✕ یا کلیک فضای خالی بسته می‌شود)
                if lib.selectedId != nil || (lib.scope == .mindMaps && lib.selectedMindMapId != nil) {
                    PaneDivider(
                        width: $detailWidth,
                        range: detailMin...detailMax,
                        multiplier: -1,
                        reset: 520
                    )

                    DetailView()
                        .modifier(ThemedScrollBackground())
                        .frame(width: shownDetail)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .animation(.easeInOut(duration: 0.18),
                       value: lib.selectedId == nil && lib.selectedMindMapId == nil)
        }
    }

    // MARK: رها کردن لینک (Drag & Drop)

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    DispatchQueue.main.async {
                        if let url { QuickAddPanel.shared.show(prefill: url.absoluteString) }
                    }
                }
                return true
            }
        }
        for provider in providers {
            for type in [UTType.url.identifier, UTType.fileURL.identifier, UTType.plainText.identifier] {
                guard provider.hasItemConformingToTypeIdentifier(type) else { continue }
                provider.loadItem(forTypeIdentifier: type, options: nil) { item, _ in
                    let text: String?
                    if let s = item as? String {
                        text = s
                    } else if let d = item as? Data {
                        text = String(data: d, encoding: .utf8)
                    } else if let u = item as? URL {
                        text = u.absoluteString
                    } else {
                        text = nil
                    }
                    DispatchQueue.main.async {
                        if let text { QuickAddPanel.shared.show(prefill: text) }
                    }
                }
                return true
            }
        }
        return false
    }

    private var dropOverlay: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).opacity(0.82)
            VStack(spacing: 10) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(Color.accentColor)
                Text(L.tr("Drop the link here"))
                    .font(.title3.weight(.medium))
                Text(L.tr("The Quick Add form will open with the address filled in"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 0.15), value: dropTargeted)
    }

    private var currentFolderId: Int64? {
        if case .folder(let id) = lib.scope { return id }
        return nil
    }

    @ViewBuilder
    private var toast: some View {
        if let text = lib.notice {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(text)
                    .font(.callout)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .shadow(radius: 8, y: 3)
            .padding(.bottom, 20)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .allowsHitTesting(false)
        }
    }
}

// MARK: - خط‌کش جداکنندهٔ ستون‌ها (قابل کشیدن)

struct PaneDivider: View {
    @Environment(\.layoutDirection) private var layoutDirection
    @Binding var width: Double
    let range: ClosedRange<Double>
    /// در چیدمان چپ‌به‌راست: +1 برای ستونِ سمت راست، -1 برای ستونِ سمت چپ
    let multiplier: Double
    let reset: Double

    @State private var base: Double?
    @State private var hovering = false

    var body: some View {
        // در چیدمان راست‌به‌چپ ستونها جابه‌جا می‌شوند؛ جهت کشیدن ماوس باید معکوس شود
        // (در غیر این صورت کشیدن به چپ، ستون را به راست می‌برد)
        let direction = L.rtl ? -multiplier : multiplier

        Rectangle()
            .fill(hovering ? Color.accentColor.opacity(0.75) : Color.primary.opacity(0.10))
            .frame(width: 6)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                if inside {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                // فضای مختصات سراسری: چون خودِ خط‌کش هنگام کشیدن جابه‌جا می‌شود،
                // اگر از .local استفاده شود نیمی از فاصلهٔ ماوس گم می‌شود و ستون از دست عقب می‌ماند
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        if base == nil { base = width }
                        let next = (base ?? width) + Double(value.translation.width) * direction
                        width = min(range.upperBound, max(range.lowerBound, next))
                    }
                    .onEnded { _ in
                        base = nil
                    }
            )
            .onTapGesture(count: 2) {
                width = reset
            }
            .help(L.tr("Drag to resize (double-click to reset to default size)"))
    }
}
