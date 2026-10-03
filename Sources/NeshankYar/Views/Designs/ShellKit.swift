import SwiftUI
import AppKit

// MARK: - کیت مشترک پوسته‌ها
// امکاناتی که باید در «همهٔ» طراحی‌ها با کیفیت یکسان موجود باشند:
// منوی سرریز (ابزارها + مرتب‌سازی + ورود/خروجی + زباله‌دان) و
// منوی راست‌کلیک کامل نشانک — تا هیچ طراحی‌ای از چیدمان کلاسیک عقب نماند.

// MARK: لایهٔ کدر پشت پنل‌ها

extension View {
    /// پشت پنل‌های Material یک لایهٔ کاملاً مات می‌گذارد تا رنگ عناصر اشباعِ
    /// پشتِ پنل (مثل دکمهٔ آبی «نشانک جدید» در شفق) به‌هیچ‌وجه از پشت آن پس نزند.
    /// بعد از `background(.regularMaterial)` به کار برود.
    @ViewBuilder
    func opaquePanelBacking() -> some View {
        background(Color(nsColor: .windowBackgroundColor))
    }
}

// MARK: باز کردن ابزارها (مشترک همهٔ پوسته‌ها)

/// نقطهٔ ورود یکسان «نقشه ذهنی» و «دانلود ویدیو» در هر ۶ چیدمان —
/// نشانک انتخاب‌شده به‌صورت خودکار پر می‌شود.
@MainActor
enum ShellTools {
    static func selectedBookmark() -> Bookmark? {
        Library.shared.selectedId.flatMap { Library.shared.bookmark(id: $0) }
    }

    static func openMindMap() {
        MindMapToolWindow.shared.show(bookmark: selectedBookmark())
    }

    static func openVideoDownload() {
        VideoDownloadToolWindow.shared.show(bookmark: selectedBookmark())
    }
}

/// بخش «ابزارها» برای منوهای ⋯ همهٔ پوسته‌ها و چیدمان کلاسیک
struct ShellToolsSection: View {
    var body: some View {
        Section(L.tr("Tools")) {
            Button {
                ShellTools.openMindMap()
            } label: {
                Label(L.tr("Mind Map Designer"), systemImage: "brain.head.profile")
            }
            .help(L.tr("Separate window: design a mind map"))
            Button {
                ShellTools.openVideoDownload()
            } label: {
                Label(L.tr("Video Downloader"), systemImage: "arrow.down.circle")
            }
            .help(L.tr("Separate window: download a video"))
        }
    }
}

// MARK: منوی سرریز «بیشتر»

/// منوی ⋯ با همان امکانات منوی «More» چیدمان کلاسیک؛ هشدارها داخل خودش هستند
/// تا هر پوسته فقط آن را در نوار خودش بگذارد.
struct ShellMoreMenu: View {
    @ObservedObject private var lib = Library.shared
    @State private var showSaveFilter = false
    @State private var filterName = ""
    @State private var confirmEmptyTrash = false

    /// سبک دکمه: آیکون تنها یا با برچسب
    var labeled = false

    var body: some View {
        Menu {
            Button(L.tr("Save Current Filter…")) {
                filterName = lib.query.isBlank ? suggestedName : lib.query.trimmed
                showSaveFilter = true
            }

            Divider()

            if lib.scope == .trash {
                Button(L.tr("Restore All")) {
                    lib.restore(ids: lib.results.map(\.id))
                }
                .disabled(lib.results.isEmpty)

                Button(L.tr("Empty Trash"), role: .destructive) {
                    confirmEmptyTrash = true
                }
                .disabled(lib.counts.trash == 0)

                Divider()
            }

            Picker(L.tr("Sort"), selection: Binding(
                get: { lib.sort },
                set: { lib.sort = $0 }
            )) {
                ForEach(Library.Sort.allCases) { s in
                    Label(s.label, systemImage: sortIcon(s)).tag(s)
                }
            }

            Divider()

            ShellToolsSection()

            Divider()

            Button {
                Task { await lib.checkAllLinks() }
            } label: {
                if lib.isChecking {
                    Label(L.tr("Checking…"), systemImage: "bolt.horizontal.circle.fill")
                } else {
                    Label(L.tr("Check All Links"), systemImage: "bolt.horizontal.circle")
                }
            }
            .disabled(lib.isChecking)

            Button(L.tr("Import from Browser File…")) {
                FilePanels.pickImport { url in
                    Task { await lib.importHTML(from: url) }
                }
            }
            Button(L.tr("Export HTML…")) {
                FilePanels.pickExport { url in
                    lib.exportHTML(to: url)
                }
            }
        } label: {
            if labeled {
                Label(L.tr("More"), systemImage: "ellipsis.circle")
            } else {
                Image(systemName: "ellipsis.circle")
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L.tr("Grouping, sorting and tools"))
        .alert(L.tr("Save Current Filter"), isPresented: $showSaveFilter) {
            TextField(L.tr("Filter Name"), text: $filterName)
            Button(L.tr("Save")) {
                lib.saveCurrentFilter(name: filterName)
                filterName = ""
            }
            Button(L.tr("Cancel"), role: .cancel) { filterName = "" }
        } message: {
            Text(L.tr("The current search, scope and sort will be saved with this name."))
        }
        .confirmationDialog(L.tr("Empty Trash?"), isPresented: $confirmEmptyTrash) {
            Button(L.tr("Delete All Permanently"), role: .destructive) {
                lib.emptyTrash()
            }
        } message: {
            Text(L.tf("%@ bookmarks will be permanently deleted.", Digits.fa(lib.counts.trash)))
        }
    }

    private var suggestedName: String {
        switch lib.scope {
        case .folder(let id):
            return lib.flattenFolders(lib.folders).first { $0.id == id }?.name ?? L.tr("Folder")
        case .unfiled: return L.tr("Unfiled")
        case .tag(let name): return name
        case .starred: return L.tr("Starred")
        case .trash: return L.tr("Trash")
        case .mindMaps: return L.tr("Mind Maps")
        case .all: return L.tr("All Bookmarks")
        }
    }

    private func sortIcon(_ s: Library.Sort) -> String {
        switch s {
        case .newest: return "arrow.down.circle"
        case .oldest: return "arrow.up.circle"
        case .title: return "textformat"
        case .site: return "globe"
        }
    }
}

// MARK: منوی مرتب‌سازی مستقل

/// دکمهٔ مرتب‌سازی برای سربرگ پوسته‌ها
struct ShellSortMenu: View {
    @ObservedObject private var lib = Library.shared
    var showsTitle = false

