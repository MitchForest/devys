import SwiftUI
import UI
#if canImport(ImageIO)
import ImageIO
#endif

public struct AttachmentChipView: View {
    private let chip: TerminalComposerChip
    private let onRemove: () -> Void
    @State private var isPreviewPresented = false

    public init(chip: TerminalComposerChip, onRemove: @escaping () -> Void) {
        self.chip = chip
        self.onRemove = onRemove
    }

    public var body: some View {
        InputChip(
            leading: { AttachmentChipLeading(chip: chip) },
            title: chip.title,
            subtitle: chip.subtitle,
            accessibilityLabel: accessibilityLabel,
            onTap: { isPreviewPresented.toggle() },
            onRemove: onRemove
        )
        .help(chip.path ?? chip.title)
        .popover(isPresented: $isPreviewPresented) {
            AttachmentChipPreview(chip: chip)
                .frame(width: 340)
                .padding(Spacing.comfortable)
        }
    }

    private var accessibilityLabel: String {
        let prefix = "\(chip.kind.accessibilityNoun): \(chip.title)"
        if let subtitle = chip.subtitle, !subtitle.isEmpty {
            return "\(prefix), \(subtitle)"
        }
        return prefix
    }
}

private struct AttachmentChipLeading: View {
    let chip: TerminalComposerChip

    var body: some View {
        switch chip.kind {
        case .image, .screenshot:
            if let path = chip.path {
                ImageThumbnailLeading(url: URL(fileURLWithPath: path), fallbackSymbol: chip.kind.systemImage)
            } else {
                SymbolLeading(systemImage: chip.kind.systemImage)
            }
        default:
            SymbolLeading(systemImage: chip.kind.systemImage)
        }
    }
}

private struct SymbolLeading: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .font(Typography.caption.weight(.medium))
    }
}

private struct ImageThumbnailLeading: View {
    let url: URL
    let fallbackSymbol: String

    @State private var thumbnail: Image?

    var body: some View {
        ZStack {
            if let thumbnail {
                thumbnail
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: fallbackSymbol)
                    .font(Typography.caption.weight(.medium))
            }
        }
        .task(id: url) {
            thumbnail = await loadThumbnail(url: url)
        }
    }
}

private func loadThumbnail(url: URL, maxPixelSize: Int = 96) async -> Image? {
    #if canImport(ImageIO)
    return await Task.detached(priority: .userInitiated) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return Image(cgImage, scale: 1, label: Text(""))
    }.value
    #else
    return nil
    #endif
}

private extension TerminalComposerChipKind {
    var systemImage: String {
        switch self {
        case .file:
            "doc.text"
        case .folder:
            "folder"
        case .image:
            "photo"
        case .screenshot:
            "viewfinder"
        case .video:
            "film"
        case .paste:
            "doc.on.clipboard"
        case .selection:
            "text.quote"
        case .diff:
            "plus.forwardslash.minus"
        }
    }

    var accessibilityNoun: String {
        switch self {
        case .file:
            "File"
        case .folder:
            "Folder"
        case .image:
            "Image"
        case .screenshot:
            "Screenshot"
        case .video:
            "Video"
        case .paste:
            "Pasted text"
        case .selection:
            "Selection"
        case .diff:
            "Diff"
        }
    }
}

private struct AttachmentChipPreview: View {
    let chip: TerminalComposerChip

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(chip.title)
                .font(Typography.heading)
            if let path = chip.path {
                Text(path)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let text = chip.text {
                ScrollView {
                    Text(text)
                        .font(Typography.Code.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 220)
            } else {
                Text(previewLabel)
                    .font(Typography.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var previewLabel: String {
        switch chip.kind {
        case .image:
            "Image attachment"
        case .video:
            "Video attachment"
        case .screenshot:
            "Screenshot attachment"
        default:
            "Attachment"
        }
    }
}
