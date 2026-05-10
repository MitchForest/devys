import Foundation
#if canImport(ImageIO)
import ImageIO
#endif

public enum TerminalComposerChipKind: String, Codable, CaseIterable, Sendable {
    case file
    case folder
    case image
    case video
    case screenshot
    case paste
    case selection
    case diff
}

public struct TerminalComposerSmartPasteSettings: Codable, Equatable, Sendable {
    public var inlineLineThreshold: Int

    public init(inlineLineThreshold: Int = 4) {
        self.inlineLineThreshold = max(0, inlineLineThreshold)
    }
}

public enum TerminalComposerDictationKey: String, Codable, CaseIterable, Equatable, Sendable {
    case function
    case control
    case option
}

public enum TerminalComposerPasteResult: Equatable, Sendable {
    case ignored
    case insertedInline(String)
    case attached(TerminalComposerChip)
}

public extension TerminalComposerChip {
    static func fileSystemItem(url: URL) -> TerminalComposerChip {
        let kind = inferredFileKind(for: url)
        let title = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        return TerminalComposerChip(
            kind: kind,
            title: title,
            subtitle: subtitle(for: kind, url: url),
            path: url.path
        )
    }

    static func paste(text: String) -> TerminalComposerChip {
        let lineCount = lineCount(in: text)
        return TerminalComposerChip(
            kind: .paste,
            title: "Paste · \(lineCount) lines",
            subtitle: preview(text),
            text: text,
            lineCount: lineCount
        )
    }

    static func selection(text: String) -> TerminalComposerChip {
        let lineCount = lineCount(in: text)
        return TerminalComposerChip(
            kind: .selection,
            title: "Selection · \(lineCount) lines",
            subtitle: preview(text),
            text: text,
            lineCount: lineCount
        )
    }

    static func screenshot() -> TerminalComposerChip {
        TerminalComposerChip(kind: .screenshot, title: "Screenshot")
    }

    static func diff(text: String) -> TerminalComposerChip {
        let lineCount = lineCount(in: text)
        return TerminalComposerChip(
            kind: .diff,
            title: "Diff · \(lineCount) lines",
            subtitle: preview(text),
            text: text,
            lineCount: lineCount
        )
    }

    static func lineCount(in text: String) -> Int {
        guard !text.isEmpty else { return 0 }
        return text.split(separator: "\n", omittingEmptySubsequences: false).count
    }

    private static func inferredFileKind(for url: URL) -> TerminalComposerChipKind {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return .folder
        }
        let ext = url.pathExtension.lowercased()
        if ["png", "jpg", "jpeg", "gif", "heic", "tiff", "webp", "bmp"].contains(ext) {
            return .image
        }
        if ["mov", "mp4", "m4v", "avi", "webm", "mkv"].contains(ext) {
            return .video
        }
        return .file
    }

    private static func subtitle(for kind: TerminalComposerChipKind, url: URL) -> String? {
        switch kind {
        case .folder:
            return folderItemCount(at: url)
        case .image:
            return imageMetadata(at: url) ?? fileSizeString(at: url)
        case .file, .video:
            return fileSizeString(at: url) ?? url.pathExtension.uppercased().nilIfEmpty
        case .screenshot, .paste, .selection, .diff:
            return nil
        }
    }

    private static func fileSizeString(at url: URL) -> String? {
        guard
            let values = try? url.resourceValues(forKeys: [.fileSizeKey]),
            let size = values.fileSize
        else { return nil }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        return formatter.string(fromByteCount: Int64(size))
    }

    private static func folderItemCount(at url: URL) -> String? {
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else { return nil }

        var count = 0
        while enumerator.nextObject() != nil {
            count += 1
            if count > 1000 { return "many items" }
        }
        return count == 1 ? "1 item" : "\(count) items"
    }

    private static func imageMetadata(at url: URL) -> String? {
        #if canImport(ImageIO)
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = properties[kCGImagePropertyPixelWidth] as? Int,
            let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return fileSizeString(at: url) }

        let dimensions = "\(width)×\(height)"
        if let size = fileSizeString(at: url) {
            return "\(dimensions) · \(size)"
        }
        return dimensions
        #else
        return fileSizeString(at: url)
        #endif
    }

    private static func preview(_ text: String) -> String {
        let collapsed = text
            .split(whereSeparator: \.isNewline)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(collapsed.prefix(80))
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
