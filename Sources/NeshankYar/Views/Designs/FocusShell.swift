import SwiftUI
import AppKit

// MARK: - طراحی «تمرکز» (Focus)
// تک‌ستون ساکت و تایپوگرافیک در وسط پنجره؛ بدون سایدبار و کروم اضافه.
// ناوبری پیوندهای متنی است، ردیف‌ها ساده و بزرگ‌حرف‌اند و
// جزئیات به‌صورت بازشوندهٔ درون‌خطی (آکاردئون) زیر همان ردیف باز می‌شود.

struct FocusShell: View {
    @ObservedObject private var lib = Library.shared
    @FocusState private var searchFocused: Bool
    @State private var hovered: Int64?

    private let columnWidth: CGFloat = 680

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    header
                    navLinks
                    searchField
                    Divider().opacity(0.5)
                    rows
                }
                .frame(width: min(columnWidth, geo.size.width - 48))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
            }
        }
    }

    // MARK: سربرگ

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L.tr("Focus"))
                    .font(.system(size: 27, weight: .medium, design: .serif))
                    .foregroundStyle(.primary.opacity(0.9))
                Text(headerCaption)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            HStack(spacing: 18) {
                Button {
                    NotificationCenter.default.post(name: .showChats, object: nil)
                } label: {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L.tr("Chats (⌘⇧C)"))

                Button {
                    ShellTools.openVideoDownload()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 13, weight: .light))
                        Text(L.tr("Video Downloader"))
                            .font(.system(size: 12.5))
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .help(L.tr("Video Downloader"))

                ShellSortMenu()
                    .fixedSize()
                    .frame(maxHeight: 18)

                ShellMoreMenu()
                    .fixedSize()
                    .frame(maxHeight: 18)

                Button {
                    AppActions.openSettings()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .light))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L.tr("Settings (⌘,)"))

                Button {
                    newAction()
                } label: {
                    HStack(spacing: 5) {
                        Text("+")
                            .font(.system(size: 15, weight: .light))
                        Text(lib.scope == .mindMaps ? L.tr("New Map") : L.tr("New Bookmark"))
                            .font(.system(size: 12.5))
                    }
                    .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 16)
    }

    private var headerCaption: String {
        if lib.scope == .mindMaps {
            return L.tf("%@ mind maps", Digits.fa(lib.mindMaps.count))
        }
        return L.tf("%@ bookmarks", Digits.fa(lib.results.count))
    }

    // MARK: ناوبری متنی

    private var navLinks: some View {
        HStack(spacing: 0) {
            navLink(.all, title: L.tr("All"))
            navDot
            navLink(.starred, title: L.tr("Starred"))
            navDot
            navLink(.unfiled, title: L.tr("Unfiled"))
            navDot
            navLink(.mindMaps, title: L.tr("Mind Maps"))
            navDot
            navLink(.trash, title: L.tr("Trash"))

            Spacer(minLength: 12)

            if !lib.folders.isEmpty || !lib.savedFilters.isEmpty {
                Menu {
                    Section(L.tr("Folders")) {
                        ForEach(lib.folderOptions()) { option in
                            Button(option.label) {
                                lib.scope = option.id == 0 ? .unfiled : .folder(option.id)
                                lib.selectedId = nil
                            }
                        }
                    }
                    if !lib.savedFilters.isEmpty {
                        Section(L.tr("Saved Filters")) {
                            ForEach(lib.savedFilters) { filter in
                                Button(filter.name) {
                                    lib.apply(filter)
                                    lib.selectedId = nil
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "folder")
                            .font(.system(size: 10, weight: .light))
                        Text(folderName)
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .frame(maxHeight: 20)
            }
        }
        .padding(.bottom, 18)
    }

    private var navDot: some View {
        Text("·")
            .font(.system(size: 13))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 7)
    }

    private func navLink(_ scope: Library.Scope, title: String) -> some View {
        let active = lib.scope == scope
        return Button {
            lib.scope = scope
            lib.selectedId = nil
            lib.selectedMindMapId = nil
        } label: {
            VStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 12.5, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? .primary : .secondary)
                Rectangle()
                    .fill(active ? Color.accentColor : .clear)
                    .frame(height: 1.5)
                    .frame(width: 34)
            }
        }
        .buttonStyle(.plain)
    }

    /// نام پوشهٔ فعال برای منوی پوشه‌ها
    private var folderName: String {
        if case .folder(let id) = lib.scope {
            return lib.flattenFolders(lib.folders).first { $0.id == id }?.name ?? L.tr("Folders")
        }
        if case .tag(let name) = lib.scope { return "#" + name }
        return L.tr("Folders")
    }

    // MARK: جستجو

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .light))
                .foregroundStyle(.tertiary)
            TextField(lib.scope == .mindMaps
                      ? L.tr("Search mind maps by name, URL or text…")
                      : L.tr("Search in title, URL, tag and note…"),
                      text: $lib.query)
                .textFieldStyle(.plain)
                .font(.system(size: 15, weight: .light))
                .focused($searchFocused)
            if !lib.query.isEmpty {
                Button { lib.query = "" } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 12)
    }

    // MARK: ردیف‌ها + بازشوندهٔ درون‌خطی

    @ViewBuilder
    private var rows: some View {
        if lib.scope == .mindMaps {
            if lib.mindMaps.isEmpty { emptyState } else {
                ForEach(lib.mindMaps) { map in
                    FocusMapRow(record: map, expanded: lib.selectedMindMapId == map.id) {
                        toggleMap(map.id)
                    }
                    rowDivider(map.id)
                }
            }
        } else if lib.results.isEmpty {
            emptyState
        } else {
            ForEach(lib.results) { bookmark in
                FocusRow(bookmark: bookmark,
                         expanded: lib.selectedId == bookmark.id,
                         hovered: hovered == bookmark.id,
                         isTrash: lib.scope == .trash,
                         onOpen: { lib.open(bookmark) },
                         onStar: { lib.setStarred(bookmark.id, !bookmark.starred) },
                         onEdit: { lib.editing = .edit(bookmark) },
                         onRestore: {
                             lib.restore(ids: [bookmark.id])
                             if lib.selectedId == bookmark.id { lib.selectedId = nil }
                         },
                         onDelete: { deleteAction(bookmark) })
                    .onTapGesture { toggle(bookmark.id) }
                    .onTapGesture(count: 2) { lib.open(bookmark) }
                    .onHover { inside in hovered = inside ? bookmark.id : nil }
                    .contextMenu { ShellBookmarkMenu(bookmark: bookmark) }

                // جزئیات درون‌خطی: دقیقاً زیر ردیف باز می‌شود
                if lib.selectedId == bookmark.id {
                    FocusInlineDetail(onClose: { lib.selectedId = nil })
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                rowDivider(bookmark.id)
            }
        }
    }

    @ViewBuilder
    private func rowDivider(_ id: Int64) -> some View {
        Rectangle()
            .fill(Color.primary.opacity(0.09))
            .frame(height: 0.7)
    }

    private func toggle(_ id: Int64) {
        lib.selectedId = lib.selectedId == id ? nil : id
        lib.selectedMindMapId = nil
    }

    private func toggleMap(_ id: Int64) {
        lib.selectedMindMapId = lib.selectedMindMapId == id ? nil : id
        lib.selectedId = nil
    }

    private func deleteAction(_ b: Bookmark) {
        if lib.scope == .trash { lib.purge(ids: [b.id]) } else { lib.delete(ids: [b.id]) }
        if lib.selectedId == b.id { lib.selectedId = nil }
    }

    @ViewBuilder
    private func rowMenu(_ b: Bookmark) -> some View {
        ShellBookmarkMenu(bookmark: b)
    }

    // MARK: حالت خالی

    private var emptyState: some View {
        VStack(spacing: 10) {
            Text(lib.query.isBlank ? "¶" : "∅")
                .font(.system(size: 34, weight: .ultraLight))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)
            Text(lib.query.isBlank ? L.tr("No bookmarks here") : L.tr("No results found"))
                .font(.system(size: 15, weight: .medium, design: .serif))
                .foregroundStyle(.secondary)
            Text(lib.query.isBlank ? L.tr("Press ⌘N to add your first bookmark.") : L.tr("Try different words or type a domain."))
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
            if lib.query.isBlank && lib.scope != .mindMaps {
                Button {
                    newAction()
                } label: {
                    Text("+ " + L.tr("New Bookmark"))
                        .font(.system(size: 12.5))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 70)
    }

    private func newAction() {
        if lib.scope == .mindMaps {
            MindMapToolWindow.shared.show(url: "")
        } else {
            lib.editing = .new(folderId: ShellSupport.currentFolderId(lib))
        }
    }
}

// MARK: - ردیف متنی تمرکز

private struct FocusRow: View {
    let bookmark: Bookmark
    let expanded: Bool
    let hovered: Bool
    let isTrash: Bool
    var onOpen: () -> Void
    var onStar: () -> Void
    var onEdit: () -> Void
    var onRestore: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                // ستارهٔ متنی قبل از عنوان
                Text(bookmark.starred ? "★" : "  ")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentColor)

                Text(bookmark.title.isBlank ? bookmark.domain : bookmark.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(expanded ? Color.primary : Color.primary.opacity(0.88))
                    .lineLimit(2)

                Spacer(minLength: 8)

                // اقدامات فقط با هاور ظاهر می‌شوند
                HStack(spacing: 14) {
                    if isTrash {
                        hoverIcon("arrow.uturn.backward", help: L.tr("Restore from Trash")) { onRestore() }
                    } else {
                        hoverIcon("arrow.up.right", help: L.tr("Open")) { onOpen() }
                        hoverIcon(bookmark.starred ? "star.fill" : "star", help: nil) { onStar() }
                        hoverIcon("square.and.pencil", help: L.tr("Edit Bookmark")) { onEdit() }
                        hoverIcon("trash", help: L.tr("Delete (Move to Trash)")) { onDelete() }
                    }
                }
                .opacity(hovered ? 1 : 0)
            }

            HStack(spacing: 8) {
                if !bookmark.isRead {
                    Circle().fill(Color.accentColor).frame(width: 4, height: 4)
                }
                Text(bookmark.domain)
                    .lineLimit(1)
                Text("·")
                Text(Dates.relative(bookmark.createdAt))
                if bookmark.isDead {
                    Text("·")
                    Text(L.tr("Dead link"))
                        .foregroundStyle(.red.opacity(0.8))
                }
                Spacer(minLength: 0)
                if !bookmark.tags.isEmpty {
                    Text(bookmark.tags.prefix(3).map { "#" + $0 }.joined(separator: " "))
                        .lineLimit(1)
                        .foregroundStyle(Color.accentColor.opacity(0.75))
                }
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .animation(.easeInOut(duration: 0.15), value: hovered)
    }

    private func hoverIcon(_ name: String, help: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 11.5, weight: .light))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help(help ?? "")
    }
}

