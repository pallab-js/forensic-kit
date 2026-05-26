// SPEC: REQ-000 — ForensicKit library root; re-exports all public API
// SPEC: REQ-101 — ForensicEvent (see Models/ForensicEvent.swift)
// SPEC: REQ-102 — CollectionService (see Protocols/CollectionService.swift)
// SPEC: REQ-103 — ForensicError (see Errors/ForensicError.swift)
// SPEC: REQ-104 — EventPayload (see Models/EventPayload.swift)
// SPEC: REQ-105 — All types are Sendable (Swift 6 strict concurrency)

/// ForensicKit — macOS forensic data collection framework.
/// Built with Swift Package Manager. No Xcode required.
public enum ForensicKit {
    /// Semantic version of the library.
    public static let version = "0.1.0-phase1"
}
