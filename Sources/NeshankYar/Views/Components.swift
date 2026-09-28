import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - کش تصاویر محلی

final class ImageStore: @unchecked Sendable {
    static let shared = ImageStore()
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 500
    }

    func image(path: String?) -> NSImage? {
        guard let path, !path.isEmpty else { return nil }
        if let hit = cache.object(forKey: path as NSString) { return hit }
        guard FileManager.default.fileExists(atPath: path),
              let img = NSImage(contentsOfFile: path) else { return nil }
        cache.setObject(img, forKey: path as NSString)
        return img
    }
}

// MARK: - فاوآیکون

struct FaviconView: View {
    let path: String?
    var size: CGFloat = 20

    private var corner: CGFloat { size > 26 ? 9 : 6 }

    var body: some View {
        Group {
            if let img = ImageStore.shared.image(path: path) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "globe")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.secondary)
                    .padding(size > 26 ? 7 : 5)
            }
        }
        .frame(width: size, height: size)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: corner))
        .overlay(
            RoundedRectangle(cornerRadius: corner)
                .strokeBorder(Color.primary.opacity(0.08))
        )
    }
}

// MARK: - تصویر بندانگشتی

struct ThumbnailView: View {
    let bookmark: Bookmark
    var height: CGFloat = 110

    /// اولویت: عکس واقعی صفحه ← تصویر معرفی ← فاوآیکون
    private var path: String? { bookmark.screenshot ?? bookmark.thumb }

    var body: some View {
        ZStack {
            if let img = ImageStore.shared.image(path: path) {
                // پایه با عرض پیشنهادیِ قطعی و تصویر به‌صورت overlay تا ابعاد کارت
                // هرگز از روی نسبت تصویر رشد نکند (وگرنه کارت از سلول گرید پهن‌تر
                // می‌شود و روی کارت همسایه می‌افتد — باگ هم‌پوشانی کارت‌ها)
                Color.clear
                    .frame(height: height)
                    .overlay {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
            } else {
                LinearGradient(
                    colors: [Color.accentColor.opacity(0.22), Color.accentColor.opacity(0.06)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .frame(height: height)
                FaviconView(path: bookmark.favicon, size: 34)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - چیپ برچسب

struct TagChip: View {
    let name: String
    var count: Int?
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 4) {
            Text(name)
            if let c = count { Text(Digits.fa(c)) }
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                }
                .buttonStyle(.borderless)
                .help(L.tr("Remove tag"))
            }
        }
        .font(.caption)
        .padding(.horizontal, onRemove == nil ? 9 : 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
        .foregroundStyle(Color.accentColor)
    }
}

// MARK: - پنل‌های انتخاب فایل

enum FilePanels {
    @MainActor
    static func pickImport(completion: @escaping @MainActor (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.html, .xml, .plainText]
        panel.message = L.tr("Choose a bookmark file exported from Safari, Chrome or Firefox")
        panel.prompt = L.tr("Import")
        if panel.runModal() == .OK, let url = panel.url {
            completion(url)
        }
    }

    @MainActor
    static func pickExport(completion: @escaping @MainActor (URL) -> Void) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.html]
        panel.nameFieldStringValue = "neshankyar-bookmarks.html"
        panel.message = L.tr("Save an HTML backup of all bookmarks")
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            completion(url)
        }
    }
}

// MARK: - رابط‌های کمکی SwiftUI

extension View {
    /// پس‌زمینهٔ نرم برای نوارها
    func softBar() -> some View {
        background(.bar)
    }
}
