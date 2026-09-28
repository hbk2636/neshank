import SwiftUI

struct EditorSheet: View {
    let target: EditorTarget

    @ObservedObject private var lib = Library.shared
    @Environment(\.dismiss) private var dismiss

    @State private var urlText = ""
    @State private var titleText = ""
    @State private var noteText = ""
    @State private var folderId: Int64 = 0
    @State private var tagsText = ""
    @State private var autoFetch = true
    @State private var saving = false
    @State private var appeared = false

    private var isEditing: Bool { target.bookmark != nil }

    private var normalizedURL: URL? { URLNormalizer.url(urlText) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: isEditing ? "pencil.circle.fill" : "plus.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text(isEditing ? L.tr("Edit Bookmark") : L.tr("New Bookmark"))
                    .font(.headline)
                Spacer()
            }

            Form {
                TextField(L.tr("URL"), text: $urlText, prompt: Text("https://example.com"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await save() } }

                TextField(L.tr("Title (empty = auto-fetch)"), text: $titleText)
                    .textFieldStyle(.roundedBorder)

                Picker(L.tr("Folder"), selection: $folderId) {
                    ForEach(lib.folderOptions()) { option in
                        Text(option.label).tag(option.id)
                    }
                }

                TextField(L.tr("Tags (comma-separated)"), text: $tagsText)
                    .textFieldStyle(.roundedBorder)

                TextField(L.tr("Note"), text: $noteText)
                    .textFieldStyle(.roundedBorder)

                if !isEditing {
                    Toggle(L.tr("Auto-fetch title, description and image"), isOn: $autoFetch)
                }
            }
            .formStyle(.columns)

            if let u = normalizedURL {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.green)
                    Text(URLNormalizer.domain(u))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(u.absoluteString)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                .font(.caption)
            } else if !urlText.isBlank {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle")
                        .foregroundStyle(.red)
                    Text(L.tr("Invalid URL"))
                        .foregroundStyle(.red)
                }
                .font(.caption)
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
                Button(L.tr("Cancel")) {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(isEditing ? L.tr("Save Changes") : L.tr("Add Bookmark")) {
                    Task { await save() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(normalizedURL == nil || saving)
            }
        }
        .padding(22)
        .frame(width: 540)
        .onAppear {
            guard !appeared else { return }
            appeared = true
            fill()
        }
    }

    private func fill() {
        if let b = target.bookmark {
            urlText = b.url
            titleText = b.title
            noteText = b.note
            folderId = b.folderId ?? 0
            tagsText = b.tags.joined(separator: "، ")
        } else if case .new(let preset) = target {
            folderId = preset ?? 0
            let paste = NSPasteboard.general.string(forType: .string) ?? ""
            if let u = URLNormalizer.url(paste.trimmed), u.absoluteString == paste.trimmed {
                urlText = paste.trimmed
            }
        }
    }

    private func save() async {
        guard let url = normalizedURL else { return }
        let tags = tagsText
            .replacingOccurrences(of: "،", with: ",")
            .split(whereSeparator: { $0 == "," || $0 == ";" || $0.isNewline })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        saving = true
        defer { saving = false }

        if let b = target.bookmark {
            lib.update(
                b,
                url: url.absoluteString,
                title: titleText,
                note: noteText,
                folderId: folderId == 0 ? nil : folderId,
                tags: tags
            )
            dismiss()
        } else {
            await lib.add(
                rawURL: url.absoluteString,
                title: titleText,
                note: noteText,
                folderId: folderId == 0 ? nil : folderId,
                tags: tags,
                fetchMeta: autoFetch
            )
            dismiss()
        }
    }
}
