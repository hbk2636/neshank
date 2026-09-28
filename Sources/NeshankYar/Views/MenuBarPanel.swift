import SwiftUI
import AppKit

struct MenuBarPanel: View {
    @ObservedObject private var lib = Library.shared
    @Environment(\.openWindow) private var openWindow

    @State private var query = ""
    @State private var status: String?

    private var results: [Bookmark] { lib.quickResults(query) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "bookmark.fill")
                    .foregroundStyle(Color.accentColor)
                Text(L.tr("Neshank"))
                    .font(.headline)
                Spacer()
                Button {
                    addFromClipboard()
                } label: {
                    Label(L.tr("Quick Add"), systemImage: "plus")
                }
                .controlSize(.small)

                Button {
                    openMain()
                } label: {
                    Image(systemName: "macwindow")
                }
                .controlSize(.small)
                .help(L.tr("Open Main Window"))
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(L.tr("Search or type a URL…"), text: $query)
                    .textFieldStyle(.plain)
                    .onSubmit {
                        if let first = results.first, URLNormalizer.url(first.url) != nil && !query.isBlank {
                            lib.open(first)
                        } else {
                            addFromClipboard()
                        }
                    }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )

            if let status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if results.isEmpty {
                        Text(query.isBlank ? L.tr("You have no bookmarks yet") : L.tr("No results found"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.top, 24)
                            .frame(maxWidth: .infinity)
                    } else if query.isBlank {
                        // نمایش دسته‌بندی‌شده بر اساس پوشه
                        ForEach(groupedResults, id: \.name) { group in
                            sectionHeader(group.name, count: group.items.count)
                            ForEach(group.items) { bookmark in
                                row(bookmark)
                            }
                        }
                    } else {
                        ForEach(results) { bookmark in
                            row(bookmark)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: .infinity)

            Divider()

            HStack {
                Button(L.tr("Quit")) {
                    NSApp.terminate(nil)
                }
                .controlSize(.small)
                Spacer()
                Text(L.tf("%@ bookmarks", Digits.fa(lib.counts.all)))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(width: 340, height: 440)
        .environment(\.layoutDirection, L.direction)
        .tint(AppTheme.accent)
        .preferredColorScheme(AppTheme.appearance)
    }

    private func row(_ b: Bookmark) -> some View {
        Button {
            lib.open(b)
        } label: {
            HStack(spacing: 8) {
                FaviconView(path: b.favicon, size: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(b.displayTitle)
                        .font(.system(size: 12, weight: b.isRead ? .regular : .semibold))
                        .lineLimit(1)
                    Text(b.domain)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if b.starred {
                    Image(systemName: "star.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.yellow)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: دسته‌بندی بر اساس پوشه

    private struct MenuGroup {
        let name: String
        let items: [Bookmark]
    }

    private var groupedResults: [MenuGroup] {
        let names = Dictionary(
            uniqueKeysWithValues: lib.flattenFolders(lib.folders).map { ($0.id, $0.name) }
        )
        var map: [String: [Bookmark]] = [:]
        for b in results {
            let key = b.folderId.flatMap { names[$0] } ?? L.tr("Unfiled")
            map[key, default: []].append(b)
        }
        return map.map { MenuGroup(name: $0.key, items: $0.value) }
            .sorted { lhs, rhs in
                (lhs.items.first?.createdAt ?? .distantPast) > (rhs.items.first?.createdAt ?? .distantPast)
            }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(Digits.fa(count))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
    }

    private func addFromClipboard() {
        guard let text = NSPasteboard.general.string(forType: .string)?.trimmed,
              URLNormalizer.url(text) != nil
        else {
            status = L.tr("No URL in the clipboard")
            return
        }
        status = L.tr("Adding…")
        Task {
            await lib.add(rawURL: text, title: "", note: "", folderId: nil, tags: [], fetchMeta: true)
            status = L.tr("Bookmark added")
            query = ""
        }
    }

    private func openMain() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "main")
    }
}
