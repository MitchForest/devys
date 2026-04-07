// WorkspacePerformanceRecorder.swift
// Devys - Lightweight timing for perf-sensitive workspace interactions.

import Foundation
import OSLog

struct WorkspacePerformanceTrace {
    let id: String
    let name: String
    let startedAt: Date
    let context: [String: String]
}

struct WorkspacePerformanceCheckpoint {
    let name: String
    let markedAt: Date
}

enum WorkspacePerformanceRecorder {
    private static let logger = Logger(
        subsystem: "com.devys.mac-client",
        category: "WorkspacePerformance"
    )

    static func begin(
        _ name: String,
        context: [String: String] = [:]
    ) -> WorkspacePerformanceTrace {
        let trace = WorkspacePerformanceTrace(
            id: UUID().uuidString.lowercased(),
            name: name,
            startedAt: Date(),
            context: context
        )
        log(event: "begin", trace: trace, context: [:], outcome: nil)
        return trace
    }

    static func checkpoint(
        _ name: String,
        in trace: WorkspacePerformanceTrace,
        previous: WorkspacePerformanceCheckpoint? = nil,
        context: [String: String] = [:],
        outcome: String? = nil
    ) -> WorkspacePerformanceCheckpoint {
        let checkpoint = WorkspacePerformanceCheckpoint(name: name, markedAt: Date())
        let elapsedMilliseconds = milliseconds(since: trace.startedAt, to: checkpoint.markedAt)
        let deltaMilliseconds = previous.map { milliseconds(since: $0.markedAt, to: checkpoint.markedAt) }
        var resolvedContext = context
        resolvedContext["checkpoint"] = name
        resolvedContext["elapsed_ms"] = String(elapsedMilliseconds)
        if let deltaMilliseconds {
            resolvedContext["delta_ms"] = String(deltaMilliseconds)
        }
        log(event: "checkpoint", trace: trace, context: resolvedContext, outcome: outcome)
        return checkpoint
    }

    static func end(
        _ trace: WorkspacePerformanceTrace,
        outcome: String = "success",
        context: [String: String] = [:]
    ) {
        log(event: "end", trace: trace, context: context, outcome: outcome)
    }

    private static func log(
        event: String,
        trace: WorkspacePerformanceTrace,
        context: [String: String],
        outcome: String?
    ) {
        let durationMilliseconds = Int(Date().timeIntervalSince(trace.startedAt) * 1_000)
        let mergedContext = trace.context.merging(context) { _, newValue in newValue }
        let contextString = mergedContext
            .sorted { $0.key < $1.key }
            .map { key, value in "\(key)=\(value)" }
            .joined(separator: " ")

        var message = "\(event) trace=\(trace.name) trace_id=\(trace.id)"
        if !contextString.isEmpty {
            message += " \(contextString)"
        }
        if event == "end" {
            message += " duration_ms=\(durationMilliseconds)"
        }
        if let outcome {
            message += " outcome=\(outcome)"
        }

        logger.debug("\(message, privacy: .public)")
    }

    private static func milliseconds(since startDate: Date, to endDate: Date) -> Int {
        Int(endDate.timeIntervalSince(startDate) * 1_000)
    }
}
