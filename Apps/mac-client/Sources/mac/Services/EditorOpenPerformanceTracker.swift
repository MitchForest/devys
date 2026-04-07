// EditorOpenPerformanceTracker.swift
// Devys - Editor-open performance milestones and outcome classification.
//
// Copyright © 2026 Devys. All rights reserved.

import Foundation

enum EditorOpenPerformanceSnapshot: Equatable {
    case loading
    case previewText(fileSize: Int64?)
    case binary(fileSize: Int64?)
    case tooLarge(fileSize: Int64?)
    case loaded(fileSize: Int64?)
    case failed(fileSize: Int64?)
}

enum EditorOpenPerformanceEvent: Equatable {
    case checkpoint(name: String, context: [String: String])
    case finish(outcome: String, context: [String: String])
}

struct EditorOpenPerformanceTracker {
    private enum Checkpoint: String {
        case tabVisible = "tab-visible"
        case previewContentVisible = "preview-content-visible"
        case interactiveDocumentVisible = "interactive-document-visible"
    }

    private enum Outcome: String {
        case textLoaded = "text_loaded"
        case binary = "binary"
        case tooLarge = "too_large"
        case failed = "failed"
    }

    private(set) var fileSizeBucket = Self.fileSizeBucket(for: nil)
    private var hasMarkedTabVisible = false
    private var hasMarkedPreviewVisible = false
    private var hasMarkedInteractiveVisible = false
    private var hasFinished = false

    mutating func recordPresentation(
        _ snapshot: EditorOpenPerformanceSnapshot
    ) -> [EditorOpenPerformanceEvent] {
        guard !hasFinished else { return [] }

        updateFileSizeBucket(for: snapshot)

        var events = ensureTabVisible()

        switch snapshot {
        case .loading:
            return events
        case .previewText:
            events.append(contentsOf: ensurePreviewVisible())
            return events
        case .loaded:
            events.append(contentsOf: ensurePreviewVisible())
            events.append(contentsOf: ensureInteractiveVisible())
            events.append(contentsOf: finish(outcome: Outcome.textLoaded.rawValue))
            return events
        case .binary:
            events.append(contentsOf: finish(outcome: Outcome.binary.rawValue))
            return events
        case .tooLarge:
            events.append(contentsOf: finish(outcome: Outcome.tooLarge.rawValue))
            return events
        case .failed:
            events.append(contentsOf: finish(outcome: Outcome.failed.rawValue))
            return events
        }
    }

    mutating func finish(outcome: String) -> [EditorOpenPerformanceEvent] {
        guard !hasFinished else { return [] }
        hasFinished = true
        return [
            .finish(
                outcome: outcome,
                context: context()
            )
        ]
    }

    static func fileSizeBucket(for fileSize: Int64?) -> String {
        guard let fileSize else { return "unknown" }
        switch fileSize {
        case ...262_144:
            return "0_256kb"
        case ...1_048_576:
            return "256kb_1mb"
        case ...4_194_304:
            return "1mb_4mb"
        default:
            return "4mb_plus"
        }
    }

    private mutating func ensureTabVisible() -> [EditorOpenPerformanceEvent] {
        guard !hasMarkedTabVisible else { return [] }
        hasMarkedTabVisible = true
        return [
            .checkpoint(
                name: Checkpoint.tabVisible.rawValue,
                context: context()
            )
        ]
    }

    private mutating func ensurePreviewVisible() -> [EditorOpenPerformanceEvent] {
        guard !hasMarkedPreviewVisible else { return [] }
        hasMarkedPreviewVisible = true
        return [
            .checkpoint(
                name: Checkpoint.previewContentVisible.rawValue,
                context: context()
            )
        ]
    }

    private mutating func ensureInteractiveVisible() -> [EditorOpenPerformanceEvent] {
        guard !hasMarkedInteractiveVisible else { return [] }
        hasMarkedInteractiveVisible = true
        return [
            .checkpoint(
                name: Checkpoint.interactiveDocumentVisible.rawValue,
                context: context()
            )
        ]
    }

    private mutating func updateFileSizeBucket(for snapshot: EditorOpenPerformanceSnapshot) {
        switch snapshot {
        case .loading:
            return
        case .previewText(let fileSize),
             .binary(let fileSize),
             .tooLarge(let fileSize),
             .loaded(let fileSize),
             .failed(let fileSize):
            fileSizeBucket = Self.fileSizeBucket(for: fileSize)
        }
    }

    private func context() -> [String: String] {
        [
            "file_size_bucket": fileSizeBucket
        ]
    }
}