    var body: some View {
        Menu {
            Picker(L.tr("Sort"), selection: Binding(
                get: { lib.sort },
                set: { lib.sort = $0 }
            )) {
                ForEach(Library.Sort.allCases) { s in
                    Label(s.label, systemImage: sortIcon(s)).tag(s)
                }
            }
        } label: {
            if showsTitle {
                Label(L.tr("Sort"), systemImage: "arrow.up.arrow.down")
            } else {
                Image(systemName: "arrow.up.arrow.down")
            }
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(L.tr("Sort"))
    }

    private func sortIcon(_ s: Library.Sort) -> String {
        switch s {
        case .newest: return "arrow.down.circle"
        case .oldest: return "arrow.up.circle"
        case .title: return "textformat"
        case .site: return "globe"
        }
    }
}

// MARK: منوی راست‌کلیک کامل نشانک

/// منوی زمینه با همان امکانات چیدمان کلاسیک + امکانات سریع (انتقال پوشه، برچسب، خوانده‌شده)
struct ShellBookmarkMenu: View {
    @ObservedObject private var lib = Library.shared
    let bookmark: Bookmark

    var body: some View {
        if bookmark.isTrashed {
            Button(L.tr("Restore from Trash")) {
                lib.restore(ids: [bookmark.id])
            }
            Button(L.tr("Copy URL")) {
                lib.copyURL(bookmark)
            }
            Divider()
            Button(L.tr("Delete Permanently"), role: .destructive) {
                lib.purge(ids: [bookmark.id])
            }
        } else {
            Button(L.tr("Open")) {
                lib.open(bookmark)
            }
            .keyboardShortcut(.return, modifiers: .command)

            Button(L.tr("Copy URL")) {
                lib.copyURL(bookmark)
            }

            Divider()

            Button(bookmark.starred ? L.tr("Remove Star") : L.tr("Star")) {
                lib.setStarred(bookmark.id, !bookmark.starred)
            }

            Button(bookmark.isRead ? L.tr("Mark as Unread") : L.tr("Mark as Read")) {
                lib.setRead(bookmark.id, !bookmark.isRead)
            }

            Divider()

            Button(L.tr("Edit Bookmark")) {
                lib.editing = .edit(bookmark)
            }

            Menu(L.tr("Move to Folder")) {
                ForEach(lib.folderOptions()) { option in
                    Button(option.label) {
                        lib.setFolder([bookmark.id], folderId: option.id == 0 ? nil : option.id)
                    }
                }
            }

            Menu(L.tr("Tag")) {
                if lib.tags.isEmpty {
                    Text(L.tr("No tags yet"))
                }
                ForEach(lib.tags) { tag in
                    Button("#" + tag.name) {
                        lib.addTagBulk([bookmark.id], name: tag.name)
                    }
                }
            }

            if bookmark.folderId != nil {
                Button(L.tr("Remove from Folder")) {
                    lib.setFolder([bookmark.id], folderId: nil)
                }
            }

            Divider()

            Button(L.tr("Delete (Move to Trash)"), role: .destructive) {
                lib.delete(ids: [bookmark.id])
            }
        }
    }
}

// MARK: نشانگر پیشرفت بررسی لینک‌ها

/// قرص کوچک پیشرفت «بررسی لینک‌ها» برای گذاشتن در نوار پوسته‌ها
struct ShellCheckBadge: View {
    @ObservedObject private var lib = Library.shared

    var body: some View {
        if lib.isChecking {
            HStack(spacing: 5) {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.6)
                    .frame(width: 12, height: 12)
                Text(Digits.fa(Int(lib.checkProgress * 100)) +
                     (AppLanguage.current == .persian ? "٪" : "%"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Capsule().fill(Color.primary.opacity(0.06)))
        }
    }
}

// MARK: منوی زمینهٔ نقشهٔ ذهنی

/// منوی راست‌کلیک کامل نقشهٔ ذهنی برای پوسته‌ها
struct ShellMindMapMenu: View {
    @ObservedObject private var lib = Library.shared
    let record: MindMapRecord

    var body: some View {
        Button(L.tr("Open Mind Map")) {
            lib.selectedMindMapId = record.id
        }
        Button(L.tr("Open Source Page")) {
            ShellSupport.openURL(record.sourceURL)
        }
        Button(L.tr("Copy URL")) {
            ShellSupport.copyToClipboard(record.sourceURL)
        }
        Divider()
        Button(L.tr("Delete Mind Map"), role: .destructive) {
            lib.deleteMindMaps(ids: [record.id])
        }
    }
}
