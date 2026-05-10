import SwiftUI
import UI

@MainActor
public struct DiffDocumentView: View {
    @Environment(\.colorScheme) private var colorScheme

    private let filePath: String
    private let snapshot: DiffSnapshot?
    private let mode: DiffViewMode
    private let isLoading: Bool
    private let errorMessage: String?
    private let isStaged: Bool
    private let statusMessage: String?
    private let onAcceptHunk: ((Int) async -> Void)?
    private let onRejectHunk: ((Int) async -> Void)?

    @State private var showWordDiff = true
    @State private var showLineNumbers = true
    @State private var wrapLines = false
    @State private var changeStyle: DiffChangeStyle = .fullBackground

    public init(
        filePath: String,
        snapshot: DiffSnapshot?,
        mode: DiffViewMode,
        isLoading: Bool,
        errorMessage: String?,
        isStaged: Bool,
        statusMessage: String?,
        onAcceptHunk: ((Int) async -> Void)? = nil,
        onRejectHunk: ((Int) async -> Void)? = nil
    ) {
        self.filePath = filePath
        self.snapshot = snapshot
        self.mode = mode
        self.isLoading = isLoading
        self.errorMessage = errorMessage
        self.isStaged = isStaged
        self.statusMessage = statusMessage
        self.onAcceptHunk = onAcceptHunk
        self.onRejectHunk = onRejectHunk
    }

    public var body: some View {
        let codeViewDesign = CodeViewDesign.resolved(for: colorScheme)

        Group {
            if let errorMessage, !errorMessage.isEmpty {
                ContentUnavailableView(
                    "Cannot Open Diff",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if let statusMessage, !statusMessage.isEmpty {
                ContentUnavailableView(
                    "Diff Unavailable",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(statusMessage)
                )
            } else if let snapshot {
                if snapshot.isBinary {
                    ContentUnavailableView(
                        "Binary File",
                        systemImage: "doc.zipper",
                        description: Text("This file is binary and cannot be displayed as a diff.")
                    )
                } else if !snapshot.hasChanges {
                    ContentUnavailableView(
                        "No Changes",
                        systemImage: "checkmark.circle",
                        description: Text("This file has no changes.")
                    )
                } else {
                    MetalDiffView(
                        snapshot: snapshot,
                        filePath: filePath,
                        mode: mode,
                        configuration: DiffRenderConfiguration(
                            fontName: codeViewDesign.fontName,
                            fontSize: codeViewDesign.fontSize,
                            lineHeight: codeViewDesign.lineHeight,
                            surfaceDesign: codeViewDesign.surfaceDesign,
                            showLineNumbers: showLineNumbers,
                            showPrefix: true,
                            showWordDiff: showWordDiff,
                            wrapLines: wrapLines,
                            changeStyle: changeStyle,
                            showsHunkHeaders: false
                        ),
                        isStaged: isStaged,
                        onAcceptHunk: onAcceptHunk,
                        onRejectHunk: onRejectHunk
                    )
                }
            } else if isLoading {
                ProgressView()
            } else {
                ContentUnavailableView("No Diff", systemImage: "doc.text.magnifyingglass")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