// MARK: - ردیف نقشهٔ ذهنی

private struct FocusMapRow: View {
    let record: MindMapRecord
    let expanded: Bool
    var onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("◍")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentColor)
                Text(record.displayTitle)
                    .font(.system(size: 15, weight: .medium))
                    .lineLimit(2)
                Spacer(minLength: 8)
                Image(systemName: expanded ? "chevron.down" : "chevron.down")
                    .font(.system(size: 10, weight: .light))
                    .rotationEffect(.degrees(expanded ? 0 : -90))
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 8) {
                Text(record.sourceURL).lineLimit(1)
                Text("·")
                Text(Dates.relative(record.createdAt))
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .onTapGesture { onToggle() }
        .contextMenu { ShellMindMapMenu(record: record) }
    }
}

// MARK: - جزئیات درون‌خطی

/// ظرف آرام جزئیات درون‌خطی — محتوای سنگین همان DetailView است،
/// قاب‌بندی و حاشیه‌ها مال تمرکز: خط بالایی، پس‌زمینهٔ محو و عرض ستون.
private struct FocusInlineDetail: View {
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .light))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(L.tr("Close"))
            }
            .padding(.bottom, 6)

            DetailView()
                .frame(minHeight: 360, maxHeight: 520)
        }
        .padding(16)
        .background(Color.primary.opacity(0.035))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.accentColor.opacity(0.5)).frame(height: 1)
        }
        .padding(.vertical, 4)
    }
}
