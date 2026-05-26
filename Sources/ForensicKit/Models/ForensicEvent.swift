// SPEC: REQ-101 — ForensicEvent: Sendable, Codable, Identifiable value type
// SPEC: REQ-105 — Sendable conformance for Swift 6 strict concurrency

import Foundation

/// A single forensic observation captured during a collection run.
///
/// `ForensicEvent` is the canonical data unit flowing through the entire
/// ForensicKit pipeline — from collection services to the reporting layer.
/// It is immutable, value-typed, and safe to pass across concurrency domains.
public struct ForensicEvent: Sendable, Codable, Identifiable, Hashable {

    // MARK: - Core Fields

    /// Globally unique identifier for this event instance.
    public let id: UUID

    /// Wall-clock time at which the event was observed.
    public let timestamp: Date

    /// Operational severity of the event.
    public let severity: Severity

    /// Which subsystem produced this event.
    public let source: Source

    /// The structured payload carrying event-specific data.
    public let payload: EventPayload

    // MARK: - Init

    /// Creates a new `ForensicEvent`.
    ///
    /// - Parameters:
    ///   - id: Unique event ID. Defaults to a new `UUID`.
    ///   - timestamp: Observation time. Defaults to `Date()`.
    ///   - severity: Operational severity.
    ///   - source: Originating subsystem.
    ///   - payload: Event-specific structured data.
    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        severity: Severity,
        source: Source,
        payload: EventPayload
    ) {
        self.id = id
        self.timestamp = timestamp
        self.severity = severity
        self.source = source
        self.payload = payload
    }
}

// MARK: - Nested Types

extension ForensicEvent {

    /// Operational severity levels for forensic events.
    // SPEC: REQ-101 — Severity nested type
    public enum Severity: String, Sendable, Codable, CaseIterable, Hashable {
        /// Routine informational observation.
        case info
        /// Anomalous condition worth reviewing.
        case warning
        /// High-priority indicator requiring immediate attention.
        case critical
    }

    /// The subsystem that produced a forensic event.
    // SPEC: REQ-101 — Source nested type
    public enum Source: String, Sendable, Codable, CaseIterable, Hashable {
        /// Process-tree activity.
        case process
        /// Memory usage and allocation.
        case memory
        /// Network connections and sockets.
        case network
        /// File system access and metadata.
        case filesystem
        /// OS-level system events.
        case system
    }
}
