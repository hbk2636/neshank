import SwiftUI
import AppKit

// MARK: - وضعیت پنل «افزودن سریع»

@MainActor
final class QuickAddState: ObservableObject {
    static let shared = QuickAddState()

    @Published var urlText = ""
    @Published var folderId: Int64 = 0
    @Published var status: String?
    /// با هر بار باز شدن زیاد می‌شود تا فوکوس دوباره تنظیم شود
    @Published var token = 0

    private init() {}

    func show(prefill: String = "") {
        let p = prefill.trimmed
        if !p.isEmpty { urlText = p }
        status = nil
        token &+= 1
    }
}

// MARK: - پنل شناور افزودن سریع

@MainActor
final class QuickAddPanel {
    static let shared = QuickAddPanel()
    private var panel: NSPanel?
    private init() {}

    /// نمایش پنل (با متن پیش‌فرض در صورت وجود)
    func show(prefill: String = "") {
        QuickAddState.shared.show(prefill: prefill)
        let p = panel ?? make()
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    var isVisible: Bool { panel?.isVisible ?? false }

    private func make() -> NSPanel {
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 210),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.title = L.tr("Quick Add")
        p.titleVisibility = .hidden
        p.titlebarAppearsTransparent = true
        p.isMovableByWindowBackground = true
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.contentViewController = NSHostingController(rootView: QuickAddView())
        p.center()
        panel = p
        return p
    }
}

// MARK: - نمای پنل

struct QuickAddView: View {
    @ObservedObject private var state = QuickAddState.shared
    @ObservedObject private var lib = Library.shared
    @FocusState private var focused: Bool
    @State private var saving = false

    private var normalized: URL? { URLNormalizer.url(state.urlText) }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 8) {
                Image(systemName: "bolt.fill")
                    .foregroundStyle(Color.accentColor)
                Text(L.tr("Quick Add"))
                    .font(.headline)
                Spacer()
                Text(L.tr("From anywhere, ⌘⇧Space"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                Image(systemName: "link")
                    .foregroundStyle(.secondary)
                TextField(L.tr("Paste a URL…"), text: $state.urlText, prompt: Text("https://example.com"))
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { save() }
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(normalized == nil && !state.urlText.isBlank
                                  ? Color.red.opacity(0.6)
                                  : Color.primary.opacity(0.10))
            )

            HStack(spacing: 8) {
                Picker(L.tr("Folder"), selection: $state.folderId) {
                    ForEach(lib.folderOptions()) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 200)

                Toggle(L.tr("Auto-fetch info"), isOn: Binding(
                    get: { UserDefaults.standard.object(forKey: "autoFetch") as? Bool ?? true },
                    set: { UserDefaults.standard.set($0, forKey: "autoFetch") }
                ))
                .toggleStyle(.checkbox)
                .font(.caption)

                Spacer()

                if let status = state.status {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
            }

            HStack(spacing: 10) {
                if saving {
                    ProgressView()
                        .controlSize(.small)
                    Text(L.tr("Fetching page info…"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(L.tr("Close")) {
                    QuickAddPanel.shared.hide()
                }
                .keyboardShortcut(.cancelAction)

                Button(L.tr("Add Bookmark")) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(normalized == nil || saving)
                .controlSize(.large)
            }
        }
        .padding(20)
        .frame(width: 480)
        .tint(AppTheme.accent)
        .onAppear { focused = true }
        .onChange(of: state.token) { _ in
            focused = true
        }
        .animation(.easeInOut(duration: 0.18), value: state.status)
    }

    private func save() {
        guard normalized != nil, !saving else { return }
        let text = state.urlText
        saving = true
        Task {
            await lib.add(
                rawURL: text,
                title: "",
                note: "",
                folderId: state.folderId == 0 ? nil : state.folderId,
                tags: [],
                fetchMeta: UserDefaults.standard.object(forKey: "autoFetch") as? Bool ?? true
            )
            saving = false
            state.urlText = ""
            state.status = L.tr("Bookmark saved ✓")
            focused = true
        }
    }
}
