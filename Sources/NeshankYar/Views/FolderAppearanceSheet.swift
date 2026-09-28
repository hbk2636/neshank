import SwiftUI

// MARK: - ظاهر سفارشی پوشه (رنگ + آیکون)

struct FolderAppearanceSheet: View {
    let folder: Folder

    @ObservedObject private var lib = Library.shared
    @Environment(\.dismiss) private var dismiss

    @State private var color: String?
    @State private var icon: String?

    private let iconColumns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 8)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: icon ?? folder.uiIcon)
                    .foregroundStyle((color ?? folder.color).map(Color.init(hex:)) ?? .yellow)
                    .font(.title3)
                Text(L.tf("Appearance of Folder “%@”", folder.name))
                    .font(.headline)
                Spacer()
            }

            VStack(alignment: .trailing, spacing: 8) {
                Text(L.tr("Color"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 9) {
                    swatch(name: L.tr("Default"), hex: nil, preview: .yellow)

                    ForEach(FolderPalette.colors, id: \.hex) { item in
                        swatch(name: item.name, hex: item.hex, preview: Color(hex: item.hex))
                    }
                }
            }

            VStack(alignment: .trailing, spacing: 8) {
                Text(L.tr("Icon"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: iconColumns, spacing: 8) {
                    ForEach(FolderPalette.icons, id: \.self) { name in
                        Button {
                            icon = (icon == name) ? nil : name
                        } label: {
                            Image(systemName: name)
                                .font(.system(size: 16))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(icon == name
                                              ? Color.accentColor.opacity(0.18)
                                              : Color(nsColor: .controlBackgroundColor))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7)
                                        .strokeBorder(icon == name
                                                      ? Color.accentColor
                                                      : Color.primary.opacity(0.10))
                                )
                        }
                        .buttonStyle(.plain)
                        .help(name)
                    }
                }
            }

            HStack {
                Button(L.tr("Default")) {
                    color = nil
                    icon = nil
                }
                Spacer()
                Button(L.tr("Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L.tr("Save")) {
                    lib.setFolderColor(id: folder.id, hex: color)
                    lib.setFolderIcon(id: folder.id, icon: icon)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(22)
        .frame(width: 430)
        .onAppear {
            color = folder.color
            icon = folder.icon
        }
    }

    private func swatch(name: String, hex: String?, preview: Color) -> some View {
        Button {
            color = hex
        } label: {
            Circle()
                .fill(preview)
                .frame(width: 26, height: 26)
                .overlay(
                    Circle().strokeBorder(Color.primary.opacity(0.15))
                )
                .overlay(
                    Group {
                        if color == hex {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(hex == nil ? Color.primary : Color.white)
                        }
                    }
                )
        }
        .buttonStyle(.plain)
        .help(name)
    }
}
